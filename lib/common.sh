#!/usr/bin/env bash
# Shared helpers for the read-only status command.

EXIT_OK=0
EXIT_POLICY=1
EXIT_USAGE=2
EXIT_UNKNOWN=3
EXIT_PRIVILEGES=4
EXIT_HARDWARE=5

error() {
  printf 'Error: %s\n' "$*" >&2
}

require_fedora() {
  if [[ ! -r /etc/os-release ]]; then
    error 'Cannot read /etc/os-release to verify the platform.'
    return "${EXIT_USAGE}"
  fi

  local os_id
  os_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
  if [[ "${os_id}" != 'fedora' ]]; then
    error 'This utility supports Fedora Linux only.'
    return "${EXIT_USAGE}"
  fi
}

require_commands() {
  local command
  for command in "$@"; do
    if ! command -v "${command}" >/dev/null 2>&1; then
      error "Required command not found: ${command}"
      return "${EXIT_UNKNOWN}"
    fi
  done
}

require_root() {
  local action="${1:-lockdown}"
  if (( EUID != 0 )); then
    error "This action requires root. Run: sudo ./run.sh ${action}"
    return "${EXIT_PRIVILEGES}"
  fi
}

grant_invoking_user_log_access() {
  local log_file="$1" owner
  (( EUID == 0 )) || return 0
  [[ "${SUDO_UID:-}" =~ ^[0-9]+$ ]] || return 0

  owner="${SUDO_UID}"
  if [[ "${SUDO_GID:-}" =~ ^[0-9]+$ ]]; then
    owner+=":${SUDO_GID}"
  fi
  chown "${owner}" "${log_file}" || {
    error "Could not grant the invoking user access to log: ${log_file}"
    return 1
  }
}
