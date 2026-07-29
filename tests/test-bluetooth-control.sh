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
# shellcheck source=../lib/radio-state.sh
source "${REPO_DIR}/privileged/bash/lib/radio-state.sh"
APPLICATION_ROOT="${TEST_DIR}"
# shellcheck source=../bluetooth/control.sh
source "${REPO_DIR}/privileged/bash/bluetooth/control.sh"

MOCK_BLUETOOTH_BLOCK='unblocked'
MOCK_BLUETOOTH_SERVICE='active'
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
    'stop bluetooth.service')
      MOCK_BLUETOOTH_SERVICE='inactive'
      MOCK_COMMANDS+=('systemctl stop bluetooth.service')
      ;;
    *) return 1 ;;
  esac
}

bluetoothctl() {
  printf '%s\n' 'No default controller available'
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

printf 'Bluetooth control tests passed.\n'
