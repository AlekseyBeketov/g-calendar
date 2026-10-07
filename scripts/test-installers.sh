#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/install-common.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/g-calendar-install-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
TEST_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT + 1)); printf 'PASS %s\n' "$1"; }
reject() { if "$@" >/dev/null 2>&1; then gc_fail "Expected rejection: $*"; exit 1; fi; }
gc_host_supported
# Tiny fixture executable: no UI, Google, OAuth, app data or full app compilation.
printf '%s\n' '#include <unistd.h>' 'int main(int argc, char **argv) { if (argc > 1) sleep(2); return 0; }' > "$TEST_ROOT/fixture.c"
/usr/bin/clang -target arm64-apple-macos13.0 "$TEST_ROOT/fixture.c" -o "$TEST_ROOT/fixture"
make_app() {
  local path="$1" version="$2" identifier="${3:-$GC_BUNDLE_ID}"
  mkdir -p "$path/Contents/MacOS"
  cp "$ROOT/resources/Info.plist" "$path/Contents/Info.plist"
  cp "$TEST_ROOT/fixture" "$path/Contents/MacOS/g-calendar"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$path/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $identifier" "$path/Contents/Info.plist"
  /usr/bin/codesign --force --sign - --identifier "$identifier" "$path" >/dev/null 2>&1
}
make_app "$TEST_ROOT/v1/g-calendar.app" 0.1.0
make_app "$TEST_ROOT/v2/g-calendar.app" 0.2.0
make_app "$TEST_ROOT/foreign/g-calendar.app" 0.1.0 org.example.foreign
APP1="$TEST_ROOT/v1/g-calendar.app"; APP2="$TEST_ROOT/v2/g-calendar.app"
DEST="$TEST_ROOT/Applications with spaces"
# Only the running-process probe is replaced in fixture transactions: the actual
# user's g-calendar can remain open while all bundles/destinations are isolated.
transaction() (
  gc_assert_not_running() { return 0; }
  gc_prepare_destination "$DEST"
  case "$1" in install) gc_install_bundle "$2";; rollback) gc_rollback_bundle;; uninstall) gc_uninstall_bundle;; esac
)
transaction install "$APP1" >/dev/null
[[ "$(gc_plist "$DEST/g-calendar.app" CFBundleShortVersionString)" == 0.1.0 ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'install + destination with spaces'
transaction install "$APP1" >/dev/null
[[ -d "$DEST/.g-calendar-previous.app" ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'repeat installation retains previous bundle'
transaction install "$APP2" >/dev/null
[[ "$(gc_plist "$DEST/g-calendar.app" CFBundleShortVersionString)" == 0.2.0 ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
transaction rollback >/dev/null
[[ "$(gc_plist "$DEST/g-calendar.app" CFBundleShortVersionString)" == 0.1.0 ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
[[ "$(gc_plist "$DEST/.g-calendar-previous.app" CFBundleShortVersionString)" == 0.2.0 ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'upgrade and explicit reversible rollback'
mkdir "$TEST_ROOT/synthetic-data"
for name in cache journal reminders settings oauth; do printf 'private-fixture:%s\n' "$name" > "$TEST_ROOT/synthetic-data/$name"; done
BEFORE="$(/usr/bin/shasum -a 256 "$TEST_ROOT"/synthetic-data/*)"
transaction install "$APP2" >/dev/null
[[ "$BEFORE" == "$(/usr/bin/shasum -a 256 "$TEST_ROOT"/synthetic-data/*)" ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'synthetic data remains byte-identical'
reject transaction install "$TEST_ROOT/foreign/g-calendar.app"
[[ "$(gc_plist "$DEST/g-calendar.app" CFBundleShortVersionString)" == 0.2.0 ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'foreign candidate rejected before replacement'
FOREIGN_DEST="$TEST_ROOT/Foreign Applications"
mkdir "$FOREIGN_DEST"; /usr/bin/ditto "$TEST_ROOT/foreign/g-calendar.app" "$FOREIGN_DEST/g-calendar.app"
reject bash -c 'source "$1"; gc_assert_not_running(){ return 0; }; gc_prepare_destination "$2" && gc_install_bundle "$3"' _ "$ROOT/scripts/install-common.sh" "$FOREIGN_DEST" "$APP1"
[[ "$(gc_plist "$FOREIGN_DEST/g-calendar.app" CFBundleIdentifier)" == org.example.foreign ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'foreign destination preserved'
reject gc_check_platform Darwin x86_64 13.0
reject gc_check_platform Darwin arm64 12.7
reject gc_check_platform Linux arm64 27.0
gc_check_platform Darwin arm64 13.0
pass 'Intel / old macOS / non-macOS rejected'
reject gc_verify_release_signature "$APP1" ABCDE12345
reject gc_verify_release_signature "$APP1" wrong
pass 'ad-hoc signature / invalid publisher rejected for release'
cp -R "$APP1" "$TEST_ROOT/tampered.app"
printf 'tampered' >> "$TEST_ROOT/tampered.app/Contents/MacOS/g-calendar"
reject gc_verify_bundle "$TEST_ROOT/tampered.app"
pass 'broken signature rejected'
gc_ditto "$APP1" "$TEST_ROOT/wrong-signed-id.app"
/usr/bin/codesign --force --sign - --identifier "$GC_BUNDLE_ID.suffix" "$TEST_ROOT/wrong-signed-id.app" >/dev/null 2>&1
reject gc_verify_bundle "$TEST_ROOT/wrong-signed-id.app"
pass 'signature identifier is exact rather than a matching prefix'
for platform in macos ios; do
  TARGET="$TEST_ROOT/$platform-target/g-calendar.app"
  /usr/bin/ditto "$APP1" "$TARGET"
  /usr/bin/vtool -set-build-version "$platform" 14.0 27.0 -replace -output "$TEST_ROOT/modified-executable" "$TARGET/Contents/MacOS/g-calendar"
  mv "$TEST_ROOT/modified-executable" "$TARGET/Contents/MacOS/g-calendar"
  chmod +x "$TARGET/Contents/MacOS/g-calendar"
  /usr/bin/codesign --force --sign - --identifier "$GC_BUNDLE_ID" "$TARGET" >/dev/null 2>&1
  reject gc_verify_bundle "$TARGET"
done
pass 'actual Mach-O platform and deployment target checked independently of plist'
/usr/bin/ruby -e 'File.binwrite(ARGV[0],[0xfeedfacf,0x100000c,0,2,1,16,0,0,0x24,16,13<<16,13<<16].pack("V*"))' "$TEST_ROOT/legacy-macho"
gc_verify_macho "$TEST_ROOT/legacy-macho"
/usr/bin/ruby -e 'File.binwrite(ARGV[0],[0xfeedfacf,0x100000c,0,2,1,16,0,0,0x24,0,13<<16,13<<16].pack("V*"))' "$TEST_ROOT/malformed-macho"
reject gc_verify_macho "$TEST_ROOT/malformed-macho"
printf 'short' > "$TEST_ROOT/short-macho"; reject gc_verify_macho "$TEST_ROOT/short-macho"
pass 'native parser accepts legacy macOS target and rejects malformed/truncated commands'
LINK_DEST="$TEST_ROOT/Linked Applications"; ln -s "$DEST" "$LINK_DEST"
reject gc_prepare_destination "$LINK_DEST"
pass 'symlink destination rejected'
LOCK_DEST="$TEST_ROOT/Locked Applications"; mkdir "$LOCK_DEST"
touch "$LOCK_DEST/.g-calendar-install.lock"; chmod 600 "$LOCK_DEST/.g-calendar-install.lock"
/bin/bash -c 'source "$1"; gc_prepare_destination "$2" || exit; touch "$3"; sleep 2' _ "$ROOT/scripts/install-common.sh" "$LOCK_DEST" "$TEST_ROOT/lock-ready" &
LOCK_PID=$!
for ((i=0; i<100; i++)); do [[ ! -f "$TEST_ROOT/lock-ready" ]] || break; sleep 0.02; done
[[ -f "$TEST_ROOT/lock-ready" ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
reject bash -c 'source "$1"; gc_prepare_destination "$2"' _ "$ROOT/scripts/install-common.sh" "$LOCK_DEST"
wait "$LOCK_PID"
[[ -f "$LOCK_DEST/.g-calendar-install.lock" && "$(/usr/bin/stat -f %Lp "$LOCK_DEST/.g-calendar-install.lock")" == 600 ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'concurrent stable private lock rejects second process'
LEGACY_LOCK_DEST="$TEST_ROOT/Legacy Locked Applications"
mkdir "$LEGACY_LOCK_DEST"
/bin/bash -c 'source "$1"; gc_lock_fd_modern(){ return 64; }; gc_prepare_destination "$2" || exit; touch "$3"; sleep 2' _ "$ROOT/scripts/install-common.sh" "$LEGACY_LOCK_DEST" "$TEST_ROOT/legacy-lock-ready" &
LEGACY_LOCK_PID=$!
for ((i=0; i<100; i++)); do [[ ! -f "$TEST_ROOT/legacy-lock-ready" ]] || break; sleep 0.02; done
[[ -f "$TEST_ROOT/legacy-lock-ready" ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
reject bash -c 'source "$1"; gc_lock_fd_modern(){ return 64; }; gc_prepare_destination "$2"' _ "$ROOT/scripts/install-common.sh" "$LEGACY_LOCK_DEST"
wait "$LEGACY_LOCK_PID"
pass 'macOS13-compatible inherited flock fallback retains interprocess lease'
reject bash -c 'set -e; source "$1"; gc_assert_not_running(){ gc_fail "running fixture"; }; gc_prepare_destination "$2"; gc_install_bundle "$3"' _ "$ROOT/scripts/install-common.sh" "$DEST" "$APP1"
pass 'running-app seam rejects without closing app'
"$APP1/Contents/MacOS/g-calendar" --installer-fixture-wait &
FIXTURE_PID=$!
RUNNING_FIXTURE_COMMAND="$(/bin/ps -p "$FIXTURE_PID" -o comm=)" || { gc_fail 'Process observation unavailable; actual running-app scenario did not pass.'; exit 1; }
[[ "$RUNNING_FIXTURE_COMMAND" == "$APP1/Contents/MacOS/g-calendar" ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
if RUNNING_FIXTURE_ERROR="$(gc_assert_not_running 2>&1)"; then gc_fail 'Running fixture was not detected.'; exit 1; fi
[[ "$RUNNING_FIXTURE_ERROR" == *'Закройте g-calendar и повторите установку.'* ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
wait "$FIXTURE_PID"
pass 'actual running fixture detected without process-probe override'
reject bash -c 'set -e; source "$1"; gc_assert_not_running(){ return 0; }; gc_copy_bundle(){ mkdir -p "$2"; return 1; }; gc_prepare_destination "$3"; gc_install_bundle "$4"' _ "$ROOT/scripts/install-common.sh" _ "$DEST" "$APP1"
[[ "$(gc_plist "$DEST/g-calendar.app" CFBundleShortVersionString)" == 0.2.0 ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
[[ -z "$(find "$DEST" -maxdepth 1 -name '.g-calendar-stage.*' -print)" ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'interrupted copy retains installed app and cleans staging'
reject bash -c 'set -e; source "$1"; gc_assert_not_running(){ return 0; }; mv(){ case "$1" in */.g-calendar-stage.*/g-calendar.app) return 1;; esac; command mv "$@"; }; gc_prepare_destination "$2"; gc_install_bundle "$3"' _ "$ROOT/scripts/install-common.sh" "$DEST" "$APP1"
[[ "$(gc_plist "$DEST/g-calendar.app" CFBundleShortVersionString)" == 0.2.0 ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'failed final rename automatically restores previous app'
# Repopulate the backup after the automatic restoration consumed it.
transaction install "$APP2" >/dev/null
transaction install "$APP1" >/dev/null
# Model a kill between the two renames. The next run refuses, rollback repairs.
mv "$DEST/g-calendar.app" "$TEST_ROOT/current-away.app"
reject transaction install "$APP1"
transaction rollback >/dev/null
[[ "$(gc_plist "$DEST/g-calendar.app" CFBundleShortVersionString)" == 0.2.0 ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'interrupted rename requires and supports rollback'
chmod 500 "$TEST_ROOT/Locked Applications"
reject bash -c 'source "$1"; gc_prepare_destination "$2"' _ "$ROOT/scripts/install-common.sh" "$TEST_ROOT/Locked Applications"
chmod 700 "$TEST_ROOT/Locked Applications"
pass 'unwritable destination rejected'
(cd "$TEST_ROOT/v1"; /usr/bin/zip -qr "$TEST_ROOT/valid.zip" g-calendar.app)
gc_validate_archive "$TEST_ROOT/valid.zip"
mkdir "$TEST_ROOT/unpacked"; gc_extract_archive "$TEST_ROOT/valid.zip" "$TEST_ROOT/unpacked"
gc_verify_bundle "$TEST_ROOT/unpacked/g-calendar.app"
pass 'valid ZIP preflight and extraction'
METADATA_APP="$TEST_ROOT/metadata/g-calendar.app"
gc_ditto "$APP1" "$METADATA_APP"
mkdir -p "$METADATA_APP/Contents/Resources"
printf 'resource bytes\n' > "$METADATA_APP/Contents/Resources/metadata-fixture.txt"
/usr/bin/codesign --force --sign - --identifier "$GC_BUNDLE_ID" "$METADATA_APP" >/dev/null 2>&1
/usr/bin/xattr -w com.example.gcalendar.installer-fixture 'metadata bytes' "$METADATA_APP/Contents/Resources/metadata-fixture.txt"
gc_verify_bundle "$METADATA_APP"
gc_ditto -c -k --keepParent "$METADATA_APP" "$TEST_ROOT/metadata.zip"
gc_validate_archive "$TEST_ROOT/metadata.zip"
[[ "$(gc_zipinfo -1 "$TEST_ROOT/metadata.zip")" == *'g-calendar.app/Contents/Resources/._metadata-fixture.txt'* ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
mkdir "$TEST_ROOT/metadata-unpacked"
gc_extract_archive "$TEST_ROOT/metadata.zip" "$TEST_ROOT/metadata-unpacked"
RESTORED="$TEST_ROOT/metadata-unpacked/g-calendar.app/Contents/Resources/metadata-fixture.txt"
[[ "$(/usr/bin/xattr -p com.example.gcalendar.installer-fixture "$RESTORED")" == 'metadata bytes' ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
cmp "$METADATA_APP/Contents/Resources/metadata-fixture.txt" "$RESTORED"
[[ -z "$(find "$TEST_ROOT/metadata-unpacked" -name '._*' -print -quit)" ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
reject gc_extract_archive "$TEST_ROOT/metadata.zip" "$TEST_ROOT/metadata-unpacked"
pass 'actual ditto ZIP restores xattrs/bytes, consumes AppleDouble and rejects nonempty destination'
printf 'not zip' > "$TEST_ROOT/broken.zip"; reject gc_validate_archive "$TEST_ROOT/broken.zip"
mkdir -p "$TEST_ROOT/unsafe/g-calendar.app"; ln -s /tmp "$TEST_ROOT/unsafe/g-calendar.app/escape"
(cd "$TEST_ROOT/unsafe"; /usr/bin/zip -yqr "$TEST_ROOT/symlink.zip" g-calendar.app)
reject gc_validate_archive "$TEST_ROOT/symlink.zip"
(cd "$TEST_ROOT"; /usr/bin/zip -q "$TEST_ROOT/wrong-root.zip" fixture.c)
reject gc_validate_archive "$TEST_ROOT/wrong-root.zip"
# Write a minimal malicious ZIP using Ruby's standard zlib, without Python dependency.
/usr/bin/ruby -rzlib -e 'n="../escape"; d="bad"; crc=Zlib.crc32(d); File.binwrite(ARGV[0],[0x04034b50,20,0,0,0,0,crc,d.bytesize,d.bytesize,n.bytesize,0].pack("VvvvvvVVVvv")+n+d+[0x02014b50,20,20,0,0,0,0,crc,d.bytesize,d.bytesize,n.bytesize,0,0,0,0,0,0].pack("VvvvvvvVVVvvvvvVV")+n+[0x06054b50,0,0,1,1,46+n.bytesize,30+n.bytesize+d.bytesize,0].pack("VvvvvVVv"))' "$TEST_ROOT/traversal.zip"
reject gc_validate_archive "$TEST_ROOT/traversal.zip"
[[ ! -e "$TEST_ROOT/escape" ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'malformed / symlink / wrong-root / path traversal ZIP rejected'
DIGEST="$(/usr/bin/shasum -a 256 "$TEST_ROOT/valid.zip")"; DIGEST="${DIGEST%% *}"
gc_verify_digest "$TEST_ROOT/valid.zip" "$DIGEST"
reject gc_verify_digest "$TEST_ROOT/valid.zip" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
pass 'trusted checksum enforced'
transaction uninstall >/dev/null
[[ ! -e "$DEST/g-calendar.app" ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
[[ "$BEFORE" == "$(/usr/bin/shasum -a 256 "$TEST_ROOT"/synthetic-data/*)" ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
transaction uninstall >/dev/null
reject bash -c 'source "$1"; gc_assert_not_running(){ return 0; }; gc_prepare_destination "$2" && gc_uninstall_bundle' _ "$ROOT/scripts/install-common.sh" "$FOREIGN_DEST"
[[ -d "$FOREIGN_DEST/g-calendar.app" ]] || { gc_fail 'Fixture assertion failed'; exit 1; }
pass 'uninstall is idempotent; foreign bundle and user data preserved'
printf 'INSTALLER_SCENARIOS=%s\n' "$TEST_COUNT"
