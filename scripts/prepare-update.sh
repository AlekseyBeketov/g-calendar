#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/g-calendar.app"; OUTPUT=""; NOTES=""
fail() { printf 'Update preparation failed: %s\n' "$1" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:?Missing app}"; shift 2;;
    --output) OUTPUT="${2:?Missing output}"; shift 2;;
    --notes) NOTES="${2:?Missing release notes}"; shift 2;;
    --help) echo 'prepare-update.sh --output NEW_DIRECTORY --notes FILE [--app APP]'; exit 0;;
    *) fail "Unknown argument: $1";;
  esac
done
[[ -n "$OUTPUT" && ! -e "$OUTPUT" && -f "$NOTES" ]] || fail 'A fresh output directory and release notes file are required'
SPARKLE_ROOT="$("$ROOT/scripts/fetch-sparkle.sh")"
PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Invalid app version'
PUBLIC_KEY="$("$SPARKLE_ROOT/bin/generate_keys" --account g-calendar -p)"
[[ "$PUBLIC_KEY" == "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")" ]] || fail 'The signing key in Keychain does not match this application'
"$ROOT/scripts/package-dmg.sh" --app "$APP" --output "$OUTPUT" --mode preview
OUTPUT="$(cd "$OUTPUT" && pwd)"
STAGE="$(mktemp -d "$ROOT/.build/.update-feed.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
NAME="g-calendar-$VERSION-arm64-preview"
cp "$OUTPUT/$NAME.zip" "$STAGE/$NAME.zip"
cp "$NOTES" "$STAGE/$NAME.md"
"$SPARKLE_ROOT/bin/generate_appcast" --account g-calendar --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/AlekseyBeketov/g-calendar/releases/download/v$VERSION/" \
  --link https://github.com/AlekseyBeketov/g-calendar "$STAGE"
"$SPARKLE_ROOT/bin/sign_update" --account g-calendar --verify "$STAGE/appcast.xml"
SIGNATURE="$(/usr/bin/xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$STAGE/appcast.xml")"
[[ -n "$SIGNATURE" ]] || fail 'No archive signature in the appcast'
"$SPARKLE_ROOT/bin/sign_update" --account g-calendar --verify "$OUTPUT/$NAME.zip" "$SIGNATURE"
cp "$STAGE/appcast.xml" "$OUTPUT/appcast.xml"
(cd "$OUTPUT" && /usr/bin/shasum -a 256 "$NAME.zip" "$NAME.dmg" release-manifest.json appcast.xml > SHA256SUMS)
"$ROOT/scripts/verify-release.sh" --app "$APP" --mode preview --artifacts "$OUTPUT"
printf 'PREPARED_UPDATE=%s\nTAG=v%s\n' "$OUTPUT" "$VERSION"
echo 'Upload ZIP, DMG, appcast.xml, release-manifest.json and SHA256SUMS together to a draft GitHub Release, review it, then publish explicitly.'
echo 'No tag or release has been created. Keep the signing key in Keychain and back it up privately before distributing this first version.'
