#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/install-common.sh"
DESTINATION="$HOME/Applications"
VERSION=''; SHA256=''; TEAM_ID=''; ROLLBACK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination|--version|--sha256|--team-id)
      [[ $# -ge 2 ]] || { gc_fail "Нет значения $1."; exit 2; }
      case "$1" in --destination) DESTINATION="$2";; --version) VERSION="$2";; --sha256) SHA256="$2";; --team-id) TEAM_ID="$2";; esac
      shift 2;;
    --rollback) ROLLBACK=1; shift;;
    --help) printf '%s\n' 'install-release.sh --version vX.Y.Z --sha256 <trusted asset digest> --team-id <expected publisher> [--destination /absolute/Applications] [--rollback]'; exit 0;;
    *) gc_fail "Неизвестный аргумент: $1"; exit 2;;
  esac
done
gc_host_supported
if [[ "$ROLLBACK" == 1 ]]; then gc_prepare_destination "$DESTINATION"; gc_rollback_bundle; exit; fi
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { gc_fail 'Укажите конкретный tag vX.Y.Z; latest не используется.'; exit 2; }
[[ "$SHA256" =~ ^[a-fA-F0-9]{64}$ && "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { gc_fail 'Нужны доверенные SHA256 и Developer ID Team ID.'; exit 2; }
gc_assert_not_running
DOWNLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/g-calendar-download.XXXXXX")"
cleanup_download() { local status=$?; gc_install_cleanup; rm -rf "$DOWNLOAD_DIR"; return "$status"; }
trap cleanup_download EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
ASSET="g-calendar-${VERSION#v}-arm64.zip"
URL="https://github.com/AlekseyBeketov/g-calendar/releases/download/$VERSION/$ASSET"
/usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 180 --retry 2 --retry-delay 2 --max-filesize 268435456 --output "$DOWNLOAD_DIR/app.zip" "$URL"
gc_verify_digest "$DOWNLOAD_DIR/app.zip" "$SHA256"
mkdir "$DOWNLOAD_DIR/extracted"
gc_extract_archive "$DOWNLOAD_DIR/app.zip" "$DOWNLOAD_DIR/extracted"
APP="$DOWNLOAD_DIR/extracted/g-calendar.app"
[[ "$(gc_plist "$APP" CFBundleShortVersionString)" == "${VERSION#v}" ]] || { gc_fail 'Версия bundle не совпала с tag.'; exit 1; }
gc_verify_release_signature "$APP" "$TEAM_ID"
gc_prepare_destination "$DESTINATION"
# gc_prepare_destination installs the shared trap; retain download cleanup too.
trap cleanup_download EXIT
gc_install_bundle "$APP" "$TEAM_ID"
