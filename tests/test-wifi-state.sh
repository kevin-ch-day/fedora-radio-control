#!/usr/bin/env bash
# Mocked Wi-Fi telemetry test. No system command below reaches the host.
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

source "${REPO_DIR}/privileged/bash/lib/common.sh"
source "${REPO_DIR}/privileged/bash/wifi/state.sh"

MOCK_ACTIVE_CONNECTIONS=''
MOCK_DEVICE_STATUS=''
MOCK_PROFILES=''
MOCK_NMCLI_FAIL=0

nmcli() {
  (( MOCK_NMCLI_FAIL == 0 )) || return 1
  case "$*" in
    '--terse --fields TYPE,TIMESTAMP connection show --active') printf '%s\n' "${MOCK_ACTIVE_CONNECTIONS}" ;;
    '--terse --fields DEVICE,TYPE,STATE device status') printf '%s\n' "${MOCK_DEVICE_STATUS}" ;;
    '--terse --fields TYPE,AUTOCONNECT connection show') printf '%s\n' "${MOCK_PROFILES}" ;;
    *) return 1 ;;
  esac
}

date() {
  [[ "$*" == '-u +%s' ]] && printf '%s\n' '4561'
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

MOCK_ACTIVE_CONNECTIONS=$'wifi:900\nwireguard:1000'
MOCK_DEVICE_STATUS=$'wlp0s20f3:wifi:connected\nenp0s31f6:ethernet:connected'
MOCK_PROFILES=$'wifi:yes\n802-11-wireless:no\nethernet:yes'

collect_wifi_connection_duration || fail 'active Wi-Fi duration query should succeed'
[[ "${WIFI_ACTIVE_LINK}" == 'connected' ]] || fail 'active Wi-Fi link was not reported'
[[ "${WIFI_ACTIVE_LINK_DURATION}" == '1h 01m' ]] || fail 'Wi-Fi duration was not calculated'
[[ "$(wifi_active_connection_interface)" == 'wlp0s20f3' ]] || fail 'Wi-Fi interface was not reported'
[[ "$(wifi_autoconnect_profile_count)" == 1 ]] || fail 'autoconnect count included an ineligible profile'

MOCK_ACTIVE_CONNECTIONS='ethernet:1000'
MOCK_DEVICE_STATUS='enp0s31f6:ethernet:connected'
MOCK_PROFILES=$'wifi:no\n802-11-wireless:no'
collect_wifi_connection_duration || fail 'inactive Wi-Fi duration query should succeed'
[[ "${WIFI_ACTIVE_LINK}" == 'none' ]] || fail 'inactive Wi-Fi link was not reset'
[[ "${WIFI_ACTIVE_LINK_DURATION}" == 'not connected' ]] || fail 'inactive Wi-Fi duration was not reset'
if wifi_active_connection_interface >/dev/null; then
  fail 'inactive Wi-Fi interface query should return no connection'
else
  [[ "$?" -eq 1 ]] || fail 'inactive Wi-Fi interface query returned the wrong status'
fi
[[ "$(wifi_autoconnect_profile_count)" == 0 ]] || fail 'disabled profiles were counted'

MOCK_NMCLI_FAIL=1
if collect_wifi_connection_duration; then
  fail 'failed Wi-Fi duration query should not succeed'
fi
[[ "${WIFI_ACTIVE_LINK}" == 'unknown' ]] || fail 'failed Wi-Fi duration query was not reported unknown'
if wifi_active_connection_interface >/dev/null; then
  fail 'failed Wi-Fi interface query should not succeed'
else
  [[ "$?" -eq 2 ]] || fail 'failed Wi-Fi interface query returned the wrong status'
fi
if wifi_autoconnect_profile_count >/dev/null; then
  fail 'failed Wi-Fi profile query should not succeed'
fi

printf 'Wi-Fi state tests passed.\n'
