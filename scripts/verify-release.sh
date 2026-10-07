#!/bin/bash
set -euo pipefail

APP=""; MODE="local"; SIGNATURE_ONLY=0; ARTIFACTS=""
fail() { printf 'Verification failed: %s\n' "$1" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:?Missing app}"; shift 2 ;;
    --mode) MODE="${2:?Missing mode}"; shift 2 ;;
    --signature-only) SIGNATURE_ONLY=1; shift ;;
    --artifacts) ARTIFACTS="${2:?Missing artifacts directory}"; shift 2 ;;
    --help) printf '%s\n' 'Usage: verify-release.sh --app PATH [--mode local|signed] [--signature-only] [--artifacts DIR]'; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done
[[ "$MODE" == local || "$MODE" == signed ]] || fail 'Mode must be local or signed'
[[ -d "$APP" && ! -L "$APP" ]] || fail 'Expected an app directory, not a symlink'
PLIST="$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$PLIST" >/dev/null || fail 'Invalid Info.plist'
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
[[ "$(read_key CFBundleIdentifier)" == com.alexbeketov.gcalendar ]] || fail 'Unexpected bundle identity'
[[ "$(read_key CFBundleExecutable)" == g-calendar ]] || fail 'Unexpected executable'
[[ "$(read_key LSMinimumSystemVersion)" == 13.0 ]] || fail 'This release pipeline supports macOS 13.0 minimum only'
[[ "$(/usr/bin/lipo -archs "$APP/Contents/MacOS/g-calendar")" == arm64 ]] || fail 'Expected arm64-only executable'
/usr/bin/codesign --verify --strict "$APP" || fail 'Invalid bundle signature'
TEMP="$(mktemp -d "${TMPDIR:-/private/tmp}/g-calendar-release-check.XXXXXX")"
chmod 700 "$TEMP"
trap 'rm -rf "$TEMP"' EXIT
/usr/bin/codesign -d --verbose=4 "$APP" >"$TEMP/signature" 2>&1
/usr/bin/vtool -show-build "$APP/Contents/MacOS/g-calendar" > "$TEMP/platform"
/usr/bin/grep -Eq '^[[:space:]]*platform MACOS$' "$TEMP/platform" || fail 'Executable is not a macOS target'
/usr/bin/grep -Eq '^[[:space:]]*minos 13\.0$' "$TEMP/platform" || fail 'Executable deployment target differs from the manifest'
if [[ "$MODE" == local ]]; then
  /usr/bin/grep -qx 'Signature=adhoc' "$TEMP/signature" || fail 'Local preview requires an ad-hoc signature; use the signed workflow for Developer ID'
fi
if [[ "$MODE" == signed ]]; then
  TEAM="${G_CALENDAR_TEAM_ID:?Set G_CALENDAR_TEAM_ID to the expected Developer ID Team ID}"
  [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail 'Invalid expected Team ID'
  /usr/bin/grep -q '^Authority=Developer ID Application:' "$TEMP/signature" || fail 'Expected Developer ID Application authority'
  /usr/bin/grep -qx "TeamIdentifier=$TEAM" "$TEMP/signature" || fail 'Publisher Team ID mismatch'
  /usr/bin/grep -q 'flags=.*runtime' "$TEMP/signature" || fail 'Hardened runtime missing'
  /usr/bin/grep -q '^Timestamp=' "$TEMP/signature" || fail 'Secure signing timestamp missing'
  /usr/bin/codesign --verify --strict -R "=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$TEAM\"" "$APP" || fail 'Developer ID requirement failed'
  if [[ "$SIGNATURE_ONLY" == 0 ]]; then
    /usr/bin/xcrun stapler validate "$APP" || fail 'App notarization ticket missing'
    /usr/sbin/spctl --assess --type execute "$APP" || fail 'App Gatekeeper assessment failed'
  fi
fi
if [[ -n "$ARTIFACTS" ]]; then
  [[ -f "$ARTIFACTS/SHA256SUMS" && -f "$ARTIFACTS/release-manifest.json" ]] || fail 'Missing final manifest or checksums'
  # Generated checksum filenames are single path components; never trust arbitrary paths.
  while IFS= read -r line; do
    [[ "$line" =~ ^[0-9a-f]{64}\ \ [A-Za-z0-9._-]+$ ]] || fail 'Unsafe checksum entry'
  done < "$ARTIFACTS/SHA256SUMS"
  (cd "$ARTIFACTS" && /usr/bin/shasum -a 256 -c SHA256SUMS) || fail 'Artifact checksum mismatch'
  # plutil -lint only accepts plist serialization; -extract parses JSON (including null).
  /usr/bin/plutil -extract version raw -o - "$ARTIFACTS/release-manifest.json" >/dev/null || fail 'Invalid JSON manifest'
  VERSION="$(read_key CFBundleShortVersionString)"
  manifest_key() { /usr/bin/plutil -extract "$1" raw -o - "$ARTIFACTS/release-manifest.json"; }
  [[ "$(manifest_key version)" == "$VERSION" && "$(manifest_key build)" == "$(read_key CFBundleVersion)" ]] || fail 'Manifest version mismatch'
  [[ "$(manifest_key architecture)" == arm64 && "$(manifest_key minimumMacOS)" == 13.0 ]] || fail 'Manifest platform mismatch'
  [[ "$(manifest_key bundleIdentifier)" == com.alexbeketov.gcalendar ]] || fail 'Manifest bundle identity mismatch'
  if [[ "$MODE" == local ]]; then
    [[ "$(manifest_key signing)" == ad-hoc && "$(manifest_key distribution)" == local && "$(manifest_key notarized)" == false ]] || fail 'Local manifest misrepresents signing'
  else
    [[ "$(manifest_key signing)" == developer-id && "$(manifest_key distribution)" == release && "$(manifest_key teamID)" == "$TEAM" ]] || fail 'Manifest publisher mismatch'
    if [[ "$SIGNATURE_ONLY" == 0 ]]; then [[ "$(manifest_key notarized)" == true ]] || fail 'Manifest is not finalized'; fi
  fi
  PREFIX="g-calendar-$VERSION-arm64"
  if [[ "$MODE" == local ]]; then PREFIX="$PREFIX-local"; fi
  [[ "$(manifest_key assets.0)" == "$PREFIX.zip" && "$(manifest_key assets.1)" == "$PREFIX.dmg" ]] || fail 'Manifest asset names mismatch'
  if manifest_key assets.2 >/dev/null 2>&1; then fail 'Unexpected manifest asset'; fi
  DMG="$ARTIFACTS/$PREFIX.dmg"
  [[ -f "$DMG" && -f "$ARTIFACTS/$PREFIX.zip" ]] || fail 'Expected versioned assets missing'
  /usr/bin/hdiutil verify "$DMG" || fail 'Disk image integrity failed'
  if [[ "$MODE" == signed && "$SIGNATURE_ONLY" == 0 ]]; then
    /usr/bin/codesign --verify --strict -R "=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$TEAM\"" "$DMG" || fail 'DMG publisher identity mismatch'
    /usr/bin/xcrun stapler validate "$DMG" || fail 'DMG notarization ticket missing'
    /usr/sbin/spctl --assess --type open --context context:primary-signature "$DMG" || fail 'DMG Gatekeeper assessment failed'
  fi
fi
printf 'VERIFIED_APP=%s\nVERIFICATION_MODE=%s\n' "$APP" "$MODE"
if [[ "$MODE" == signed && "$SIGNATURE_ONLY" == 0 ]]; then
  printf '%s\n' 'NOTARIZATION_CHECKED=true'
else
  printf '%s\n' 'NOTARIZATION_CHECKED=false'
fi
if [[ "$MODE" == local ]]; then printf '%s\n' 'LOCAL_ONLY: signature integrity checked; Developer ID, notarization and Gatekeeper acceptance are not claimed.'; fi
