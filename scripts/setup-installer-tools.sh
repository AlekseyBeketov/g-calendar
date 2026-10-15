#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="$ROOT/.build/installer-layout-venv"
mkdir -p "$ROOT/.build"
/usr/bin/python3 -m venv "$ENVIRONMENT"
"$ENVIRONMENT/bin/python" -m pip --cache-dir "$ROOT/.build/pip-cache" install --disable-pip-version-check \
  --require-hashes --only-binary=:all: -r "$ROOT/resources/installer/requirements.txt"
printf 'INSTALLER_PYTHON=%s\n' "$ENVIRONMENT/bin/python"
