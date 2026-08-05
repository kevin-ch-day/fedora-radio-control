#!/usr/bin/env bash
# Read-only Bluetooth service and controller state collection.

BLUETOOTH_RFKILL_COUNT=0
BLUETOOTH_SERVICE_ACTIVE='unknown'
BLUETOOTH_SERVICE_ENABLED='unknown'
BLUETOOTH_CONTROLLER='unknown'
BLUETOOTH_POWERED='unknown'
BLUETOOTH_DISCOVERABLE='unknown'
BLUETOOTH_PAIRABLE='unknown'
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
  BLUETOOTH_POWERED='unknown'
  BLUETOOTH_DISCOVERABLE='unknown'
  BLUETOOTH_PAIRABLE='unknown'
  if ! command -v bluetoothctl >/dev/null 2>&1; then
    BLUETOOTH_CONTROLLER='tool-unavailable'
    return
  fi
  # Once bluetooth.service is stopped, bluetoothctl may exit without output
  # because its D-Bus endpoint is gone. RFKill and service state are still
  # available evidence for a completed disable transaction.
  if [[ "${BLUETOOTH_SERVICE_ACTIVE}" == 'inactive' ]]; then
    BLUETOOTH_CONTROLLER='unavailable'
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
  BLUETOOTH_POWERED="$(printf '%s\n' "${controller_output}" | sed -nE 's/^[[:space:]]*Powered:[[:space:]]*(yes|no)$/\1/p' | head -n 1)"
  BLUETOOTH_DISCOVERABLE="$(printf '%s\n' "${controller_output}" | sed -nE 's/^[[:space:]]*Discoverable:[[:space:]]*(yes|no)$/\1/p' | head -n 1)"
  BLUETOOTH_PAIRABLE="$(printf '%s\n' "${controller_output}" | sed -nE 's/^[[:space:]]*Pairable:[[:space:]]*(yes|no)$/\1/p' | head -n 1)"
  [[ -n "${BLUETOOTH_POWERED}" ]] || BLUETOOTH_POWERED='unknown'
  [[ -n "${BLUETOOTH_DISCOVERABLE}" ]] || BLUETOOTH_DISCOVERABLE='unknown'
  [[ -n "${BLUETOOTH_PAIRABLE}" ]] || BLUETOOTH_PAIRABLE='unknown'
}
