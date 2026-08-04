#!/usr/bin/env bash
# Supported public entry point. The Python frontend is the public application;
# the Bash runtime remains only inside the installed root-owned helper.
set -Eeuo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  printf 'Error: Do not run Fedora Radio Control as root. Start it as your normal user: ./run.sh\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
APPLICATION="${SCRIPT_DIR}/src/fedora_radio_control/__main__.py"

if [[ ! -r "${APPLICATION}" ]]; then
  printf 'Internal error: Python application is missing or is not readable.\n' >&2
  exit 3
fi

exec env "PYTHONPATH=${SCRIPT_DIR}/src${PYTHONPATH:+:${PYTHONPATH}}" python3 -m fedora_radio_control "$@"
