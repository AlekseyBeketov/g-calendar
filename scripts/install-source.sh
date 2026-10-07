#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/install-common.sh"
DESTINATION="$HOME/Applications"
ROLLBACK=0
APP=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination) [[ $# -ge 2 ]] || { gc_fail 'Нет destination.'; exit 2; }; DESTINATION="$2"; shift 2;;
    --app) [[ $# -ge 2 ]] || { gc_fail 'Нет app path.'; exit 2; }; APP="$2"; shift 2;;
    --rollback) ROLLBACK=1; shift;;
    --help) printf '%s\n' 'install-source.sh [--destination /absolute/Applications] [--app /absolute/g-calendar.app] [--rollback]'; exit 0;;
    *) gc_fail "Неизвестный аргумент: $1"; exit 2;;
  esac
done
gc_host_supported
gc_prepare_destination "$DESTINATION"
if [[ "$ROLLBACK" == 1 ]]; then gc_rollback_bundle; exit; fi
gc_assert_not_running
if [[ -z "$APP" ]]; then
  "$ROOT/scripts/build-app.sh"
  APP="$ROOT/dist/g-calendar.app"
fi
[[ "$APP" == /* ]] || { gc_fail 'App path должен быть абсолютным.'; exit 2; }
gc_install_bundle "$APP"
