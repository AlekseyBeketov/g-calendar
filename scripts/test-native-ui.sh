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
  "$ROOT/Sources/GCalendar/CalendarTimeGrid.swift" \
  "$ROOT/Sources/GCalendar/RuntimeModes.swift" \
  "$ROOT/Sources/GCalendar/DemoPerformanceProbe.swift" \
  "$ROOT/Sources/GCalendar/GWSClient.swift" \
  "$ROOT/Sources/GCalendar/Cache.swift" \
  "$ROOT/Sources/GCalendar/Reminders.swift" \
  "$ROOT/Sources/GCalendar/TaskKeyboardNavigation.swift" \
  "$ROOT/Sources/GCalendar/TaskKeyboardFocusView.swift" \
  "$ROOT/Sources/GCalendar/WorkspaceSearchField.swift" \
  "$ROOT/Sources/GCalendar/CalendarScrollOffsetObserver.swift" \
  "$ROOT/Sources/GCalendar/ThemePalette.swift" \
  "$ROOT/Sources/GCalendar/AppTheme.swift" \
  "$ROOT/Sources/GCalendar/WorkspaceToolbar.swift" \
  "$ROOT/Tests/WorkspaceToolbarNativeTests.swift" \
  "$ROOT/Tests/CalendarTimedCardNativeTests.swift" \
  "$ROOT/Tests/NativeUIInvariantTests.swift" -o "$BUILD_DIR/native-ui-tests"
# Optional: G_CALENDAR_NATIVE_EVIDENCE_DIR writes synthetic toolbar PNGs and bounds.txt.
"$BUILD_DIR/native-ui-tests"
