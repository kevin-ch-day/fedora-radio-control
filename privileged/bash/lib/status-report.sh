#!/usr/bin/env bash
# Detailed terminal rendering of current Wi-Fi, Bluetooth, and policy state.

report_status() {
  local fedora_name hostname current_user effective_user result

  refresh_radio_state
  fedora_name="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-Fedora Linux}")"
  hostname="$(hostname 2>/dev/null || printf 'unavailable')"
  effective_user="$(id -un 2>/dev/null || printf 'unavailable')"
  current_user="${SUDO_USER:-${effective_user}}"

  ui_heading 'Fedora Radio Control'
  ui_section 'System'
  ui_label 'Fedora:' "${fedora_name}"
  ui_label 'Hostname:' "${hostname}"
  if [[ "${current_user}" == "${effective_user}" ]]; then
    ui_label 'User:' "${current_user}"
  else
    ui_label 'Invoking user:' "${current_user}"
    ui_label 'Effective user:' "${effective_user}"
  fi

  ui_section 'Wi-Fi'
  ui_label 'NetworkManager radio:' "${WIFI_RADIO_STATE}"
  ui_label 'RFKill devices:' "${WIFI_RFKILL_COUNT}"
  if (( WIFI_RFKILL_COUNT == 0 )); then
    printf '  Hardware:              NOT DETECTED\n'
  else
    print_rfkill_entries "${WIFI_RFKILL[@]}"
  fi
  case "${WIFI_EFFECTIVE}" in
    disabled) printf '\n  Effective state: DISABLED\n' ;;
    unknown) printf '\n  Effective state: STATE UNKNOWN\n' ;;
    *) printf '\n  Effective state: NOT FULLY DISABLED\n' ;;
  esac

  ui_section 'Bluetooth'
  ui_label 'Service active:' "${BLUETOOTH_SERVICE_ACTIVE}"
  ui_label 'Service enabled:' "${BLUETOOTH_SERVICE_ENABLED}"
  case "${BLUETOOTH_CONTROLLER}" in
    available)
      printf '  Controller:            available\n'
      ui_label 'Controller powered:' "${BLUETOOTH_POWERED}"
      ui_label 'Controller discoverable:' "${BLUETOOTH_DISCOVERABLE}"
      ui_label 'Controller pairable:' "${BLUETOOTH_PAIRABLE}"
      ui_label 'Discoverable timeout:' "${BLUETOOTH_DISCOVERABLE_TIMEOUT}"
      ui_label 'Pairable timeout:' "${BLUETOOTH_PAIRABLE_TIMEOUT}"
      ;;
    unavailable) printf '  Controller:            ADAPTER UNAVAILABLE\n' ;;
    tool-unavailable) printf '  Controller:            NOT ASSESSED (bluetoothctl unavailable)\n' ;;
    *) printf '  Controller:            STATE UNKNOWN\n' ;;
  esac
  printf '  RFKill devices:        %s\n' "${BLUETOOTH_RFKILL_COUNT}"
  if (( BLUETOOTH_RFKILL_COUNT == 0 )); then
    printf '  Hardware:              NOT DETECTED\n'
  else
    print_rfkill_entries "${BLUETOOTH_RFKILL[@]}"
  fi
  case "${BLUETOOTH_EFFECTIVE}" in
    disabled) printf '\n  Effective state: DISABLED\n' ;;
    unknown) printf '\n  Effective state: STATE UNKNOWN\n' ;;
    *) printf '\n  Effective state: NOT FULLY DISABLED\n' ;;
  esac

  ui_section 'Policy'
  if (( STATE_QUERY_FAILED )); then
    result='STATE UNKNOWN'
    printf '  Result: %s\n' "$(ui_result "${result}")"
    printf '  Reason: %s\n' "$(policy_reason)"
    return "${EXIT_UNKNOWN}"
  fi
  if [[ "${WIFI_EFFECTIVE}" == disabled && "${BLUETOOTH_EFFECTIVE}" == disabled ]]; then
    result='LOCKED DOWN'
    printf '  Result: %s\n' "$(ui_result "${result}")"
    return "${EXIT_OK}"
  fi
  result='NOT LOCKED DOWN'
  printf '  Result: %s\n' "$(ui_result "${result}")"
  printf '  Reason: %s\n' "$(policy_reason)"
  return "${EXIT_POLICY}"
}
