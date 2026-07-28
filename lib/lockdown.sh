#!/usr/bin/env bash
# Verified full radio lockdown transaction.

LOCKDOWN_LOG_FILE=''

lockdown_log() {
  printf '%s\n' "$*" >> "${LOCKDOWN_LOG_FILE}"
}

lockdown_begin_log() {
  local invoking_user
  begin_action_log 'lockdown' || return $?
  LOCKDOWN_LOG_FILE="${ACTION_LOG_FILE}"
  invoking_user="${SUDO_USER:-$(id -un)}"
  lockdown_log "timestamp_utc=$(date -u +%Y%m%dT%H%M%SZ)"
  lockdown_log "invoking_user=${invoking_user}"
  lockdown_log 'requested_action=lockdown'
}

lockdown_log_state() {
  local phase="$1"
  local entry index device soft hard
  lockdown_log "state_phase=${phase}"
  lockdown_log "wifi_networkmanager=${WIFI_RADIO_STATE}"
  lockdown_log "wifi_effective=${WIFI_EFFECTIVE}"
  for entry in "${WIFI_RFKILL[@]}"; do
    IFS='|' read -r index device soft hard <<< "${entry}"
    lockdown_log "wifi_rfkill=${index}:${device}:soft=${soft}:hard=${hard}"
  done
  lockdown_log "bluetooth_service_active=${BLUETOOTH_SERVICE_ACTIVE}"
  lockdown_log "bluetooth_service_enabled=${BLUETOOTH_SERVICE_ENABLED}"
  lockdown_log "bluetooth_controller=${BLUETOOTH_CONTROLLER}"
  lockdown_log "bluetooth_effective=${BLUETOOTH_EFFECTIVE}"
  for entry in "${BLUETOOTH_RFKILL[@]}"; do
    IFS='|' read -r index device soft hard <<< "${entry}"
    lockdown_log "bluetooth_rfkill=${index}:${device}:soft=${soft}:hard=${hard}"
  done
}

lockdown_attempt() {
  local description="$1" status
  shift
  lockdown_log "attempt=${description}"
  if "$@" >/dev/null 2>&1; then
    lockdown_log "attempt_result=${description}:ok"
    return 0
  else
    status=$?
  fi
  lockdown_log "attempt_result=${description}:failed:exit=${status}"
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
    lockdown_log 'attempt=power_off_bluetooth_controller:skipped_tool_unavailable'
  else
    lockdown_log 'attempt=power_off_bluetooth_controller:skipped_no_controller'
  fi
  lockdown_attempt 'block_bluetooth_rfkill' rfkill block bluetooth || attempt_failed=1
  lockdown_attempt 'runtime_mask_bluetooth_service' systemctl mask --runtime bluetooth.service || attempt_failed=1
  lockdown_attempt 'stop_bluetooth_service' systemctl stop bluetooth.service || attempt_failed=1

  refresh_radio_state
  lockdown_log_state 'after'
  if [[ "$(current_policy_result)" == 'LOCKED DOWN' ]]; then
    lockdown_log 'final_result=LOCKED_DOWN'
    printf 'Lockdown verified. Log: %s\n' "${LOCKDOWN_LOG_FILE}"
    return "${EXIT_OK}"
  fi

  if (( STATE_QUERY_FAILED )); then
    lockdown_log 'final_result=STATE_UNKNOWN'
    error "Lockdown could not be verified. Log: ${LOCKDOWN_LOG_FILE}"
    return "${EXIT_UNKNOWN}"
  fi

  lockdown_log 'final_result=NOT_LOCKED_DOWN'
  error "Lockdown was not verified. Log: ${LOCKDOWN_LOG_FILE}"
  (( attempt_failed )) && return "${EXIT_POLICY}"
  return "${EXIT_POLICY}"
}
