#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=2.10.0
SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
BASE="$ROOT/.build/dependencies"
ARCHIVE="$BASE/sparkle-$VERSION.tar.xz"
DESTINATION="$BASE/sparkle-$VERSION"
mkdir -p "$BASE"
if [[ ! -f "$ARCHIVE" ]]; then
  TEMP="$(mktemp "$BASE/.sparkle-download.XXXXXX")"
  trap 'rm -f "$TEMP"' EXIT
  /usr/bin/curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 180 --retry 2 --max-filesize 33554432 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$TEMP"
  [[ "$(/usr/bin/shasum -a 256 "$TEMP" | /usr/bin/cut -d ' ' -f 1)" == "$SHA256" ]] || { echo 'Sparkle checksum mismatch' >&2; exit 1; }
  mv "$TEMP" "$ARCHIVE"
fi
[[ "$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/cut -d ' ' -f 1)" == "$SHA256" ]] || { echo 'Sparkle cache checksum mismatch' >&2; exit 1; }
if [[ -f "$DESTINATION/.archive-sha256" && "$(cat "$DESTINATION/.archive-sha256")" == "$SHA256" ]]; then
  /usr/bin/codesign --verify --deep --strict "$DESTINATION/Sparkle.framework"
  printf '%s\n' "$DESTINATION"
  exit 0
fi
LOCK="$BASE/.sparkle-extract-lock"
mkdir "$LOCK" 2>/dev/null || { echo 'Sparkle extraction is already running; retry when it finishes.' >&2; exit 1; }
STAGE="$(mktemp -d "$BASE/.sparkle-extract.XXXXXX")"
trap 'rm -rf "$STAGE"; rmdir "$LOCK"' EXIT
/usr/bin/tar -xf "$ARCHIVE" -C "$STAGE"
/usr/bin/codesign --verify --deep --strict "$STAGE/Sparkle.framework"
rm -rf "$DESTINATION"
mv "$STAGE" "$DESTINATION"
printf '%s\n' "$SHA256" > "$DESTINATION/.archive-sha256"
rmdir "$LOCK"
trap - EXIT
printf '%s\n' "$DESTINATION"
