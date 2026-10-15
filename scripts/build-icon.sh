#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.build/icon-tools"
TEMP="$(mktemp -d "$ROOT/.build/icon-tools/run.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
mkdir "$TEMP/AppIcon.iconset"
for base in 16 32 128 256 512; do
  for scale in 1 2; do
    suffix=""; if [[ "$scale" == 2 ]]; then suffix="@2x"; fi
    size="$((base * scale))"
    /usr/bin/sips -z "$size" "$size" "$ROOT/resources/AppIcon.png" \
      --out "$TEMP/AppIcon.iconset/icon_${base}x${base}${suffix}.png" >/dev/null
  done
done
# Let Apple's encoder write legacy small-icon formats; PNG chunks with legacy
# type codes are not interchangeable with a valid native ICNS representation.
/usr/bin/iconutil -c icns -o "$TEMP/AppIcon.icns" "$TEMP/AppIcon.iconset"
"$ROOT/scripts/test-icon-representations.sh" "$TEMP/AppIcon.icns"
cp "$TEMP/AppIcon.icns" "$ROOT/resources/AppIcon.icns"
printf '%s\n' 'Native ICNS rebuilt and all ten representations checked.'
