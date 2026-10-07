#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/g-calendar.app"; OUTPUT=""; MODE="local"
fail() { printf 'Packaging failed: %s\n' "$1" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:?Missing app}"; shift 2 ;;
    --output) OUTPUT="${2:?Missing output directory}"; shift 2 ;;
    --mode) MODE="${2:?Missing mode}"; shift 2 ;;
    --help) printf '%s\n' 'Usage: package-dmg.sh [--app PATH] [--output DIR] [--mode local|release]'; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done
[[ "$MODE" == local || "$MODE" == release ]] || fail 'Mode must be local or release'
[[ "$MODE" == local ]] && VERIFY_MODE=local || VERIFY_MODE=signed
"$ROOT/scripts/verify-release.sh" --app "$APP" --mode "$VERIFY_MODE"
[[ -z "$(/usr/bin/find "$APP" ! -type f ! -type d -print -quit)" ]] || fail 'This minimal app archive must not contain symlinks or special files'
PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[0-9]+$ ]] || fail 'Unsafe version or build'
PREFIX="g-calendar-$VERSION-arm64"
if [[ "$MODE" == local ]]; then PREFIX="$PREFIX-local"; fi
OUTPUT="${OUTPUT:-$ROOT/dist/packages/$VERSION-arm64-$MODE}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
LOCK="$OUTPUT/.g-calendar-package-lock"
mkdir "$LOCK" 2>/dev/null || fail 'Another packaging process holds the output lock'
chmod 700 "$LOCK"
STAGE=""; MOUNT=""
cleanup() {
  if [[ -n "$MOUNT" ]]; then /usr/bin/hdiutil detach "$MOUNT" >/dev/null || true; fi
  if [[ -n "$STAGE" ]]; then rm -rf "$STAGE"; fi
  rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT
for NAME in "$PREFIX.dmg" "$PREFIX.zip" SHA256SUMS release-manifest.json; do
  [[ ! -e "$OUTPUT/$NAME" && ! -L "$OUTPUT/$NAME" ]] || fail "Artifact already exists: $NAME; choose a fresh output directory"
done
STAGE="$(mktemp -d "$OUTPUT/.package.XXXXXX")"
chmod 700 "$STAGE"
mkdir -p "$STAGE/image/.installer"
/usr/bin/ditto "$APP" "$STAGE/image/g-calendar.app"
"$ROOT/scripts/verify-release.sh" --app "$STAGE/image/g-calendar.app" --mode "$VERIFY_MODE"
ln -s /Applications "$STAGE/image/Applications"
cp "$ROOT/resources/installer/finder-layout.bin" "$STAGE/image/.DS_Store"
cp "$ROOT/resources/installer/README.html" "$STAGE/image/Как установить.html"
cp "$ROOT/resources/installer/installation.css" "$STAGE/image/.installer/installation.css"
if [[ "$MODE" == release ]]; then
  /usr/bin/sed '/<p class="notice">/d' "$STAGE/image/Как установить.html" > "$STAGE/instructions"
  mv "$STAGE/instructions" "$STAGE/image/Как установить.html"
fi
/usr/bin/ditto -c -k --keepParent "$STAGE/image/g-calendar.app" "$STAGE/$PREFIX.zip"
mkdir "$STAGE/zip-check"
/usr/bin/ditto -x -k "$STAGE/$PREFIX.zip" "$STAGE/zip-check"
"$ROOT/scripts/verify-release.sh" --app "$STAGE/zip-check/g-calendar.app" --mode "$VERIFY_MODE"
/usr/bin/hdiutil create -volname "g-calendar $VERSION" -fs HFS+ -format UDZO -srcfolder "$STAGE/image" "$STAGE/$PREFIX.dmg"
/usr/bin/hdiutil verify "$STAGE/$PREFIX.dmg"
mkdir "$STAGE/mounted"
MOUNT="$STAGE/mounted"
/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$STAGE/$PREFIX.dmg" >/dev/null
[[ -L "$MOUNT/Applications" && "$(readlink "$MOUNT/Applications")" == /Applications ]] || fail 'Applications shortcut missing'
[[ -f "$MOUNT/Как установить.html" && -f "$MOUNT/.installer/installation.css" && -f "$MOUNT/.DS_Store" ]] || fail 'Installer resources missing'
"$ROOT/scripts/verify-release.sh" --app "$MOUNT/g-calendar.app" --mode "$VERIFY_MODE"
/usr/bin/hdiutil detach "$MOUNT" >/dev/null
MOUNT=""
if [[ "$MODE" == release ]]; then
  : "${G_CALENDAR_SIGN_IDENTITY:?Set explicit Developer ID identity}"
  /usr/bin/codesign --force --sign "$G_CALENDAR_SIGN_IDENTITY" --timestamp "$STAGE/$PREFIX.dmg"
fi
if [[ "$MODE" == local ]]; then
  SIGNING=ad-hoc; NOTARIZED=false; TEAM_JSON=null
else
  SIGNING=developer-id; NOTARIZED=false; TEAM_JSON="\"$G_CALENDAR_TEAM_ID\""
fi
cat > "$STAGE/release-manifest.json" <<EOF
{
  "version": "$VERSION", "build": "$BUILD", "architecture": "arm64",
  "minimumMacOS": "13.0", "bundleIdentifier": "com.alexbeketov.gcalendar",
  "signing": "$SIGNING", "teamID": $TEAM_JSON, "notarized": $NOTARIZED,
  "distribution": "$MODE", "assets": ["$PREFIX.zip", "$PREFIX.dmg"]
}
EOF
(cd "$STAGE" && /usr/bin/shasum -a 256 "$PREFIX.zip" "$PREFIX.dmg" release-manifest.json > SHA256SUMS)
for NAME in "$PREFIX.dmg" "$PREFIX.zip" release-manifest.json SHA256SUMS; do mv "$STAGE/$NAME" "$OUTPUT/$NAME"; done
printf 'PACKAGES=%s\n' "$OUTPUT"
if [[ "$MODE" == release ]]; then
  printf '%s\n' 'DMG_NOTARIZATION_PENDING: run notarize-release.sh; do not distribute these intermediate artifacts.'
else
  printf '%s\n' 'LOCAL_ONLY: ad-hoc preview; not a notarized public release.'
fi
