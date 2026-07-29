#!/usr/bin/env bash
# Read-only Bluetooth service and controller state collection.

BLUETOOTH_RFKILL_COUNT=0
BLUETOOTH_SERVICE_ACTIVE='unknown'
BLUETOOTH_SERVICE_ENABLED='unknown'
BLUETOOTH_CONTROLLER='unknown'
BLUETOOTH_ADDRESS=''
BLUETOOTH_ALIAS=''
BLUETOOTH_POWERED='unknown'
BLUETOOTH_DISCOVERABLE='unknown'
BLUETOOTH_PAIRABLE='unknown'
BLUETOOTH_DISCOVERABLE_TIMEOUT='unknown'
BLUETOOTH_PAIRABLE_TIMEOUT='unknown'
BLUETOOTH_EFFECTIVE='unknown'
declare -a BLUETOOTH_RFKILL=()

collect_bluetooth_service_state() {
  if ! BLUETOOTH_SERVICE_ACTIVE="$(systemctl show bluetooth.service --property=ActiveState --value 2>/dev/null)"; then
    error 'Unable to query bluetooth.service active state.'
    BLUETOOTH_SERVICE_ACTIVE='unknown'
    mark_query_failure
  fi
  if ! BLUETOOTH_SERVICE_ENABLED="$(systemctl show bluetooth.service --property=UnitFileState --value 2>/dev/null)"; then
    error 'Unable to query bluetooth.service enabled state.'
    mark_query_failure
  fi
  BLUETOOTH_SERVICE_ACTIVE="${BLUETOOTH_SERVICE_ACTIVE//$'\n'/}"
  BLUETOOTH_SERVICE_ENABLED="${BLUETOOTH_SERVICE_ENABLED//$'\n'/}"
}

collect_bluetooth_controller() {
  local controller_output controller_line
  BLUETOOTH_ADDRESS=''
  BLUETOOTH_ALIAS=''
  BLUETOOTH_POWERED='unknown'
  BLUETOOTH_DISCOVERABLE='unknown'
  BLUETOOTH_PAIRABLE='unknown'
  BLUETOOTH_DISCOVERABLE_TIMEOUT='unknown'
  BLUETOOTH_PAIRABLE_TIMEOUT='unknown'
  if ! command -v bluetoothctl >/dev/null 2>&1; then
    BLUETOOTH_CONTROLLER='tool-unavailable'
    return
  fi
  if ! controller_output="$(bluetoothctl --timeout 2 show 2>&1)"; then
    if [[ "${controller_output}" == *'No default controller available'* ]]; then
      BLUETOOTH_CONTROLLER='unavailable'
      return
    fi
    error 'Unable to query the Bluetooth controller.'
    BLUETOOTH_CONTROLLER='unknown'
    mark_query_failure
    return
  fi

  if [[ "${controller_output}" == *'No default controller available'* ]]; then
    BLUETOOTH_CONTROLLER='unavailable'
    return
  fi
  controller_line="$(printf '%s\n' "${controller_output}" | sed -nE 's/^[[:space:]]*Controller[[:space:]]+([0-9A-Fa-f:]+)[[:space:]]+.*$/\1/p' | head -n 1)"
  if [[ -z "${controller_line}" ]]; then
    error 'Bluetooth controller output was unrecognized.'
    BLUETOOTH_CONTROLLER='unknown'
    mark_query_failure
    return
  fi

  BLUETOOTH_CONTROLLER='available'
  BLUETOOTH_ADDRESS="${controller_line}"
  BLUETOOTH_ALIAS="$(printf '%s\n' "${controller_output}" | sed -nE 's/^[[:space:]]*Alias:[[:space:]]*(.*)$/\1/p' | head -n 1)"
  BLUETOOTH_POWERED="$(printf '%s\n' "${controller_output}" | sed -nE 's/^[[:space:]]*Powered:[[:space:]]*(yes|no)$/\1/p' | head -n 1)"
  BLUETOOTH_DISCOVERABLE="$(printf '%s\n' "${controller_output}" | sed -nE 's/^[[:space:]]*Discoverable:[[:space:]]*(yes|no)$/\1/p' | head -n 1)"
  BLUETOOTH_PAIRABLE="$(printf '%s\n' "${controller_output}" | sed -nE 's/^[[:space:]]*Pairable:[[:space:]]*(yes|no)$/\1/p' | head -n 1)"
  BLUETOOTH_DISCOVERABLE_TIMEOUT="$(printf '%s\n' "${controller_output}" | sed -nE 's/^[[:space:]]*DiscoverableTimeout:[[:space:]]*([0-9]+)$/\1/p' | head -n 1)"
  BLUETOOTH_PAIRABLE_TIMEOUT="$(printf '%s\n' "${controller_output}" | sed -nE 's/^[[:space:]]*PairableTimeout:[[:space:]]*([0-9]+)$/\1/p' | head -n 1)"
  [[ -n "${BLUETOOTH_POWERED}" ]] || BLUETOOTH_POWERED='unknown'
  [[ -n "${BLUETOOTH_DISCOVERABLE}" ]] || BLUETOOTH_DISCOVERABLE='unknown'
  [[ -n "${BLUETOOTH_PAIRABLE}" ]] || BLUETOOTH_PAIRABLE='unknown'
  [[ -n "${BLUETOOTH_DISCOVERABLE_TIMEOUT}" ]] || BLUETOOTH_DISCOVERABLE_TIMEOUT='unknown'
  [[ -n "${BLUETOOTH_PAIRABLE_TIMEOUT}" ]] || BLUETOOTH_PAIRABLE_TIMEOUT='unknown'
}

report_bluetooth_state() {
  refresh_radio_state

  ui_heading 'Bluetooth State'
  ui_label 'Service active:' "${BLUETOOTH_SERVICE_ACTIVE}"
  ui_label 'Service enabled:' "${BLUETOOTH_SERVICE_ENABLED}"
  case "${BLUETOOTH_CONTROLLER}" in
    available)
      ui_label 'Controller:' 'available'
      ui_label 'Powered:' "${BLUETOOTH_POWERED}"
      ui_label 'Discoverable:' "${BLUETOOTH_DISCOVERABLE}"
      ui_label 'Pairable:' "${BLUETOOTH_PAIRABLE}"
      ui_label 'Discoverable timeout:' "${BLUETOOTH_DISCOVERABLE_TIMEOUT}"
      ui_label 'Pairable timeout:' "${BLUETOOTH_PAIRABLE_TIMEOUT}"
      ;;
    unavailable) ui_label 'Controller:' 'ADAPTER UNAVAILABLE' ;;
    tool-unavailable) ui_label 'Controller:' 'NOT ASSESSED (bluetoothctl unavailable)' ;;
    *) ui_label 'Controller:' 'STATE UNKNOWN' ;;
  esac
  ui_label 'RFKill devices:' "${BLUETOOTH_RFKILL_COUNT}"
  if (( BLUETOOTH_RFKILL_COUNT == 0 )); then
    ui_label 'Hardware:' 'NOT DETECTED'
  else
    print_rfkill_entries "${BLUETOOTH_RFKILL[@]}"
  fi
  printf '\n'
  case "${BLUETOOTH_EFFECTIVE}" in
    disabled) ui_label 'Effective state:' 'DISABLED' ;;
    unknown) ui_label 'Effective state:' 'STATE UNKNOWN' ;;
    *)
      ui_label 'Effective state:' 'NOT FULLY DISABLED'
      if [[ "${BLUETOOTH_SERVICE_ACTIVE}" != 'inactive' ]]; then
        ui_label 'Policy blocker:' "bluetooth.service is ${BLUETOOTH_SERVICE_ACTIVE}"
      elif (( BLUETOOTH_RFKILL_COUNT == 0 )); then
        ui_label 'Policy blocker:' 'Bluetooth RFKill hardware was not detected'
      else
        ui_label 'Policy blocker:' 'a Bluetooth RFKill device remains unblocked'
      fi
      ;;
  esac
}
