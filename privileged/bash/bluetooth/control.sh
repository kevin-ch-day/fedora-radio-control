#!/usr/bin/env bash
# Verified Bluetooth disable control. Bluetooth enable remains intentionally
# unavailable until its distinct exposure-confirmation policy is implemented.

BLUETOOTH_CONTROL_LOG_FILE=''

bluetooth_control_log() {
  action_log_write "${BLUETOOTH_CONTROL_LOG_FILE}" "$1" "$2"
}

bluetooth_control_begin_log() {
  begin_action_log 'bluetooth-disable' || return $?
  BLUETOOTH_CONTROL_LOG_FILE="${ACTION_LOG_FILE}"
  action_log_write "${BLUETOOTH_CONTROL_LOG_FILE}" 'requested_action' 'bluetooth_disable'
}

bluetooth_control_log_state() {
  local phase="$1"
  local entry index device soft hard
  action_log_event "${BLUETOOTH_CONTROL_LOG_FILE}" 'state_snapshot'
  bluetooth_control_log 'state_phase' "${phase}"
  bluetooth_control_log 'bluetooth_service_active' "${BLUETOOTH_SERVICE_ACTIVE}"
  bluetooth_control_log 'bluetooth_controller' "${BLUETOOTH_CONTROLLER}"
  bluetooth_control_log 'bluetooth_effective' "${BLUETOOTH_EFFECTIVE}"
  for entry in "${BLUETOOTH_RFKILL[@]}"; do
    IFS='|' read -r index device soft hard <<< "${entry}"
    bluetooth_control_log 'bluetooth_rfkill' "${index}:${device}:soft=${soft}:hard=${hard}"
  done
}

bluetooth_control_attempt() {
  local description="$1" status
  shift
  action_log_event "${BLUETOOTH_CONTROL_LOG_FILE}" 'command_attempt'
  bluetooth_control_log 'attempt' "${description}"
  if "$@" >/dev/null 2>&1; then
    action_log_event "${BLUETOOTH_CONTROL_LOG_FILE}" 'command_result'
    bluetooth_control_log 'attempt' "${description}"
    bluetooth_control_log 'result' 'ok'
    bluetooth_control_log 'exit_code' '0'
    return 0
  else
    status=$?
  fi
  action_log_event "${BLUETOOTH_CONTROL_LOG_FILE}" 'command_result'
  bluetooth_control_log 'attempt' "${description}"
  bluetooth_control_log 'result' 'failed'
  bluetooth_control_log 'exit_code' "${status}"
  return 1
}

bluetooth_disable_apply() {
  local final_status
  bluetooth_control_begin_log || return $?
  refresh_radio_state
  bluetooth_control_log_state 'before'
  if [[ "${BLUETOOTH_CONTROLLER}" == 'available' ]] && command -v bluetoothctl >/dev/null 2>&1; then
    bluetooth_control_attempt 'power_off_bluetooth_controller' bluetoothctl --timeout 5 power off || true
  elif [[ "${BLUETOOTH_CONTROLLER}" == 'tool-unavailable' ]]; then
    action_log_event "${BLUETOOTH_CONTROL_LOG_FILE}" 'command_skipped'
    bluetooth_control_log 'attempt' 'power_off_bluetooth_controller'
    bluetooth_control_log 'reason' 'tool_unavailable'
  else
    action_log_event "${BLUETOOTH_CONTROL_LOG_FILE}" 'command_skipped'
    bluetooth_control_log 'attempt' 'power_off_bluetooth_controller'
    bluetooth_control_log 'reason' 'no_controller'
  fi
  bluetooth_control_attempt 'block_bluetooth_rfkill' rfkill block bluetooth || true
  bluetooth_control_attempt 'runtime_mask_bluetooth_service' systemctl mask --runtime bluetooth.service || true
  bluetooth_control_attempt 'stop_bluetooth_service' systemctl stop bluetooth.service || true
  refresh_radio_state
  bluetooth_control_log_state 'after'
  if [[ "${BLUETOOTH_EFFECTIVE}" == 'disabled' ]]; then
    action_log_result "${BLUETOOTH_CONTROL_LOG_FILE}" 'DISABLED' "${EXIT_OK}"
    printf 'Bluetooth disable verified. Log: %s\n' "${BLUETOOTH_CONTROL_LOG_FILE}"
    return "${EXIT_OK}"
  fi
  final_status="${EXIT_POLICY}"
  (( BLUETOOTH_QUERY_FAILED )) && final_status="${EXIT_UNKNOWN}"
  action_log_result "${BLUETOOTH_CONTROL_LOG_FILE}" 'NOT_DISABLED' "${final_status}"
  if [[ "${BLUETOOTH_SERVICE_ACTIVE}" != 'inactive' ]]; then
    error "bluetooth.service remains ${BLUETOOTH_SERVICE_ACTIVE}; Bluetooth is not fully disabled."
  fi
  error "Bluetooth disable was not verified. Log: ${BLUETOOTH_CONTROL_LOG_FILE}"
  return "${final_status}"
}
