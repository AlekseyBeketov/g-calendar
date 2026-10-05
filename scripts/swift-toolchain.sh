#!/bin/bash
# Configure only this compiler process; never change the installed toolchain.
configure_swift_compiler() {
  local cache_root="$1"
  local compiler toolchain_usr legacy_map modern_map legacy_body modern_body
  compiler="$(/usr/bin/xcrun --find swiftc)"
  toolchain_usr="$(cd "$(dirname "$compiler")/.." && pwd)"
  legacy_map="$toolchain_usr/include/swift/module.modulemap"
  modern_map="$toolchain_usr/include/swift/bridging.modulemap"
  mkdir -p "$cache_root/ModuleCache"
  G_CALENDAR_SWIFT=(/usr/bin/swiftc -module-cache-path "$cache_root/ModuleCache")

  # Some mixed CLT installations retain the old implicit map as well as the
  # driver's explicit bridging map. Hide the old map only if their bodies match.
  if [[ -f "$legacy_map" && -f "$modern_map" ]]; then
    legacy_body="$(sed '/^[[:space:]]*\/\//d; /^[[:space:]]*$/d' "$legacy_map")"
    modern_body="$(sed '/^[[:space:]]*\/\//d; /^[[:space:]]*$/d' "$modern_map")"
    if [[ "$legacy_body" == "$modern_body" && "$modern_body" == *"module SwiftBridging"* ]]; then
      local overlay_dir legacy_json empty_json
      overlay_dir="$cache_root/toolchain-overlay"
      mkdir -p "$overlay_dir"
      printf '%s\n' '// Duplicate legacy map hidden for this compiler process only.' > "$overlay_dir/empty.modulemap"
      legacy_json="$(printf '%s' "$legacy_map" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      empty_json="$(printf '%s' "$overlay_dir/empty.modulemap" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      printf '{"version":0,"roots":[{"type":"file","name":"%s","external-contents":"%s"}]}\n' \
        "$legacy_json" "$empty_json" > "$overlay_dir/overlay.json"
      G_CALENDAR_SWIFT+=(-Xcc -ivfsoverlay -Xcc "$overlay_dir/overlay.json")
      printf '%s\n' 'Using a process-local overlay for duplicate SwiftBridging maps.' >&2
    fi
  fi
}
