#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/g-calendar.app"
RENEW_CURRENT=false
for ARG in "$@"; do
  case "$ARG" in
    --renew-current) RENEW_CURRENT=true ;;
    --help) echo 'refresh-app-registration.sh [--renew-current]'; exit 0 ;;
    *) echo "Unknown argument: $ARG" >&2; exit 2 ;;
  esac
done
REGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$REGISTER" && -d "$APP" && ! -L "$APP" ]] || { echo 'Current application or Launch Services tool unavailable' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == com.alexbeketov.gcalendar ]]
/usr/bin/codesign --verify --deep --strict "$APP"
COUNT=0
while IFS= read -r OLD; do
  [[ -d "$OLD" && ! -L "$OLD" && -f "$OLD/Contents/Resources/g-calendar-build-origin.txt" ]] || continue
  [[ "$(cat "$OLD/Contents/Resources/g-calendar-build-origin.txt")" == built-by=scripts/build-app.sh ]] || continue
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$OLD/Contents/Info.plist")" == com.alexbeketov.gcalendar ]] || continue
  if ! RESULT="$("$REGISTER" -u "$OLD" 2>&1)"; then
    # An already-absent registration is a successful no-op, including races with Spotlight.
    [[ "$RESULT" == *'-10814'* ]] && continue
    printf '%s\n' "$RESULT" >&2
    exit 1
  fi
  COUNT=$((COUNT + 1))
done < <("$REGISTER" -dump | /usr/bin/awk -v root="$ROOT" '
  /^path:/ {path=$0; sub(/^path:[[:space:]]*/, "", path); sub(/ \(0x[0-9a-f]+\)$/, "", path)}
  /^identifier:[[:space:]]+com\.alexbeketov\.gcalendar$/ {
    if(index(path, root "/.build/g-calendar/run-")==1 && path ~ /\/previous-g-calendar\.app$/) print path
  }')
if [[ "$RENEW_CURRENT" == true ]]; then
  if ! RESULT="$("$REGISTER" -u "$APP" 2>&1)"; then
    [[ "$RESULT" == *'-10814'* ]] || { printf '%s\n' "$RESULT" >&2; exit 1; }
  fi
fi
"$REGISTER" -f "$APP"
printf 'REFRESHED_APP=%s\nUNREGISTERED_BUILD_BACKUPS=%s\n' "$APP" "$COUNT"
echo 'Relaunch this app to check a future notification; existing delivered banners may retain their cached icon.'
