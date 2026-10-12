#!/usr/bin/env bash
# Local, derived indexes. No API calls or Git hooks are required.
set -euo pipefail

usage() {
  echo "Usage: $0 [--force]"
}

force=()
case "${1:-}" in
  "") ;;
  --force) force=(--force) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then usage >&2; exit 2; fi

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
index_root="$repo/.local-indexes"
graphify_bin="${GRAPHIFY_BIN:-graphify}"
tgrep_bin="${TGREP_BIN:-tgrep}"
for tool in "$graphify_bin" "$tgrep_bin" python3 git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool unavailable: $tool" >&2
    exit 1
  fi
done

mkdir -p "$index_root"
if [[ ! -w "$index_root" ]]; then
  echo "Index directory is not writable: $index_root" >&2
  exit 1
fi
if ! mkdir "$index_root/.lock" 2>/dev/null; then
  echo "Indexing is already running, or a stale lock remains: $index_root/.lock" >&2
  exit 1
fi
# Graphify 0.9.56 can write its stat cache under the corpus despite --out.
# Relocate only that known auxiliary file; never remove other corpus output.
relocate_stat_cache() {
  local stray="$repo/graphify-out/cache/stat-index.json"
  if [[ -f "$stray" && ! -L "$stray" && ! -L "$repo/graphify-out" && ! -L "$repo/graphify-out/cache" ]]; then
    mkdir -p "$index_root/graphify/graphify-out/cache"
    mv "$stray" "$index_root/graphify/graphify-out/cache/corpus-stat-index.json"
    rmdir "$repo/graphify-out/cache" "$repo/graphify-out" 2>/dev/null || true
  fi
}
trap 'relocate_stat_cache; rm -f "$index_root/.snapshot.json"; rmdir "$index_root/.lock"' EXIT

# Invalidate readiness before any mutation; a failed run must not retain a ready manifest.
rm -f "$index_root/manifest.json"
python3 - "$repo" "$index_root/.snapshot.json" <<'PY'
import hashlib, json, pathlib, subprocess, sys
repo, destination = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
def git(*args):
    return subprocess.check_output(['git', '-C', str(repo), *args])
paths = sorted(set(git('ls-files', '-z', '--cached', '--others', '--exclude-standard').split(b'\0')) - {b''})
digest = hashlib.sha256()
for raw in paths:
    path = repo / raw.decode('utf-8', 'surrogateescape')
    digest.update(raw + b'\0')
    digest.update(path.read_bytes() if path.is_file() else b'<missing>')
snapshot = {'head': git('rev-parse', 'HEAD').decode().strip(),
            'status': git('status', '--porcelain=v1', '--untracked-files=all').decode(),
            'source_sha256': digest.hexdigest()}
destination.write_text(json.dumps(snapshot))
PY

echo "Updating Graphify in $index_root/graphify"
if ! (cd "$index_root" && "$graphify_bin" extract "$repo" --code-only --no-cluster \
    --out "$index_root/graphify" "${force[@]}"); then
  echo "Graphify failed; indexes are not ready." >&2
  exit 1
fi
relocate_stat_cache

echo "Updating tgrep in $index_root/tgrep"
if ! "$tgrep_bin" index "$repo" --index-path "$index_root/tgrep" "${force[@]}" \
    --exclude node_modules --exclude bin --exclude obj --exclude .git \
    --exclude .codegraph --exclude .hermes --exclude .local-indexes \
    --exclude .worktrees --exclude .build --exclude .swiftpm --exclude dist \
    --exclude DerivedData --exclude build --exclude graphify-out; then
  echo "Graphify completed, but tgrep failed; indexes are only partially updated." >&2
  exit 1
fi

python3 - "$repo" "$index_root" "$graphify_bin" "$tgrep_bin" "${1:-incremental}" <<'PY'
import datetime, hashlib, json, pathlib, subprocess, sys
repo, root = map(pathlib.Path, sys.argv[1:3])
graph = json.loads((root / 'graphify/graphify-out/graph.json').read_text())
nodes, edges = graph.get('nodes'), graph.get('edges', graph.get('links'))
if not isinstance(nodes, list) or not nodes or not isinstance(edges, list) or not edges:
    raise SystemExit('Graphify validation failed: non-empty nodes and edges/links are required.')
source_paths = set()
for item in nodes + edges:
    source = item.get('source_file')
    if not source:
        continue
    path = pathlib.Path(source)
    path = (path if path.is_absolute() else repo / path).resolve()
    if not path.is_relative_to(repo) or path.is_relative_to(root) or not path.is_file():
        raise SystemExit(f'Graphify validation failed: invalid source path {source}')
    source_paths.add(str(path.relative_to(repo)))
if not source_paths:
    raise SystemExit('Graphify validation failed: no repository source paths.')
meta = json.loads((root / 'tgrep/meta.json').read_text())
if meta.get('root_path') != str(repo) or meta.get('complete') is not True:
    raise SystemExit('tgrep validation failed: root_path mismatch or incomplete index.')
snapshot = json.loads((root / '.snapshot.json').read_text())
def git(*args):
    return subprocess.check_output(['git', '-C', str(repo), *args])
paths = sorted(set(git('ls-files', '-z', '--cached', '--others', '--exclude-standard').split(b'\0')) - {b''})
digest = hashlib.sha256()
for raw in paths:
    path = repo / raw.decode('utf-8', 'surrogateescape')
    digest.update(raw + b'\0')
    digest.update(path.read_bytes() if path.is_file() else b'<missing>')
if digest.hexdigest() != snapshot['source_sha256'] or git('rev-parse', 'HEAD').decode().strip() != snapshot['head']:
    raise SystemExit('Source changed during indexing; rerun ./scripts/index-code.sh to verify a stable snapshot.')
manifest = {'schema_version': 1, 'repository': str(repo), 'worktree_key': hashlib.sha256(str(repo).encode()).hexdigest()[:16],
            'built_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'mode': sys.argv[5],
            'git': snapshot, 'tools': {name: subprocess.check_output([binary, '--version'], text=True).strip()
                                    for name, binary in zip(('graphify', 'tgrep'), sys.argv[3:5])},
            'graphify': {'path': 'graphify/graphify-out/graph.json', 'nodes': len(nodes), 'edges': len(edges),
                         'source_files': len(source_paths), 'swift_source_files': sum(p.endswith('.swift') for p in source_paths)},
            'tgrep': {'path': 'tgrep', 'root_path': meta['root_path'], 'complete': True}, 'verified': True}
temporary = root / 'manifest.json.tmp'
temporary.write_text(json.dumps(manifest, indent=2) + '\n')
temporary.replace(root / 'manifest.json')
print(f"Indexes verified: {len(nodes)} nodes, {len(edges)} edges, {len(source_paths)} source files; {root / 'manifest.json'}")
PY
