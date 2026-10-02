#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/g-calendar/read-only-smoke"
BINARY="$BUILD_DIR/read-only-smoke"
mkdir -p "$BUILD_DIR"

swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx13.0 \
  "$ROOT/Sources/GCalendar/Models.swift" \
  "$ROOT/Sources/GCalendar/GWSClient.swift" \
  "$ROOT/Sources/GCalendar/Cache.swift" \
  "$ROOT/scripts/ReadOnlySmoke.swift" \
  -o "$BINARY"

"$BINARY"
