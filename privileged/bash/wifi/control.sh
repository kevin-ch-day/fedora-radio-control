#!/usr/bin/env bash
# Verified Wi-Fi controls. Enable is deliberately explicit because existing
# NetworkManager profiles may reconnect after the radio becomes available.

WIFI_CONTROL_LOG_FILE=''

wifi_control_log() {
  action_log_write "${WIFI_CONTROL_LOG_FILE}" "$1" "$2"
}

wifi_control_begin_log() {
  local action="$1"
  begin_action_log "wifi-${action}" || return $?
  WIFI_CONTROL_LOG_FILE="${ACTION_LOG_FILE}"
  action_log_write "${WIFI_CONTROL_LOG_FILE}" 'requested_action' "wifi_${action}"
}

wifi_control_log_state() {
  local phase="$1"
  local entry index device soft hard
  action_log_event "${WIFI_CONTROL_LOG_FILE}" 'state_snapshot'
  wifi_control_log 'state_phase' "${phase}"
  wifi_control_log 'wifi_networkmanager' "${WIFI_RADIO_STATE}"
  wifi_control_log 'wifi_effective' "${WIFI_EFFECTIVE}"
  for entry in "${WIFI_RFKILL[@]}"; do
    IFS='|' read -r index device soft hard <<< "${entry}"
    wifi_control_log 'wifi_rfkill' "${index}:${device}:soft=${soft}:hard=${hard}"
  done
}

wifi_control_attempt() {
  local description="$1" status
  shift
  action_log_event "${WIFI_CONTROL_LOG_FILE}" 'command_attempt'
  wifi_control_log 'attempt' "${description}"
  if "$@" >/dev/null 2>&1; then
    action_log_event "${WIFI_CONTROL_LOG_FILE}" 'command_result'
    wifi_control_log 'attempt' "${description}"
    wifi_control_log 'result' 'ok'
    wifi_control_log 'exit_code' '0'
    return 0
  else
    status=$?
  fi
  action_log_event "${WIFI_CONTROL_LOG_FILE}" 'command_result'
  wifi_control_log 'attempt' "${description}"
  wifi_control_log 'result' 'failed'
  wifi_control_log 'exit_code' "${status}"
  return 1
}

wifi_enable_verified() {
  local entry _index _device soft hard
  [[ "${WIFI_RADIO_STATE}" == 'enabled' ]] || return 1
  (( WIFI_RFKILL_COUNT > 0 )) || return 1
  for entry in "${WIFI_RFKILL[@]}"; do
    IFS='|' read -r _index _device soft hard <<< "${entry}"
    [[ "${hard}" == 'blocked' ]] && return 1
    [[ "${soft}" == 'unblocked' ]] || return 1
  done
}

wifi_disable_apply() {
  local final_status
  wifi_control_begin_log 'disable' || return $?
  refresh_radio_state
  wifi_control_log_state 'before'
  wifi_control_attempt 'disable_networkmanager_wifi' nmcli radio wifi off || true
  wifi_control_attempt 'block_wlan_rfkill' rfkill block wlan || true
  refresh_radio_state
  wifi_control_log_state 'after'
  if [[ "${WIFI_EFFECTIVE}" == 'disabled' ]]; then
    action_log_result "${WIFI_CONTROL_LOG_FILE}" 'DISABLED' "${EXIT_OK}"
    success "Wi-Fi disable verified. Log: ${WIFI_CONTROL_LOG_FILE}"
    return "${EXIT_OK}"
  fi
  final_status="${EXIT_POLICY}"
  (( WIFI_QUERY_FAILED )) && final_status="${EXIT_UNKNOWN}"
  action_log_result "${WIFI_CONTROL_LOG_FILE}" 'NOT_DISABLED' "${final_status}"
  error "Wi-Fi disable was not verified. Log: ${WIFI_CONTROL_LOG_FILE}"
  return "${final_status}"
}

wifi_enable_apply() {
  local final_status
  wifi_control_begin_log 'enable' || return $?
  refresh_radio_state
  wifi_control_log_state 'before'
  wifi_control_attempt 'unblock_wlan_rfkill' rfkill unblock wlan || true
  wifi_control_attempt 'enable_networkmanager_wifi' nmcli radio wifi on || true
  refresh_radio_state
  wifi_control_log_state 'after'
  if wifi_enable_verified; then
    action_log_result "${WIFI_CONTROL_LOG_FILE}" 'ENABLED' "${EXIT_OK}"
    success "Wi-Fi enable verified. Log: ${WIFI_CONTROL_LOG_FILE}"
    return "${EXIT_OK}"
  fi
  final_status="${EXIT_POLICY}"
  (( WIFI_QUERY_FAILED )) && final_status="${EXIT_UNKNOWN}"
  action_log_result "${WIFI_CONTROL_LOG_FILE}" 'NOT_ENABLED' "${final_status}"
  error "Wi-Fi enable was not verified. A hardware RFKill block cannot be removed by software. Log: ${WIFI_CONTROL_LOG_FILE}"
  return "${final_status}"
}
