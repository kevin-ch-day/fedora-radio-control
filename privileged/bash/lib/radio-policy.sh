#!/usr/bin/env bash
# Query health, effective radio state, and combined lockdown policy.

STATE_QUERY_FAILED=0
WIFI_QUERY_FAILED=0
BLUETOOTH_QUERY_FAILED=0
STATE_QUERY_SCOPE=''

mark_query_failure() {
  STATE_QUERY_FAILED=1
  case "${STATE_QUERY_SCOPE}" in
    wifi) WIFI_QUERY_FAILED=1 ;;
    bluetooth) BLUETOOTH_QUERY_FAILED=1 ;;
    shared)
      WIFI_QUERY_FAILED=1
      BLUETOOTH_QUERY_FAILED=1
      ;;
  esac
}

evaluate_effective_state() {
  if (( WIFI_QUERY_FAILED )); then
    WIFI_EFFECTIVE='unknown'
  elif [[ "${WIFI_RADIO_STATE}" == 'disabled' ]] && rfkill_entries_disabled "${WIFI_RFKILL[@]}"; then
    WIFI_EFFECTIVE='disabled'
  else
    WIFI_EFFECTIVE='not fully disabled'
  fi

  if (( BLUETOOTH_QUERY_FAILED )); then
    BLUETOOTH_EFFECTIVE='unknown'
  elif [[ "${BLUETOOTH_SERVICE_ACTIVE}" == 'inactive' ]] && rfkill_entries_disabled "${BLUETOOTH_RFKILL[@]}" && { [[ "${BLUETOOTH_CONTROLLER}" != 'available' ]] || { [[ "${BLUETOOTH_POWERED}" == 'no' ]] && [[ "${BLUETOOTH_DISCOVERABLE}" == 'no' ]] && [[ "${BLUETOOTH_PAIRABLE}" == 'no' ]]; }; }; then
    BLUETOOTH_EFFECTIVE='disabled'
  else
    BLUETOOTH_EFFECTIVE='not fully disabled'
  fi
}

refresh_radio_state() {
  STATE_QUERY_FAILED=0
  WIFI_QUERY_FAILED=0
  BLUETOOTH_QUERY_FAILED=0

  STATE_QUERY_SCOPE='shared'
  collect_rfkill
  STATE_QUERY_SCOPE='wifi'
  collect_wifi_state
  STATE_QUERY_SCOPE='bluetooth'
  collect_bluetooth_service_state
  collect_bluetooth_controller
  STATE_QUERY_SCOPE=''
  evaluate_effective_state
}

current_policy_result() {
  if (( STATE_QUERY_FAILED )); then
    printf 'STATE UNKNOWN'
  elif [[ "${WIFI_EFFECTIVE}" == 'disabled' && "${BLUETOOTH_EFFECTIVE}" == 'disabled' ]]; then
    printf 'LOCKED DOWN'
  else
    printf 'NOT LOCKED DOWN'
  fi
}

policy_reason() {
  if (( STATE_QUERY_FAILED )); then
    printf 'one or more radio states could not be queried reliably'
  elif [[ "${WIFI_EFFECTIVE}" != 'disabled' ]]; then
    if (( WIFI_RFKILL_COUNT == 0 )); then
      printf 'Wi-Fi hardware was not detected'
    elif [[ "${WIFI_RADIO_STATE}" != 'disabled' ]]; then
      printf 'NetworkManager Wi-Fi radio remains %s' "${WIFI_RADIO_STATE}"
    else
      printf 'a Wi-Fi RFKill device remains unblocked'
    fi
  elif [[ "${BLUETOOTH_EFFECTIVE}" != 'disabled' ]]; then
    if (( BLUETOOTH_RFKILL_COUNT == 0 )); then
      printf 'Bluetooth hardware was not detected'
    elif [[ "${BLUETOOTH_SERVICE_ACTIVE}" != 'inactive' ]]; then
      printf 'bluetooth.service remains %s' "${BLUETOOTH_SERVICE_ACTIVE}"
    else
      printf 'a Bluetooth RFKill device remains unblocked'
    fi
  fi
}
