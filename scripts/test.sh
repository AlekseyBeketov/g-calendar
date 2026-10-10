#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/g-calendar/tests"
TEST_BINARY="$BUILD_DIR/g-calendar-invariant-tests"
mkdir -p "$BUILD_DIR"
chmod +x "$ROOT/Tests/Fixtures/sleeping-gws.sh"
source "$ROOT/scripts/swift-toolchain.sh"
configure_swift_compiler "$BUILD_DIR"

TEST_OPTIMIZATION="-Onone"
if [[ "${G_CALENDAR_TEST_OPTIMIZE:-0}" == "1" ]]; then TEST_OPTIMIZATION="-O"; fi
"${G_CALENDAR_SWIFT[@]}" "$TEST_OPTIMIZATION" -parse-as-library -swift-version 5 -target arm64-apple-macosx13.0 \
  -framework UserNotifications -framework ServiceManagement \
  "$ROOT/Sources/GCalendar/LoginItemSettings.swift" \
  "$ROOT/Sources/GCalendar/Models.swift" \
  "$ROOT/Sources/GCalendar/CalendarLayout.swift" \
  "$ROOT/Sources/GCalendar/TaskKeyboardNavigation.swift" \
  "$ROOT/Sources/GCalendar/ShortcutSettings.swift" \
  "$ROOT/Sources/GCalendar/ThemePalette.swift" \
  "$ROOT/Sources/GCalendar/RefreshCoordinator.swift" \
  "$ROOT/Sources/GCalendar/GWSClient.swift" \
  "$ROOT/Sources/GCalendar/Cache.swift" \
  "$ROOT/Sources/GCalendar/RuntimeModes.swift" \
  "$ROOT/Sources/GCalendar/Reminders.swift" \
  "$ROOT/Sources/GCalendar/MutationService.swift" \
  "$ROOT/Sources/GCalendar/MutationRecovery.swift" \
  "$ROOT/Sources/GCalendar/SyntheticAcceptance.swift" \
  "$ROOT/Sources/GCalendar/LedgerAcceptance.swift" \
  "$ROOT/Tests/InvariantTests.swift" \
  -o "$TEST_BINARY"

G_CALENDAR_FIXTURES="$ROOT/Tests/Fixtures" "$TEST_BINARY"
