#!/usr/bin/env bash
# Mocked lockdown transaction test. No system command below reaches the host.
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT

# shellcheck source=../lib/common.sh
source "${REPO_DIR}/lib/common.sh"
# shellcheck source=../wifi/state.sh
source "${REPO_DIR}/wifi/state.sh"
# shellcheck source=../bluetooth/state.sh
source "${REPO_DIR}/bluetooth/state.sh"
# shellcheck source=../lib/radio-state.sh
source "${REPO_DIR}/lib/radio-state.sh"
APPLICATION_ROOT="${REPO_DIR}"
# shellcheck source=../lib/lockdown.sh
source "${REPO_DIR}/lib/lockdown.sh"

MOCK_WIFI='enabled'
MOCK_WIFI_BLOCK='unblocked'
MOCK_BLUETOOTH_BLOCK='unblocked'
MOCK_BLUETOOTH_SERVICE='active'
MOCK_COMMANDS=()
LOCKDOWN_LOG_DIR="${TEST_DIR}/logs"

nmcli() {
  if [[ "$*" == '--terse --fields WIFI general status' ]]; then
    printf '%s\n' "${MOCK_WIFI}"
  elif [[ "$*" == 'radio wifi off' ]]; then
    MOCK_WIFI='disabled'
    MOCK_COMMANDS+=('nmcli radio wifi off')
  else
    return 1
  fi
}

rfkill() {
  case "$*" in
    --json)
      printf '{"rfkilldevices":[{"id":1,"type":"wlan","device":"wifi0","soft":"%s","hard":"unblocked"},{"id":2,"type":"bluetooth","device":"bt0","soft":"%s","hard":"unblocked"}]}' "${MOCK_WIFI_BLOCK}" "${MOCK_BLUETOOTH_BLOCK}"
      ;;
    'block wlan')
      MOCK_WIFI_BLOCK='blocked'
      MOCK_COMMANDS+=('rfkill block wlan')
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

lockdown_apply >/dev/null || fail 'mocked lockdown should verify successfully'
[[ "${MOCK_WIFI}" == 'disabled' ]] || fail 'Wi-Fi was not disabled'
[[ "${MOCK_WIFI_BLOCK}" == 'blocked' ]] || fail 'Wi-Fi was not RFKill-blocked'
[[ "${MOCK_BLUETOOTH_BLOCK}" == 'blocked' ]] || fail 'Bluetooth was not RFKill-blocked'
[[ "${MOCK_BLUETOOTH_SERVICE}" == 'inactive' ]] || fail 'Bluetooth service was not stopped'
[[ "${#MOCK_COMMANDS[@]}" -eq 5 ]] || fail 'unexpected number of mutation attempts'
[[ -L "${LOCKDOWN_LOG_DIR}/latest.log" ]] || fail 'latest log link was not created'
grep -Fq 'final_result=LOCKED_DOWN' "${LOCKDOWN_LOG_FILE}" || fail 'verified result was not logged'
grep -Fq 'attempt=disable_networkmanager_wifi' "${LOCKDOWN_LOG_FILE}" || fail 'Wi-Fi disable was not logged'
grep -Fq 'attempt=stop_bluetooth_service' "${LOCKDOWN_LOG_FILE}" || fail 'Bluetooth stop was not logged'
grep -Fq 'attempt=runtime_mask_bluetooth_service' "${LOCKDOWN_LOG_FILE}" || fail 'Bluetooth runtime mask was not logged'

printf 'Lockdown transaction tests passed.\n'
