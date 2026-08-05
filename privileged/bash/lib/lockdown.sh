#!/usr/bin/env bash
# Verified full radio lockdown transaction.

LOCKDOWN_LOG_FILE=''

lockdown_log() {
  action_log_write "${LOCKDOWN_LOG_FILE}" "$1" "$2"
}

lockdown_begin_log() {
  begin_action_log 'lockdown' || return $?
  LOCKDOWN_LOG_FILE="${ACTION_LOG_FILE}"
  action_log_write "${LOCKDOWN_LOG_FILE}" 'requested_action' 'lockdown'
}

lockdown_log_state() {
  local phase="$1"
  local entry index device soft hard
  action_log_event "${LOCKDOWN_LOG_FILE}" 'state_snapshot'
  lockdown_log 'state_phase' "${phase}"
  lockdown_log 'wifi_networkmanager' "${WIFI_RADIO_STATE}"
  lockdown_log 'wifi_effective' "${WIFI_EFFECTIVE}"
  for entry in "${WIFI_RFKILL[@]}"; do
    IFS='|' read -r index device soft hard <<< "${entry}"
    lockdown_log 'wifi_rfkill' "${index}:${device}:soft=${soft}:hard=${hard}"
  done
  lockdown_log 'bluetooth_service_active' "${BLUETOOTH_SERVICE_ACTIVE}"
  lockdown_log 'bluetooth_service_enabled' "${BLUETOOTH_SERVICE_ENABLED}"
  lockdown_log 'bluetooth_controller' "${BLUETOOTH_CONTROLLER}"
  lockdown_log 'bluetooth_effective' "${BLUETOOTH_EFFECTIVE}"
  for entry in "${BLUETOOTH_RFKILL[@]}"; do
    IFS='|' read -r index device soft hard <<< "${entry}"
    lockdown_log 'bluetooth_rfkill' "${index}:${device}:soft=${soft}:hard=${hard}"
  done
}

lockdown_attempt() {
  local description="$1" status
  shift
  action_log_event "${LOCKDOWN_LOG_FILE}" 'command_attempt'
  lockdown_log 'attempt' "${description}"
  if "$@" >/dev/null 2>&1; then
    action_log_event "${LOCKDOWN_LOG_FILE}" 'command_result'
    lockdown_log 'attempt' "${description}"
    lockdown_log 'result' 'ok'
    lockdown_log 'exit_code' '0'
    return 0
  else
    status=$?
  fi
  action_log_event "${LOCKDOWN_LOG_FILE}" 'command_result'
  lockdown_log 'attempt' "${description}"
  lockdown_log 'result' 'failed'
  lockdown_log 'exit_code' "${status}"
  return 1
}

lockdown_apply() {
  local attempt_failed=0

  lockdown_begin_log || return $?
  refresh_radio_state
  lockdown_log_state 'before'

  lockdown_attempt 'disable_networkmanager_wifi' nmcli radio wifi off || attempt_failed=1
  lockdown_attempt 'block_wlan_rfkill' rfkill block wlan || attempt_failed=1

  if [[ "${BLUETOOTH_CONTROLLER}" == 'available' ]] && command -v bluetoothctl >/dev/null 2>&1; then
    lockdown_attempt 'power_off_bluetooth_controller' bluetoothctl --timeout 5 power off || attempt_failed=1
  elif [[ "${BLUETOOTH_CONTROLLER}" == 'tool-unavailable' ]]; then
    action_log_event "${LOCKDOWN_LOG_FILE}" 'command_skipped'
    lockdown_log 'attempt' 'power_off_bluetooth_controller'
    lockdown_log 'reason' 'tool_unavailable'
  else
    action_log_event "${LOCKDOWN_LOG_FILE}" 'command_skipped'
    lockdown_log 'attempt' 'power_off_bluetooth_controller'
    lockdown_log 'reason' 'no_controller'
  fi
  lockdown_attempt 'block_bluetooth_rfkill' rfkill block bluetooth || attempt_failed=1
  lockdown_attempt 'runtime_mask_bluetooth_service' systemctl mask --runtime bluetooth.service || attempt_failed=1
  lockdown_attempt 'stop_bluetooth_service' systemctl stop bluetooth.service || attempt_failed=1

  refresh_radio_state
  lockdown_log_state 'after'
  if [[ "$(current_policy_result)" == 'LOCKED DOWN' ]]; then
    action_log_result "${LOCKDOWN_LOG_FILE}" 'LOCKED_DOWN' "${EXIT_OK}"
    success "Lockdown verified. Log: ${LOCKDOWN_LOG_FILE}"
    return "${EXIT_OK}"
  fi

  if (( STATE_QUERY_FAILED )); then
    action_log_result "${LOCKDOWN_LOG_FILE}" 'STATE_UNKNOWN' "${EXIT_UNKNOWN}"
    error "Lockdown could not be verified. Log: ${LOCKDOWN_LOG_FILE}"
    return "${EXIT_UNKNOWN}"
  fi

  action_log_result "${LOCKDOWN_LOG_FILE}" 'NOT_LOCKED_DOWN' "${EXIT_POLICY}"
  error "Lockdown was not verified. Log: ${LOCKDOWN_LOG_FILE}"
  (( attempt_failed )) && return "${EXIT_POLICY}"
  return "${EXIT_POLICY}"
}
