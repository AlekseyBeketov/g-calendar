#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/g-calendar.app"; OUTPUT=""
fail() { printf 'Signing failed: %s\n' "$1" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:?Missing app}"; shift 2 ;;
    --output) OUTPUT="${2:?Missing signed app path}"; shift 2 ;;
    --help) printf '%s\n' 'Usage: sign-release.sh [--app PATH] --output NEW_APP_PATH'; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done
: "${G_CALENDAR_SIGN_IDENTITY:?Set explicit Developer ID Application identity}"
: "${G_CALENDAR_TEAM_ID:?Set expected Developer ID Team ID}"
[[ -n "$OUTPUT" && "$OUTPUT" == *.app && ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || fail 'Output must be a new .app path'
"$ROOT/scripts/verify-release.sh" --app "$APP" --mode local
# Current bundle has one executable. Future nested code needs an explicit inside-out signing plan.
for DIRECTORY in Frameworks PlugIns XPCServices Helpers; do
  [[ ! -e "$APP/Contents/$DIRECTORY" ]] || fail 'Nested code found; explicit signing order required'
done
mkdir -p "$(dirname "$OUTPUT")"
STAGE="$(mktemp -d "$(dirname "$OUTPUT")/.sign.XXXXXX")"
chmod 700 "$STAGE"
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto "$APP" "$STAGE/g-calendar.app"
/usr/bin/codesign --force --sign "$G_CALENDAR_SIGN_IDENTITY" --options runtime --timestamp --identifier com.alexbeketov.gcalendar "$STAGE/g-calendar.app"
"$ROOT/scripts/verify-release.sh" --app "$STAGE/g-calendar.app" --mode signed --signature-only
mv "$STAGE/g-calendar.app" "$OUTPUT"
printf 'SIGNED_APP=%s\nNOTARIZATION_PENDING=true\n' "$OUTPUT"
