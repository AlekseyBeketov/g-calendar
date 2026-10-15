#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/g-calendar/task-workspace-ui-tests"
mkdir -p "$BUILD_DIR"
source "$ROOT/scripts/swift-toolchain.sh"
configure_swift_compiler "$BUILD_DIR"
SPARKLE_ROOT="$("$ROOT/scripts/fetch-sparkle.sh")"
"${G_CALENDAR_SWIFT[@]}" -Onone -D G_CALENDAR_TEST -D G_CALENDAR_TASK_LAYOUT_TEST \
  -parse-as-library -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework UserNotifications -framework ServiceManagement \
  -F "$SPARKLE_ROOT" -framework Sparkle -Xlinker -rpath -Xlinker "$SPARKLE_ROOT" \
  "$ROOT"/Sources/GCalendar/*.swift "$ROOT/Tests/TaskWorkspaceNativeTests.swift" \
  -o "$BUILD_DIR/task-workspace-ui-tests"
"$BUILD_DIR/task-workspace-ui-tests"
