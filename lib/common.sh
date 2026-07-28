#!/usr/bin/env bash
# Shared helpers for the read-only status command.

EXIT_OK=0
EXIT_POLICY=1
EXIT_USAGE=2
EXIT_UNKNOWN=3
EXIT_PRIVILEGES=4
EXIT_HARDWARE=5
EXIT_BUSY=6

ACTION_LOG_DIRECTORY=''
ACTION_LOG_FILE=''

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
    error "This action requires root. Use the installed privileged helper for: ${action}"
    return "${EXIT_PRIVILEGES}"
  fi
}

prepare_action_log_directory() {
  if (( EUID == 0 )); then
    ACTION_LOG_DIRECTORY='/var/log/fedora-radio-control'
    install -d -o root -g root -m 0700 "${ACTION_LOG_DIRECTORY}" || {
      error "Unable to create secure log directory: ${ACTION_LOG_DIRECTORY}"
      return "${EXIT_UNKNOWN}"
    }
  else
    # Mocked tests never run mutations as root. Keep their artifacts isolated
    # from the production log directory.
    ACTION_LOG_DIRECTORY="${APPLICATION_ROOT}/logs"
    mkdir -p "${ACTION_LOG_DIRECTORY}" || return "${EXIT_UNKNOWN}"
  fi
}

begin_action_log() {
  local action="$1" timestamp
  prepare_action_log_directory || return $?
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  umask 077
  ACTION_LOG_FILE="$(mktemp "${ACTION_LOG_DIRECTORY}/${timestamp}_${action}.XXXXXX.log")" || {
    error "Unable to create action log in ${ACTION_LOG_DIRECTORY}"
    return "${EXIT_UNKNOWN}"
  }
  ln -sfn "$(basename "${ACTION_LOG_FILE}")" "${ACTION_LOG_DIRECTORY}/latest.log"
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
