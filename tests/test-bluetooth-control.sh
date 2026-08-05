#!/usr/bin/env bash
# Mocked Bluetooth disable transaction test. No system command reaches the host.
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT

# shellcheck source=../lib/common.sh
source "${REPO_DIR}/privileged/bash/lib/common.sh"
# shellcheck source=../wifi/state.sh
source "${REPO_DIR}/privileged/bash/wifi/state.sh"
# shellcheck source=../bluetooth/state.sh
source "${REPO_DIR}/privileged/bash/bluetooth/state.sh"
# shellcheck source=../lib/rfkill.sh
source "${REPO_DIR}/privileged/bash/lib/rfkill.sh"
# shellcheck source=../lib/radio-policy.sh
source "${REPO_DIR}/privileged/bash/lib/radio-policy.sh"
APPLICATION_ROOT="${TEST_DIR}"
# shellcheck source=../bluetooth/control.sh
source "${REPO_DIR}/privileged/bash/bluetooth/control.sh"

MOCK_BLUETOOTH_BLOCK='unblocked'
MOCK_BLUETOOTH_SERVICE='active'
MOCK_CONTROLLER='unavailable'
MOCK_CONTROLLER_POWER='no'
MOCK_COMMANDS=()

nmcli() {
  [[ "$*" == '--terse --fields WIFI general status' ]] && printf '%s\n' 'disabled'
}

rfkill() {
  case "$*" in
    --json)
      printf '{"rfkilldevices":[{"id":1,"type":"wlan","device":"wifi0","soft":"blocked","hard":"unblocked"},{"id":2,"type":"bluetooth","device":"bt0","soft":"%s","hard":"unblocked"}]}' "${MOCK_BLUETOOTH_BLOCK}"
      ;;
    'block bluetooth')
      MOCK_BLUETOOTH_BLOCK='blocked'
      MOCK_COMMANDS+=('rfkill block bluetooth')
      ;;
    'unblock bluetooth')
      MOCK_BLUETOOTH_BLOCK='unblocked'
      MOCK_COMMANDS+=('rfkill unblock bluetooth')
      ;;
    *) return 1 ;;
  esac
}

systemctl() {
  case "$*" in
    *ActiveState*) printf '%s\n' "${MOCK_BLUETOOTH_SERVICE}" ;;
    *UnitFileState*) printf '%s\n' 'enabled' ;;
    'mask --runtime bluetooth.service')
      MOCK_COMMANDS+=('systemctl mask --runtime bluetooth.service')
      ;;
    'unmask --runtime bluetooth.service')
      MOCK_COMMANDS+=('systemctl unmask --runtime bluetooth.service')
      ;;
    'stop bluetooth.service')
      MOCK_BLUETOOTH_SERVICE='inactive'
      MOCK_COMMANDS+=('systemctl stop bluetooth.service')
      ;;
    'start bluetooth.service')
      MOCK_BLUETOOTH_SERVICE='active'
      MOCK_COMMANDS+=('systemctl start bluetooth.service')
      ;;
    *) return 1 ;;
  esac
}

bluetoothctl() {
  case "$*" in
    '--timeout 2 show')
      if [[ "${MOCK_CONTROLLER}" == 'unavailable' ]]; then
        printf '%s\n' 'No default controller available'
      else
        printf 'Controller 00:11:22:33:44:55 Test Adapter\nPowered: %s\nDiscoverable: no\nPairable: no\n' "${MOCK_CONTROLLER_POWER}"
      fi
      ;;
    '--timeout 5 power on')
      MOCK_CONTROLLER_POWER='yes'
      MOCK_COMMANDS+=('bluetoothctl power on')
      ;;
    '--timeout 5 power off')
      MOCK_CONTROLLER_POWER='no'
      MOCK_COMMANDS+=('bluetoothctl power off')
      ;;
    *) return 1 ;;
  esac
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bluetooth_disable_apply >/dev/null || fail 'mocked Bluetooth disable should verify successfully'
[[ "${MOCK_BLUETOOTH_BLOCK}" == 'blocked' ]] || fail 'Bluetooth was not RFKill-blocked'
[[ "${MOCK_BLUETOOTH_SERVICE}" == 'inactive' ]] || fail 'Bluetooth service was not stopped'
[[ "${#MOCK_COMMANDS[@]}" -eq 3 ]] || fail 'unexpected number of mutation attempts'
[[ -L "${APPLICATION_ROOT}/logs/latest.log" ]] || fail 'latest log link was not created'
grep -Fq 'final_result=DISABLED' "${BLUETOOTH_CONTROL_LOG_FILE}" || fail 'verified result was not logged'
grep -Fq 'event=command_skipped' "${BLUETOOTH_CONTROL_LOG_FILE}" || fail 'unavailable controller skip was not logged'
grep -Fq 'reason=no_controller' "${BLUETOOTH_CONTROL_LOG_FILE}" || fail 'unavailable controller was not safely skipped'
grep -Fq 'attempt=runtime_mask_bluetooth_service' "${BLUETOOTH_CONTROL_LOG_FILE}" || fail 'runtime service mask was not logged'
grep -Fq 'event=action_completed' "${BLUETOOTH_CONTROL_LOG_FILE}" || fail 'action completion was not logged'

STATE_QUERY_FAILED=0
BLUETOOTH_QUERY_FAILED=0
BLUETOOTH_SERVICE_ACTIVE='inactive'
MOCK_CONTROLLER='query-failure'
collect_bluetooth_controller
[[ "${BLUETOOTH_CONTROLLER}" == 'unavailable' ]] || fail 'inactive Bluetooth service should not cause a controller query failure'
[[ "${BLUETOOTH_QUERY_FAILED}" == 0 ]] || fail 'inactive Bluetooth service must not mark Bluetooth state unknown'

MOCK_BLUETOOTH_BLOCK='blocked'
MOCK_BLUETOOTH_SERVICE='inactive'
MOCK_CONTROLLER='available'
MOCK_CONTROLLER_POWER='no'
MOCK_COMMANDS=()
bluetooth_enable_apply >/dev/null || fail 'mocked Bluetooth enable should verify successfully'
[[ "${MOCK_BLUETOOTH_BLOCK}" == 'unblocked' ]] || fail 'Bluetooth was not RFKill-unblocked'
[[ "${MOCK_BLUETOOTH_SERVICE}" == 'active' ]] || fail 'Bluetooth service was not started'
[[ "${MOCK_CONTROLLER_POWER}" == 'yes' ]] || fail 'Bluetooth controller was not powered on'
grep -Fq 'final_result=ENABLED' "${BLUETOOTH_CONTROL_LOG_FILE}" || fail 'Bluetooth enable result was not logged'
grep -Fq 'attempt=runtime_unmask_bluetooth_service' "${BLUETOOTH_CONTROL_LOG_FILE}" || fail 'runtime unmask was not logged'

MOCK_COMMANDS=()
bluetooth_power_apply off >/dev/null || fail 'mocked controller power-off should verify successfully'
[[ "${MOCK_CONTROLLER_POWER}" == 'no' ]] || fail 'Bluetooth controller was not powered off'
grep -Fq 'final_result=POWERED_OFF' "${BLUETOOTH_CONTROL_LOG_FILE}" || fail 'power-off result was not logged'

bluetooth_power_apply on >/dev/null || fail 'mocked controller power-on should verify successfully'
[[ "${MOCK_CONTROLLER_POWER}" == 'yes' ]] || fail 'Bluetooth controller was not powered on after power control'
grep -Fq 'final_result=POWERED_ON' "${BLUETOOTH_CONTROL_LOG_FILE}" || fail 'power-on result was not logged'

printf 'Bluetooth control tests passed.\n'
