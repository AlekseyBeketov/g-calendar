#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$#" -gt 1 || ( "$#" == 1 && "${1:-}" != "--live-read-only" ) ]]; then
  printf '%s\n' 'Usage: scripts/benchmark-transports.sh [--live-read-only]' >&2
  exit 2
fi
BUILD_DIR="$ROOT/.build/g-calendar/transport-benchmark"
mkdir -p "$BUILD_DIR"
source "$ROOT/scripts/swift-toolchain.sh"
configure_swift_compiler "$BUILD_DIR"
"${G_CALENDAR_SWIFT[@]}" -O -D G_CALENDAR_TEST -parse-as-library -swift-version 5 -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework UserNotifications -framework ServiceManagement -framework Security \
  "$ROOT/Sources/GCalendar/LoginItemSettings.swift" \
  "$ROOT/Sources/GCalendar/Models.swift" \
  "$ROOT/Sources/GCalendar/CalendarRangeCache.swift" \
  "$ROOT/Sources/GCalendar/CalendarLayout.swift" \
  "$ROOT/Sources/GCalendar/CalendarProjection.swift" \
  "$ROOT/Sources/GCalendar/CalendarPresentation.swift" \
  "$ROOT/Sources/GCalendar/TaskKeyboardNavigation.swift" \
  "$ROOT/Sources/GCalendar/ShortcutSettings.swift" \
  "$ROOT/Sources/GCalendar/ThemePalette.swift" \
  "$ROOT/Sources/GCalendar/RefreshCoordinator.swift" \
  "$ROOT/Sources/GCalendar/GWSClient.swift" \
  "$ROOT/Sources/GCalendar/GoogleRESTTransport.swift" \
  "$ROOT/Sources/GCalendar/GoogleOAuth.swift" \
  "$ROOT/Sources/GCalendar/GoogleAccountProfile.swift" \
  "$ROOT/Sources/GCalendar/WorkspaceTransport.swift" \
  "$ROOT/Sources/GCalendar/WorkspaceSnapshotReducer.swift" \
  "$ROOT/Sources/GCalendar/Cache.swift" \
  "$ROOT/Sources/GCalendar/RuntimeModes.swift" \
  "$ROOT/Sources/GCalendar/Reminders.swift" \
  "$ROOT/Sources/GCalendar/MutationService.swift" \
  "$ROOT/Sources/GCalendar/MutationRecovery.swift" \
  "$ROOT/Sources/GCalendar/SyntheticAcceptance.swift" \
  "$ROOT/Sources/GCalendar/LedgerAcceptance.swift" \
  "$ROOT/benchmarks/TransportComparison.swift" \
  -o "$BUILD_DIR/transport-benchmark"
ARCHIVE_REVISION="$(cat "$ROOT/benchmarks/source-revision.txt")"
if [[ "$ARCHIVE_REVISION" =~ ^[0-9a-f]{40}$ ]]; then
  G_CALENDAR_BENCHMARK_COMMIT="$ARCHIVE_REVISION"
else
  G_CALENDAR_BENCHMARK_COMMIT="$(rtk git -C "$ROOT" rev-parse HEAD)"
fi
G_CALENDAR_BENCHMARK_SWIFT="$("${G_CALENDAR_SWIFT[@]}" --version)"
export G_CALENDAR_BENCHMARK_COMMIT G_CALENDAR_BENCHMARK_SWIFT
"$BUILD_DIR/transport-benchmark" "$ROOT/benchmarks/transport-config.json" "${1:-}"
