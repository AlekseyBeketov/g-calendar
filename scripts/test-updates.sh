#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="${1:?Pass a prepared-update directory}"
APP="$ROOT/dist/g-calendar.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SPARKLE_ROOT="$("$ROOT/scripts/fetch-sparkle.sh")"
source "$ROOT/scripts/install-common.sh"
source "$ROOT/scripts/swift-toolchain.sh"
BUILD_DIR="$ROOT/.build/g-calendar/update-tests"
mkdir -p "$BUILD_DIR"
configure_swift_compiler "$BUILD_DIR"
SIGNATURE="$(/usr/bin/xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$ARTIFACTS/appcast.xml")"
URL="$(/usr/bin/xmllint --xpath 'string(//*[local-name()="enclosure"]/@url)' "$ARTIFACTS/appcast.xml")"
[[ "$URL" == "https://github.com/AlekseyBeketov/g-calendar/releases/download/v$VERSION/g-calendar-$VERSION-arm64-preview.zip" ]]
"${G_CALENDAR_SWIFT[@]}" -parse-as-library -target arm64-apple-macosx13.0 \
  -F "$SPARKLE_ROOT" -framework Sparkle -Xlinker -rpath -Xlinker "$SPARKLE_ROOT" \
  "$ROOT/Tests/UpdateArchiveTests.swift" -o "$BUILD_DIR/update-archive-tests"
TEMP="$(mktemp -d "$BUILD_DIR/fixture.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
mkdir -m 700 "$TEMP/extracted"
gc_extract_archive "$ARTIFACTS/g-calendar-$VERSION-arm64-preview.zip" "$TEMP/extracted"
echo 'PASS extraction preserves the signed Sparkle framework'
FIXTURE="$TEMP/extracted/g-calendar.app"
FIXTURE_ID="com.alexbeketov.gcalendar.fixture.update.$(/usr/bin/uuidgen | tr 'A-Z' 'a-z')"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $FIXTURE_ID" "$FIXTURE/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier "$FIXTURE_ID" "$FIXTURE" >/dev/null 2>&1
"$BUILD_DIR/update-archive-tests" "$APP" "$ARTIFACTS/g-calendar-$VERSION-arm64-preview.zip" "$SIGNATURE" "$FIXTURE"
ln -snf /tmp "$TEMP/extracted/g-calendar.app/Contents/Frameworks/Sparkle.framework/Resources"
if gc_verify_bundle_tree "$TEMP/extracted/g-calendar.app" >/dev/null 2>&1; then echo 'FAIL unsafe framework link accepted'; exit 1; fi
python3 - "$TEMP/alias-child.zip" <<'PY'
import stat, sys, zipfile
prefix = 'g-calendar.app/Contents/Frameworks/Sparkle.framework/'
with zipfile.ZipFile(sys.argv[1], 'w') as archive:
    link = zipfile.ZipInfo(prefix + 'Resources')
    link.create_system = 3
    link.external_attr = (stat.S_IFLNK | 0o777) << 16
    archive.writestr(link, 'Versions/Current/Resources')
    archive.writestr(prefix + 'Resources/unsafe.txt', 'must never be extracted')
PY
if gc_validate_archive "$TEMP/alias-child.zip" >/dev/null 2>&1; then echo 'FAIL archive entry beneath framework alias accepted'; exit 1; fi
echo 'PASS unsafe framework links and writes beneath aliases rejected before extraction'
