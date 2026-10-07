#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=""; OUTPUT=""
fail() { printf 'Notarization failed: %s\n' "$1" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:?Missing signed app}"; shift 2 ;;
    --output) OUTPUT="${2:?Missing new output directory}"; shift 2 ;;
    --help) printf '%s\n' 'Usage: notarize-release.sh --app SIGNED_APP --output NEW_DIRECTORY'; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done
: "${G_CALENDAR_SIGN_IDENTITY:?Set explicit Developer ID Application identity}"
: "${G_CALENDAR_TEAM_ID:?Set expected Developer ID Team ID}"
: "${G_CALENDAR_NOTARY_PROFILE:?Set an existing notarytool Keychain profile}"
[[ -n "$OUTPUT" && ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || fail 'Output must be a new directory'
"$ROOT/scripts/verify-release.sh" --app "$APP" --mode signed --signature-only
mkdir -p "$(dirname "$OUTPUT")"
STAGE="$(mktemp -d "$(dirname "$OUTPUT")/.notarize.XXXXXX")"
chmod 700 "$STAGE"
trap 'rm -rf "$STAGE"' EXIT
submit() {
  # Credential/profile values and complete service responses are never printed.
  if ! /usr/bin/xcrun notarytool submit "$1" --keychain-profile "$G_CALENDAR_NOTARY_PROFILE" --wait --timeout 30m --output-format json > "$STAGE/notary-result.json" 2> "$STAGE/notary-error.txt"; then
    fail 'Apple submission failed; verify the existing Keychain profile and network'
  fi
  STATUS="$(/usr/bin/plutil -extract status raw -o - "$STAGE/notary-result.json")"
  [[ "$STATUS" == Accepted ]] || fail 'Apple did not accept the submitted archive'
}
/usr/bin/ditto "$APP" "$STAGE/g-calendar.app"
/usr/bin/ditto -c -k --keepParent "$STAGE/g-calendar.app" "$STAGE/submit.zip"
submit "$STAGE/submit.zip"
/usr/bin/xcrun stapler staple "$STAGE/g-calendar.app"
"$ROOT/scripts/verify-release.sh" --app "$STAGE/g-calendar.app" --mode signed
# Packaging recreates ZIP from the stapled app; ZIP itself cannot be stapled.
"$ROOT/scripts/package-dmg.sh" --app "$STAGE/g-calendar.app" --mode release --output "$STAGE/packages"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$STAGE/g-calendar.app/Contents/Info.plist")"
PREFIX="g-calendar-$VERSION-arm64"
submit "$STAGE/packages/$PREFIX.dmg"
/usr/bin/xcrun stapler staple "$STAGE/packages/$PREFIX.dmg"
/usr/bin/plutil -replace notarized -bool YES "$STAGE/packages/release-manifest.json"
# The final manifest and digest are written after every stapling/signing mutation.
(cd "$STAGE/packages" && /usr/bin/shasum -a 256 "$PREFIX.zip" "$PREFIX.dmg" release-manifest.json > SHA256SUMS)
"$ROOT/scripts/verify-release.sh" --app "$STAGE/g-calendar.app" --mode signed --artifacts "$STAGE/packages"
mv "$STAGE/packages" "$OUTPUT"
printf 'NOTARIZED_PACKAGES=%s\nCLEAN_MACHINE_ACCEPTANCE_PENDING=true\n' "$OUTPUT"
