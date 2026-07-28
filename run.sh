#!/usr/bin/env bash
# Supported public entry point. It loads the internal application modules so
# menu and direct-command behavior cannot diverge.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
APPLICATION="${SCRIPT_DIR}/lib/application.sh"

if [[ ! -r "${APPLICATION}" ]]; then
  printf 'Internal error: application library is missing or is not readable.\n' >&2
  exit 3
fi

source "${APPLICATION}"
app_main "$@"
