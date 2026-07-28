#!/usr/bin/env bash
# Read-only collection and policy evaluation for radio status.

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

json_field() {
  local object="$1"
  local field="$2"
  local expression
  expression="\"${field}\"[[:space:]]*:[[:space:]]*\"?([^\",}[:space:]]+)\"?"

  if [[ "${object}" =~ ${expression} ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

collect_rfkill() {
  local raw_json object index type device soft hard
  WIFI_RFKILL=()
  BLUETOOTH_RFKILL=()
  WIFI_RFKILL_COUNT=0
  BLUETOOTH_RFKILL_COUNT=0

  if ! raw_json="$(rfkill --json 2>/dev/null)"; then
    error 'Unable to query RFKill state.'
    mark_query_failure
    return
  fi
  if [[ "${raw_json}" != *'"rfkilldevices"'* ]]; then
    error 'RFKill JSON output did not contain a device list.'
    mark_query_failure
    return
  fi

  while IFS= read -r object || [[ -n "${object}" ]]; do
    type="$(json_field "${object}" type || true)"
    [[ -n "${type}" ]] || continue
    index="$(json_field "${object}" id || json_field "${object}" index || true)"
    device="$(json_field "${object}" device || json_field "${object}" name || true)"
    soft="$(json_field "${object}" soft || true)"
    hard="$(json_field "${object}" hard || true)"
    if [[ -z "${index}" || -z "${device}" || -z "${soft}" || -z "${hard}" ]]; then
      error 'RFKill JSON output contained an incomplete device entry.'
      mark_query_failure
      continue
    fi

    case "${type}" in
      wlan)
        WIFI_RFKILL+=("${index}|${device}|${soft}|${hard}")
        ((WIFI_RFKILL_COUNT += 1))
        ;;
      bluetooth)
        BLUETOOTH_RFKILL+=("${index}|${device}|${soft}|${hard}")
        ((BLUETOOTH_RFKILL_COUNT += 1))
        ;;
    esac
  done < <(printf '%s\n' "${raw_json}" | tr '\n' ' ' | sed -E 's/}[[:space:]]*,?[[:space:]]*\{/}\n{/g')
}

rfkill_entries_disabled() {
  local entry _index _device soft hard
  (( $# > 0 )) || return 1
  for entry in "$@"; do
    IFS='|' read -r _index _device soft hard <<< "${entry}"
    if [[ "${soft}" != 'blocked' && "${hard}" != 'blocked' ]]; then
      return 1
    fi
  done
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
  elif [[ "${BLUETOOTH_SERVICE_ACTIVE}" == 'inactive' ]] && \
    rfkill_entries_disabled "${BLUETOOTH_RFKILL[@]}" && \
    { [[ "${BLUETOOTH_CONTROLLER}" != 'available' ]] || \
      { [[ "${BLUETOOTH_POWERED}" == 'no' ]] && [[ "${BLUETOOTH_DISCOVERABLE}" == 'no' ]] && [[ "${BLUETOOTH_PAIRABLE}" == 'no' ]]; }; }; then
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

rfkill_summary() {
  local entry _index _device soft hard
  (( $# > 0 )) || { printf 'NOT DETECTED'; return; }
  for entry in "$@"; do
    IFS='|' read -r _index _device soft hard <<< "${entry}"
    if [[ "${soft}" != 'blocked' && "${hard}" != 'blocked' ]]; then
      printf 'UNBLOCKED'
      return
    fi
  done
  printf 'BLOCKED'
}

rfkill_hardware_block_present() {
  local entry _index _device _soft hard
  for entry in "$@"; do
    IFS='|' read -r _index _device _soft hard <<< "${entry}"
    [[ "${hard}" == 'blocked' ]] && return 0
  done
  return 1
}

print_rfkill_entries() {
  local entry index device soft hard
  for entry in "$@"; do
    IFS='|' read -r index device soft hard <<< "${entry}"
    printf '\n  [%s] %s\n' "${index}" "${device}"
    printf '      Soft blocked: %s\n' "$([[ "${soft}" == 'blocked' ]] && printf yes || printf no)"
    printf '      Hard blocked: %s\n' "$([[ "${hard}" == 'blocked' ]] && printf yes || printf no)"
  done
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
  if [[ "${WIFI_EFFECTIVE}" == 'disabled' && "${BLUETOOTH_EFFECTIVE}" == 'disabled' ]]; then
    result='LOCKED DOWN'
    printf '  Result: %s\n' "$(ui_result "${result}")"
    return "${EXIT_OK}"
  fi
  result='NOT LOCKED DOWN'
  printf '  Result: %s\n' "$(ui_result "${result}")"
  printf '  Reason: %s\n' "$(policy_reason)"
  return "${EXIT_POLICY}"
}
