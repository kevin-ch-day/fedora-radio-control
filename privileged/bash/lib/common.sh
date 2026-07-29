#!/usr/bin/env bash
# Shared helpers for the read-only status command.

EXIT_OK=0
EXIT_POLICY=1
EXIT_USAGE=2
EXIT_UNKNOWN=3
EXIT_PRIVILEGES=4
EXIT_HARDWARE=5
EXIT_BUSY=6

error() {
  printf 'Error: %s\n' "$*" >&2
}

COMMON_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=logging.sh
source "${COMMON_LIB_DIR}/logging.sh"

format_elapsed_seconds() {
  local seconds="$1" days hours minutes
  [[ "${seconds}" =~ ^[0-9]+$ ]] || { printf 'unknown'; return; }
  days=$(( seconds / 86400 ))
  hours=$(( (seconds % 86400) / 3600 ))
  minutes=$(( (seconds % 3600) / 60 ))
  if (( days > 0 )); then
    printf '%sd %02dh %02dm' "${days}" "${hours}" "${minutes}"
  elif (( hours > 0 )); then
    printf '%sh %02dm' "${hours}" "${minutes}"
  else
    printf '%sm' "${minutes}"
  fi
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
    error "This action requires root. Use the installed privileged helper for: ${action}"
    return "${EXIT_PRIVILEGES}"
  fi
}

with_mutation_lock() {
  local runtime_directory lock_file lock_fd result
  if (( EUID == 0 )); then
    runtime_directory='/run/fedora-radio-control'
    install -d -o root -g root -m 0700 "${runtime_directory}" || {
      error "Unable to create runtime lock directory: ${runtime_directory}"
      return "${EXIT_UNKNOWN}"
    }
  else
    runtime_directory="${APPLICATION_ROOT}/.test-runtime"
    mkdir -p "${runtime_directory}" || return "${EXIT_UNKNOWN}"
  fi
  lock_file="${runtime_directory}/mutation.lock"
  if ! exec {lock_fd}>"${lock_file}"; then
    error "Unable to open mutation lock: ${lock_file}"
    return "${EXIT_UNKNOWN}"
  fi
  if ! flock -n "${lock_fd}"; then
    error 'Another radio-control action is already running.'
    exec {lock_fd}>&-
    return "${EXIT_BUSY}"
  fi
  if "$@"; then
    result=0
  else
    result=$?
  fi
  flock -u "${lock_fd}"
  exec {lock_fd}>&-
  return "${result}"
}
