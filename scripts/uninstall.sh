#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/install-common.sh"
DESTINATION="$HOME/Applications"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination) [[ $# -ge 2 ]] || exit 2; DESTINATION="$2"; shift 2;;
    --help) printf '%s\n' 'uninstall.sh [--destination /absolute/Applications] — только own .app; данные сохраняются.'; exit 0;;
    *) gc_fail "Неизвестный аргумент: $1"; exit 2;;
  esac
done
gc_host_supported
gc_prepare_destination "$DESTINATION"
gc_uninstall_bundle
