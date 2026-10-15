#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/g-calendar.app"
ICON="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist")"
DIGEST="$(/usr/bin/shasum -a 256 "$ROOT/resources/AppIcon.icns" | /usr/bin/cut -d ' ' -f 1)"
[[ "$ICON" == "WorkspaceIcon-${DIGEST:0:12}" ]]
/usr/bin/cmp "$ROOT/resources/AppIcon.icns" "$APP/Contents/Resources/$ICON.icns"
"$ROOT/scripts/test-icon-representations.sh" "$APP/Contents/Resources/$ICON.icns"
"$ROOT/scripts/verify-release.sh" --app "$APP" --mode local
TEMP="$(mktemp -d "$ROOT/.build/.icon-contract.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
/usr/bin/ditto "$APP" "$TEMP/fixture.bundle"
mv "$TEMP/fixture.bundle/Contents/Resources/$ICON.icns" "$TEMP/fixture.bundle/Contents/Resources/WorkspaceIcon.icns"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile WorkspaceIcon' "$TEMP/fixture.bundle/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier com.alexbeketov.gcalendar "$TEMP/fixture.bundle" >/dev/null 2>&1
if "$ROOT/scripts/verify-release.sh" --app "$TEMP/fixture.bundle" --mode local >"$TEMP/rejected.log" 2>&1; then
  echo 'FAIL mutable icon filename accepted'; exit 1
fi
/usr/bin/grep -q 'Icon resource name must identify its artwork revision' "$TEMP/rejected.log"
echo 'PASS exact approved icon bytes, artwork-specific filename and rejection of a reused resource name'
echo 'Visible notification icon still requires human confirmation; this test does not schedule notifications.'
