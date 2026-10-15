#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="${1:-$ROOT/resources/AppIcon.icns}"
mkdir -p "$ROOT/.build/icon-tests"
TEMP="$(mktemp -d "$ROOT/.build/icon-tests/run.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
source "$ROOT/scripts/swift-toolchain.sh"
configure_swift_compiler "$ROOT/.build/icon-tests"
"${G_CALENDAR_SWIFT[@]}" "$ROOT/Tests/AppIconTests.swift" -o "$TEMP/check-icon"
/usr/bin/iconutil -c iconset -o "$TEMP/decoded.iconset" "$ICON"
"$TEMP/check-icon" "$ROOT/resources/AppIcon.png" "$TEMP/decoded.iconset"
