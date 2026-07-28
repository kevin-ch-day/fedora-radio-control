#!/usr/bin/env bash
# Verified Wi-Fi controls. Enable is deliberately explicit because existing
# NetworkManager profiles may reconnect after the radio becomes available.

WIFI_CONTROL_LOG_FILE=''

wifi_autoconnect_profile_count() {
  local output line connection_type autoconnect count=0
  if ! output="$(nmcli --terse --fields TYPE,AUTOCONNECT connection show 2>/dev/null)"; then
    return 1
  fi
  while IFS= read -r line; do
    IFS=':' read -r connection_type autoconnect <<< "${line}"
    if [[ "${connection_type}" == 'wifi' || "${connection_type}" == '802-11-wireless' ]] && [[ "${autoconnect}" == 'yes' ]]; then
      ((count += 1))
    fi
  done <<< "${output}"
  printf '%s' "${count}"
}

wifi_control_log() {
  printf '%s\n' "$*" >> "${WIFI_CONTROL_LOG_FILE}"
}

wifi_control_begin_log() {
  local action="$1"
  begin_action_log "wifi-${action}" || return $?
  WIFI_CONTROL_LOG_FILE="${ACTION_LOG_FILE}"
  wifi_control_log "timestamp_utc=$(date -u +%Y%m%dT%H%M%SZ)"
  wifi_control_log "invoking_user=${SUDO_USER:-$(id -un)}"
  wifi_control_log "requested_action=wifi_${action}"
}

wifi_control_log_state() {
  local phase="$1"
  local entry index device soft hard
  wifi_control_log "state_phase=${phase}"
  wifi_control_log "wifi_networkmanager=${WIFI_RADIO_STATE}"
  wifi_control_log "wifi_effective=${WIFI_EFFECTIVE}"
  for entry in "${WIFI_RFKILL[@]}"; do
    IFS='|' read -r index device soft hard <<< "${entry}"
    wifi_control_log "wifi_rfkill=${index}:${device}:soft=${soft}:hard=${hard}"
  done
}

wifi_control_attempt() {
  local description="$1" status
  shift
  wifi_control_log "attempt=${description}"
  if "$@" >/dev/null 2>&1; then
    wifi_control_log "attempt_result=${description}:ok"
    return 0
  else
    status=$?
  fi
  wifi_control_log "attempt_result=${description}:failed:exit=${status}"
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
  wifi_control_begin_log 'disable' || return $?
  refresh_radio_state
  wifi_control_log_state 'before'
  wifi_control_attempt 'disable_networkmanager_wifi' nmcli radio wifi off || true
  wifi_control_attempt 'block_wlan_rfkill' rfkill block wlan || true
  refresh_radio_state
  wifi_control_log_state 'after'
  if [[ "${WIFI_EFFECTIVE}" == 'disabled' ]]; then
    wifi_control_log 'final_result=DISABLED'
    printf 'Wi-Fi disable verified. Log: %s\n' "${WIFI_CONTROL_LOG_FILE}"
    return "${EXIT_OK}"
  fi
  wifi_control_log 'final_result=NOT_DISABLED'
  error "Wi-Fi disable was not verified. Log: ${WIFI_CONTROL_LOG_FILE}"
  (( WIFI_QUERY_FAILED )) && return "${EXIT_UNKNOWN}"
  return "${EXIT_POLICY}"
}

wifi_enable_apply() {
  wifi_control_begin_log 'enable' || return $?
  refresh_radio_state
  wifi_control_log_state 'before'
  wifi_control_attempt 'unblock_wlan_rfkill' rfkill unblock wlan || true
  wifi_control_attempt 'enable_networkmanager_wifi' nmcli radio wifi on || true
  refresh_radio_state
  wifi_control_log_state 'after'
  if wifi_enable_verified; then
    wifi_control_log 'final_result=ENABLED'
    printf 'Wi-Fi enable verified. Log: %s\n' "${WIFI_CONTROL_LOG_FILE}"
    return "${EXIT_OK}"
  fi
  wifi_control_log 'final_result=NOT_ENABLED'
  error "Wi-Fi enable was not verified. A hardware RFKill block cannot be removed by software. Log: ${WIFI_CONTROL_LOG_FILE}"
  (( WIFI_QUERY_FAILED )) && return "${EXIT_UNKNOWN}"
  return "${EXIT_POLICY}"
}

wifi_confirm_enable() {
  local reply
  [[ -t 0 && -t 1 ]] || {
    error 'Wi-Fi enable requires an interactive terminal confirmation.'
    return "${EXIT_USAGE}"
  }
  printf '%s\n' 'WARNING: Enabling Wi-Fi increases radio exposure.' >&2
  printf '%s\n' 'Existing NetworkManager profiles may reconnect automatically.' >&2
  reply="$(prompt_read 'Type ENABLE-WIFI to continue: ')" || return "${EXIT_USAGE}"
  [[ "${reply}" == 'ENABLE-WIFI' ]] || {
    error 'Wi-Fi enable cancelled.'
    return "${EXIT_POLICY}"
  }
}
