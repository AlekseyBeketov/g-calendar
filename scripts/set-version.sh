#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT/resources/Info.plist"
VERSION=""
BUILD=""

fail() { printf 'Version update failed: %s\n' "$1" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:?Missing version}"; shift 2 ;;
    --build) BUILD="${2:?Missing build}"; shift 2 ;;
    --help) printf '%s\n' 'Usage: set-version.sh --version X.Y.Z [--build N]'; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'Use a three-part numeric version such as 0.2.0'
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
if [[ -z "$BUILD" ]]; then
  [[ "$CURRENT_BUILD" =~ ^[0-9]{1,9}$ ]] || fail 'Current build number is not a bounded integer'
  BUILD="$((10#$CURRENT_BUILD + 1))"
fi
[[ "$BUILD" =~ ^(0|[1-9][0-9]{0,8})$ ]] || fail 'Build must be an integer from 0 to 999999999'
[[ "$CURRENT_BUILD" =~ ^[0-9]{1,9}$ && "$BUILD" -gt "$CURRENT_BUILD" ]] || fail 'Build number must increase for every distributed update'

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
/usr/bin/plutil -lint "$PLIST" >/dev/null
printf 'VERSION=%s\nBUILD=%s\n' "$VERSION" "$BUILD"
