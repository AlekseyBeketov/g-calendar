#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/g-calendar.app"
BUILD_ROOT="$ROOT/.build/g-calendar"
BUILD_DIR="$BUILD_ROOT/run-$$"
STAGE="$BUILD_DIR/g-calendar.app"
BACKUP=""

restore_previous_app() {
  if [[ -n "$BACKUP" && -e "$BACKUP" && ! -e "$APP" ]]; then
    mv "$BACKUP" "$APP"
  fi
}
trap restore_previous_app EXIT

mkdir -p "$BUILD_DIR" "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
source "$ROOT/scripts/swift-toolchain.sh"
configure_swift_compiler "$BUILD_ROOT"

if [[ -e "$APP" && ! -f "$APP/Contents/Resources/g-calendar-build-origin.txt" ]]; then
  printf '%s\n' "Refusing to replace an app bundle not created by scripts/build-app.sh: $APP" >&2
  exit 2
fi

cp "$ROOT/resources/AppIcon.icns" "$STAGE/Contents/Resources/WorkspaceIcon.icns"

SOURCE_FILES=("$ROOT"/Sources/GCalendar/*.swift)
OPTIMIZATION="-O"
if [[ "${G_CALENDAR_DEBUG_BUILD:-0}" == "1" ]]; then OPTIMIZATION="-Onone"; fi
"${G_CALENDAR_SWIFT[@]}" "$OPTIMIZATION" -parse-as-library -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  "${SOURCE_FILES[@]}" -o "$STAGE/Contents/MacOS/g-calendar"

cp "$ROOT/resources/Info.plist" "$STAGE/Contents/Info.plist"
printf '%s\n' 'built-by=scripts/build-app.sh' > "$STAGE/Contents/Resources/g-calendar-build-origin.txt"
/usr/bin/plutil -lint "$STAGE/Contents/Info.plist"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGE/Contents/Info.plist")"
if [[ -z "$BUNDLE_IDENTIFIER" ]]; then
  printf '%s\n' "CFBundleIdentifier is missing from Info.plist" >&2
  exit 2
fi
# Use a local ad-hoc signature whose identifier matches the app bundle.
# This is not Developer ID signing, notarization, or a release signature.
/usr/bin/codesign --force --sign - --identifier "$BUNDLE_IDENTIFIER" "$STAGE"
/usr/bin/codesign --verify --strict "$STAGE"

if [[ -e "$APP" ]]; then
  BACKUP="$BUILD_DIR/previous-g-calendar.app"
  mv "$APP" "$BACKUP"
fi
mv "$STAGE" "$APP"
BACKUP=""
printf 'APP_BUNDLE=%s\n' "$APP"
/usr/bin/file "$APP/Contents/MacOS/g-calendar"
