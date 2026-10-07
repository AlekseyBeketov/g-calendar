#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/g-calendar/native-ui-tests"
mkdir -p "$BUILD_DIR"
source "$ROOT/scripts/swift-toolchain.sh"
configure_swift_compiler "$BUILD_DIR"
"${G_CALENDAR_SWIFT[@]}" -O -parse-as-library -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  "$ROOT/Sources/GCalendar/Models.swift" \
  "$ROOT/Sources/GCalendar/CalendarLayout.swift" \
  "$ROOT/Sources/GCalendar/RuntimeModes.swift" \
  "$ROOT/Sources/GCalendar/DemoPerformanceProbe.swift" \
  "$ROOT/Sources/GCalendar/GWSClient.swift" \
  "$ROOT/Sources/GCalendar/Cache.swift" \
  "$ROOT/Sources/GCalendar/Reminders.swift" \
  "$ROOT/Sources/GCalendar/TaskKeyboardNavigation.swift" \
  "$ROOT/Sources/GCalendar/TaskKeyboardFocusView.swift" \
  "$ROOT/Sources/GCalendar/WorkspaceSearchField.swift" \
  "$ROOT/Sources/GCalendar/CalendarScrollOffsetObserver.swift" \
  "$ROOT/Tests/NativeUIInvariantTests.swift" -o "$BUILD_DIR/native-ui-tests"
"$BUILD_DIR/native-ui-tests"
