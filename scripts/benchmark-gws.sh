#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" != "--live-read-only" || "$#" != "1" ]]; then
  printf '%s\n' 'Usage: scripts/benchmark-gws.sh --live-read-only (Google reads only, numbers only)' >&2
  exit 2
fi
BUILD_DIR="$ROOT/.build/g-calendar/read-benchmark"
mkdir -p "$BUILD_DIR"
source "$ROOT/scripts/swift-toolchain.sh"
configure_swift_compiler "$BUILD_DIR"
"${G_CALENDAR_SWIFT[@]}" -O -D G_CALENDAR_TEST -parse-as-library -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework UserNotifications -framework ServiceManagement \
  "$ROOT"/Sources/GCalendar/*.swift "$ROOT/benchmarks/GWSReadBenchmark.swift" \
  -o "$BUILD_DIR/read-benchmark"
"$BUILD_DIR/read-benchmark" --live-read-only
