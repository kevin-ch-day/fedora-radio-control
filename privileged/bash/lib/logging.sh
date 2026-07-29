#!/usr/bin/env bash
# Secure mutation-log lifecycle and safe structured-log helpers. This module
# never records connection names, addresses, VPN endpoints, or command output.

readonly ACTION_LOG_SCHEMA_VERSION='1'
ACTION_LOG_DIRECTORY=''
ACTION_LOG_FILE=''

action_log_sanitize_value() {
  local value="$1"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value//$'\t'/ }"
  printf '%s' "${value}"
}

action_log_write() {
  local log_file="$1" key="$2" value="$3"
  [[ "${key}" =~ ^[a-z][a-z0-9_]*$ ]] || {
    error "Refusing unsafe action-log field: ${key}"
    return "${EXIT_UNKNOWN}"
  }
  printf '%s=%s\n' "${key}" "$(action_log_sanitize_value "${value}")" >> "${log_file}"
}

action_log_event() {
  local log_file="$1" event="$2"
  action_log_write "${log_file}" 'timestamp_utc' "$(date -u +%Y%m%dT%H%M%SZ)" || return $?
  action_log_write "${log_file}" 'event' "${event}"
}

action_log_result() {
  local log_file="$1" result="$2" exit_code="$3"
  action_log_event "${log_file}" 'action_completed' || return $?
  action_log_write "${log_file}" 'final_result' "${result}" || return $?
  action_log_write "${log_file}" 'exit_code' "${exit_code}"
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
  local action="$1"
  [[ "${action}" =~ ^[a-z][a-z0-9-]{0,63}$ ]] || {
    error 'Refusing unsafe action-log name.'
    return "${EXIT_USAGE}"
  }
  prepare_action_log_directory || return $?
  umask 077
  ACTION_LOG_FILE="$(mktemp "${ACTION_LOG_DIRECTORY}/$(date -u +%Y%m%dT%H%M%SZ)_${action}.XXXXXX.log")" || {
    error "Unable to create action log in ${ACTION_LOG_DIRECTORY}"
    return "${EXIT_UNKNOWN}"
  }
  action_log_write "${ACTION_LOG_FILE}" 'log_schema_version' "${ACTION_LOG_SCHEMA_VERSION}" || return $?
  action_log_write "${ACTION_LOG_FILE}" 'action' "${action}" || return $?
  action_log_write "${ACTION_LOG_FILE}" 'invoking_user' "${SUDO_USER:-$(id -un)}" || return $?
  action_log_write "${ACTION_LOG_FILE}" 'effective_user' "$(id -un)" || return $?
  action_log_write "${ACTION_LOG_FILE}" 'hostname' "$(hostname 2>/dev/null || printf unavailable)" || return $?
  action_log_event "${ACTION_LOG_FILE}" 'action_started' || return $?
  ln -sfn "$(basename "${ACTION_LOG_FILE}")" "${ACTION_LOG_DIRECTORY}/latest.log"
}

action_log_read_field() {
  local log_file="$1" expected_key="$2" line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" == "${expected_key}="* ]] || continue
    printf '%s' "${line#*=}"
    return 0
  done < "${log_file}"
  return 1
}

action_log_show_recent_activity() {
  local record file log_file action timestamp result
  local -a records=()

  if [[ ! -d "${ACTION_LOG_DIRECTORY}" ]]; then
    printf '%s\n' 'No state-changing activity has been logged yet.'
    return 0
  fi

  mapfile -t records < <(find "${ACTION_LOG_DIRECTORY}" -maxdepth 1 -type f -name '*.log' -printf '%T@ %f\n' | sort -rn | head -n 12)
  if (( ${#records[@]} == 0 )); then
    printf '%s\n' 'No state-changing activity has been logged yet.'
    return 0
  fi

  printf '%s\n' 'Recent protected action activity (newest first)'
  for record in "${records[@]}"; do
    file="${record#* }"
    log_file="${ACTION_LOG_DIRECTORY}/${file}"
    action="$(action_log_read_field "${log_file}" 'action' || printf unknown)"
    timestamp="$(action_log_read_field "${log_file}" 'timestamp_utc' || printf unknown)"
    result="$(action_log_read_field "${log_file}" 'final_result' || printf INCOMPLETE)"
    printf '  %-16s %-23s %s\n' "${action}" "${result}" "${timestamp}"
  done
  printf '%s\n' 'Detailed logs remain root-protected in /var/log/fedora-radio-control/.'
}
