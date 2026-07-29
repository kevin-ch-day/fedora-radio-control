#!/usr/bin/env bash
# Shared helpers for reviewed privileged radio actions.

EXIT_OK=0
EXIT_POLICY=1
EXIT_USAGE=2
EXIT_UNKNOWN=3
EXIT_BUSY=6

error() {
  printf 'Error: %s\n' "$*" >&2
}

COMMON_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=logging.sh
source "${COMMON_LIB_DIR}/logging.sh"

require_commands() {
  local command
  for command in "$@"; do
    if ! command -v "${command}" >/dev/null 2>&1; then
      error "Required command not found: ${command}"
      return "${EXIT_UNKNOWN}"
    fi
  done
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
