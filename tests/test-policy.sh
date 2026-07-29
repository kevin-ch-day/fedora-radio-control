#!/usr/bin/env bash
# Hardware-independent policy tests. All system commands below are Bash mocks.
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck source=../lib/common.sh
source "${REPO_DIR}/privileged/bash/lib/common.sh"
# shellcheck source=../wifi/state.sh
source "${REPO_DIR}/privileged/bash/wifi/state.sh"
# shellcheck source=../bluetooth/state.sh
source "${REPO_DIR}/privileged/bash/bluetooth/state.sh"
# shellcheck source=../lib/radio-state.sh
source "${REPO_DIR}/privileged/bash/lib/radio-state.sh"

MOCK_RFKILL_JSON=''
MOCK_RFKILL_FAIL=0
MOCK_WIFI_STATE='disabled'
MOCK_BLUETOOTH_ACTIVE='inactive'
MOCK_BLUETOOTH_ENABLED='disabled'

nmcli() {
  printf '%s\n' "${MOCK_WIFI_STATE}"
}

rfkill() {
  (( MOCK_RFKILL_FAIL == 0 )) || return 1
  printf '%s\n' "${MOCK_RFKILL_JSON}"
}

systemctl() {
  case "$*" in
    *ActiveState*) printf '%s\n' "${MOCK_BLUETOOTH_ACTIVE}" ;;
    *UnitFileState*) printf '%s\n' "${MOCK_BLUETOOTH_ENABLED}" ;;
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

assert_equals() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  [[ "${actual}" == "${expected}" ]] || fail "${description}: expected ${expected}, got ${actual}"
}

set_fixture() {
  MOCK_RFKILL_FAIL=0
  MOCK_WIFI_STATE='disabled'
  MOCK_BLUETOOTH_ACTIVE='inactive'
  MOCK_BLUETOOTH_ENABLED='disabled'
  MOCK_RFKILL_JSON='{
    "rfkilldevices": [
      {"id": 1, "type": "wlan", "device": "laptop-wifi", "soft": "blocked", "hard": "unblocked"},
      {"id": 2, "type": "wlan", "device": "phy0", "soft": "blocked", "hard": "blocked"},
      {"id": 3, "type": "bluetooth", "device": "laptop-bluetooth", "soft": "blocked", "hard": "unblocked"}
    ]
  }'
}

set_fixture
refresh_radio_state
assert_equals '2' "${WIFI_RFKILL_COUNT}" 'all WLAN entries are collected'
assert_equals '1' "${BLUETOOTH_RFKILL_COUNT}" 'Bluetooth RFKill entry is collected'
assert_equals 'disabled' "${WIFI_EFFECTIVE}" 'a hard block is compatible with Wi-Fi lockdown'
assert_equals 'disabled' "${BLUETOOTH_EFFECTIVE}" 'blocked Bluetooth with inactive service is disabled'
assert_equals 'LOCKED DOWN' "$(current_policy_result)" 'complete policy verdict'

set_fixture
MOCK_BLUETOOTH_ACTIVE='active'
refresh_radio_state
assert_equals 'not fully disabled' "${BLUETOOTH_EFFECTIVE}" 'active Bluetooth service fails lockdown'
assert_equals 'NOT LOCKED DOWN' "$(current_policy_result)" 'active Bluetooth policy verdict'

set_fixture
MOCK_RFKILL_JSON='{
  "rfkilldevices": [
    {"id": 3, "type": "bluetooth", "device": "laptop-bluetooth", "soft": "blocked", "hard": "unblocked"}
  ]
}'
refresh_radio_state
assert_equals '0' "${WIFI_RFKILL_COUNT}" 'missing WLAN hardware is detected'
assert_equals 'not fully disabled' "${WIFI_EFFECTIVE}" 'missing WLAN hardware is not assumed secure'
assert_equals 'NOT LOCKED DOWN' "$(current_policy_result)" 'missing WLAN policy verdict'

set_fixture
MOCK_RFKILL_FAIL=1
refresh_radio_state 2>/dev/null
assert_equals 'unknown' "${WIFI_EFFECTIVE}" 'RFKill query failure makes Wi-Fi state unknown'
assert_equals 'STATE UNKNOWN' "$(current_policy_result)" 'RFKill query failure policy verdict'

set_fixture
systemctl() { return 1; }
refresh_radio_state 2>/dev/null
assert_equals 'disabled' "${WIFI_EFFECTIVE}" 'Bluetooth query failure does not invalidate Wi-Fi state'
assert_equals 'unknown' "${BLUETOOTH_EFFECTIVE}" 'Bluetooth query failure is contained to Bluetooth state'

systemctl() {
  case "$*" in
    *ActiveState*) printf '%s\n' "${MOCK_BLUETOOTH_ACTIVE}" ;;
    *UnitFileState*) printf '%s\n' "${MOCK_BLUETOOTH_ENABLED}" ;;
    *) return 1 ;;
  esac
}

set_fixture
command() {
  if [[ "${1:-}" == '-v' && "${2:-}" == 'bluetoothctl' ]]; then
    return 1
  fi
  builtin command "$@"
}
refresh_radio_state
assert_equals 'tool-unavailable' "${BLUETOOTH_CONTROLLER}" 'missing optional bluetoothctl is reported clearly'
assert_equals 'disabled' "${BLUETOOTH_EFFECTIVE}" 'missing controller utility does not invalidate service and RFKill lockdown verification'

printf 'Policy tests passed.\n'
