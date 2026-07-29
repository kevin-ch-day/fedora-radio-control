#!/usr/bin/env bash
# Mocked Wi-Fi control test. No system command below reaches the host.
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT

source "${REPO_DIR}/privileged/bash/lib/common.sh"
source "${REPO_DIR}/privileged/bash/wifi/state.sh"
source "${REPO_DIR}/privileged/bash/bluetooth/state.sh"
source "${REPO_DIR}/privileged/bash/lib/rfkill.sh"
source "${REPO_DIR}/privileged/bash/lib/radio-policy.sh"
APPLICATION_ROOT="${TEST_DIR}"
source "${REPO_DIR}/privileged/bash/wifi/control.sh"

MOCK_WIFI='enabled'
MOCK_WIFI_BLOCK='unblocked'

nmcli() {
  case "$*" in
    '--terse --fields WIFI general status') printf '%s\n' "${MOCK_WIFI}" ;;
    '--terse --fields TYPE,AUTOCONNECT connection show') printf '%s\n' 'wifi:yes' 'ethernet:yes' 'wifi:no' ;;
    'radio wifi off') MOCK_WIFI='disabled' ;;
    *) return 1 ;;
  esac
}

rfkill() {
  case "$*" in
    --json)
      printf '{"rfkilldevices":[{"id":1,"type":"wlan","device":"wifi0","soft":"%s","hard":"unblocked"},{"id":2,"type":"bluetooth","device":"bt0","soft":"blocked","hard":"unblocked"}]}' "${MOCK_WIFI_BLOCK}"
      ;;
    'block wlan') MOCK_WIFI_BLOCK='blocked' ;;
    *) return 1 ;;
  esac
}

# Deliberately fail unrelated Bluetooth collection: Wi-Fi verification must
# still succeed when its own NetworkManager and RFKill evidence is complete.
systemctl() { return 1; }
bluetoothctl() { return 1; }

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ "$(wifi_autoconnect_profile_count)" == 1 ]] || fail 'Wi-Fi autoconnect count did not omit non-Wi-Fi and disabled profiles'
wifi_disable_apply >/dev/null 2>/dev/null || fail 'Wi-Fi disable should verify despite unrelated Bluetooth query failure'
[[ "${MOCK_WIFI}" == 'disabled' ]] || fail 'NetworkManager Wi-Fi was not disabled'
[[ "${MOCK_WIFI_BLOCK}" == 'blocked' ]] || fail 'WLAN was not RFKill-blocked'
[[ -L "${ACTION_LOG_DIRECTORY}/latest.log" ]] || fail 'latest log link was not created'
grep -Fq 'final_result=DISABLED' "${WIFI_CONTROL_LOG_FILE}" || fail 'verified result was not logged'
grep -Fq 'log_schema_version=1' "${WIFI_CONTROL_LOG_FILE}" || fail 'log schema version was not recorded'
grep -Fq 'event=command_result' "${WIFI_CONTROL_LOG_FILE}" || fail 'command outcome event was not logged'
grep -Fq 'exit_code=0' "${WIFI_CONTROL_LOG_FILE}" || fail 'verified action exit code was not logged'

printf 'Wi-Fi control tests passed.\n'
