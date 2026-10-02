#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/g-calendar/tests"
TEST_BINARY="$BUILD_DIR/g-calendar-invariant-tests"
mkdir -p "$BUILD_DIR"
chmod +x "$ROOT/Tests/Fixtures/sleeping-gws.sh"

swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx13.0 \
  -framework UserNotifications \
  "$ROOT/Sources/GCalendar/Models.swift" \
  "$ROOT/Sources/GCalendar/CalendarLayout.swift" \
  "$ROOT/Sources/GCalendar/GWSClient.swift" \
  "$ROOT/Sources/GCalendar/Cache.swift" \
  "$ROOT/Sources/GCalendar/RuntimeModes.swift" \
  "$ROOT/Sources/GCalendar/Reminders.swift" \
  "$ROOT/Sources/GCalendar/MutationService.swift" \
  "$ROOT/Tests/InvariantTests.swift" \
  -o "$TEST_BINARY"

G_CALENDAR_FIXTURES="$ROOT/Tests/Fixtures" "$TEST_BINARY"
