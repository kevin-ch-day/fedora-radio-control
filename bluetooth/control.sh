#!/usr/bin/env bash
# Verified Bluetooth disable control. Bluetooth enable remains intentionally
# unavailable until its distinct exposure-confirmation policy is implemented.

BLUETOOTH_CONTROL_LOG_FILE=''

bluetooth_control_log() {
  printf '%s\n' "$*" >> "${BLUETOOTH_CONTROL_LOG_FILE}"
}

bluetooth_control_begin_log() {
  local timestamp
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "${APPLICATION_ROOT}/logs"
  BLUETOOTH_CONTROL_LOG_FILE="${APPLICATION_ROOT}/logs/${timestamp}_bluetooth-disable.log"
  : > "${BLUETOOTH_CONTROL_LOG_FILE}"
  chmod 600 "${BLUETOOTH_CONTROL_LOG_FILE}"
  grant_invoking_user_log_access "${BLUETOOTH_CONTROL_LOG_FILE}" || true
  ln -sfn "$(basename "${BLUETOOTH_CONTROL_LOG_FILE}")" "${APPLICATION_ROOT}/logs/latest.log"
  bluetooth_control_log "timestamp_utc=${timestamp}"
  bluetooth_control_log "invoking_user=${SUDO_USER:-$(id -un)}"
  bluetooth_control_log 'requested_action=bluetooth_disable'
}

bluetooth_control_log_state() {
  local phase="$1"
  local entry index device soft hard
  bluetooth_control_log "state_phase=${phase}"
  bluetooth_control_log "bluetooth_service_active=${BLUETOOTH_SERVICE_ACTIVE}"
  bluetooth_control_log "bluetooth_controller=${BLUETOOTH_CONTROLLER}"
  bluetooth_control_log "bluetooth_effective=${BLUETOOTH_EFFECTIVE}"
  for entry in "${BLUETOOTH_RFKILL[@]}"; do
    IFS='|' read -r index device soft hard <<< "${entry}"
    bluetooth_control_log "bluetooth_rfkill=${index}:${device}:soft=${soft}:hard=${hard}"
  done
}

bluetooth_control_attempt() {
  local description="$1"
  shift
  bluetooth_control_log "attempt=${description}"
  if "$@" >/dev/null 2>&1; then
    bluetooth_control_log "attempt_result=${description}:ok"
    return 0
  fi
  bluetooth_control_log "attempt_result=${description}:failed"
  return 1
}

bluetooth_disable_apply() {
  bluetooth_control_begin_log
  refresh_radio_state
  bluetooth_control_log_state 'before'
  if [[ "${BLUETOOTH_CONTROLLER}" == 'available' ]] && command -v bluetoothctl >/dev/null 2>&1; then
    bluetooth_control_attempt 'power_off_bluetooth_controller' bluetoothctl --timeout 5 power off || true
  elif [[ "${BLUETOOTH_CONTROLLER}" == 'tool-unavailable' ]]; then
    bluetooth_control_log 'attempt=power_off_bluetooth_controller:skipped_tool_unavailable'
  else
    bluetooth_control_log 'attempt=power_off_bluetooth_controller:skipped_no_controller'
  fi
  bluetooth_control_attempt 'block_bluetooth_rfkill' rfkill block bluetooth || true
  bluetooth_control_attempt 'runtime_mask_bluetooth_service' systemctl mask --runtime bluetooth.service || true
  bluetooth_control_attempt 'stop_bluetooth_service' systemctl stop bluetooth.service || true
  refresh_radio_state
  bluetooth_control_log_state 'after'
  if [[ "${BLUETOOTH_EFFECTIVE}" == 'disabled' ]]; then
    bluetooth_control_log 'final_result=DISABLED'
    printf 'Bluetooth disable verified. Log: %s\n' "${BLUETOOTH_CONTROL_LOG_FILE}"
    return "${EXIT_OK}"
  fi
  bluetooth_control_log 'final_result=NOT_DISABLED'
  if [[ "${BLUETOOTH_SERVICE_ACTIVE}" != 'inactive' ]]; then
    error "bluetooth.service remains ${BLUETOOTH_SERVICE_ACTIVE}; Bluetooth is not fully disabled."
  fi
  error "Bluetooth disable was not verified. Log: ${BLUETOOTH_CONTROL_LOG_FILE}"
  (( STATE_QUERY_FAILED )) && return "${EXIT_UNKNOWN}"
  return "${EXIT_POLICY}"
}
