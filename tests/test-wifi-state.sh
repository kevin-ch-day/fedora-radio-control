#!/usr/bin/env bash
# Mocked helper-only Wi-Fi profile test. No system command reaches the host.
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

source "${REPO_DIR}/privileged/bash/lib/common.sh"
source "${REPO_DIR}/privileged/bash/wifi/state.sh"

MOCK_PROFILES=''
MOCK_NMCLI_FAIL=0

nmcli() {
  (( MOCK_NMCLI_FAIL == 0 )) || return 1
  [[ "$*" == '--terse --fields TYPE,AUTOCONNECT connection show' ]] || return 1
  printf '%s\n' "${MOCK_PROFILES}"
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

MOCK_PROFILES=$'wifi:yes\n802-11-wireless:no\nethernet:yes'
[[ "$(wifi_autoconnect_profile_count)" == 1 ]] || fail 'autoconnect count included an ineligible profile'

MOCK_PROFILES=$'wifi:no\n802-11-wireless:no'
[[ "$(wifi_autoconnect_profile_count)" == 0 ]] || fail 'disabled profiles were counted'

MOCK_NMCLI_FAIL=1
if wifi_autoconnect_profile_count >/dev/null; then
  fail 'failed Wi-Fi profile query should not succeed'
fi

printf 'Wi-Fi state tests passed.\n'
