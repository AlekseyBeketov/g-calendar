#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/g-calendar/author-support-tests"
mkdir -p "$BUILD_DIR"
source "$ROOT/scripts/swift-toolchain.sh"
configure_swift_compiler "$BUILD_DIR"
"${G_CALENDAR_SWIFT[@]}" -O -parse-as-library -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework Vision \
  "$ROOT/Sources/GCalendar/AuthorSupport.swift" \
  "$ROOT/Sources/GCalendar/AuthorSupportView.swift" \
  "$ROOT/Sources/GCalendar/ThemePalette.swift" \
  "$ROOT/Sources/GCalendar/AppTheme.swift" \
  "$ROOT/Sources/GCalendar/PointerCursor.swift" \
  "$ROOT/Tests/AuthorSupportTests.swift" -o "$BUILD_DIR/author-support-tests"
G_CALENDAR_SUPPORT_RESOURCES="$ROOT/Resources/AuthorSupport" \
G_CALENDAR_SUPPORT_EVIDENCE="$BUILD_DIR/evidence" "$BUILD_DIR/author-support-tests"
