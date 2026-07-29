#!/usr/bin/env bash
# Mocked VPN state test. No system command below reaches the host.
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

source "${REPO_DIR}/privileged/bash/lib/common.sh"
source "${REPO_DIR}/privileged/bash/vpn/state.sh"

MOCK_NMCLI_OUTPUT=''
MOCK_NMCLI_FAIL=0

nmcli() {
  (( MOCK_NMCLI_FAIL == 0 )) || return 1
  printf '%s\n' "${MOCK_NMCLI_OUTPUT}"
}

date() {
  [[ "$*" == '-u +%s' ]] && printf '%s\n' '4561'
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

MOCK_NMCLI_OUTPUT=$'vpn:1000\nwireguard:900\nethernet:800'
collect_vpn_state || fail 'active VPN query should succeed'
[[ "${VPN_STATE}" == 'active' ]] || fail 'VPN was not reported active'
[[ "${VPN_ACTIVE_COUNT}" -eq 2 ]] || fail 'VPN count was not sanitized correctly'
[[ "${VPN_CONNECTION_DURATION}" == '1h 01m' ]] || fail 'oldest active VPN duration was not calculated'

MOCK_NMCLI_OUTPUT='ethernet:800'
collect_vpn_state || fail 'inactive VPN query should succeed'
[[ "${VPN_STATE}" == 'inactive' ]] || fail 'inactive VPN state was not reported'
[[ "${VPN_CONNECTION_DURATION}" == 'not connected' ]] || fail 'inactive VPN duration was not reset'

MOCK_NMCLI_FAIL=1
if collect_vpn_state; then
  fail 'failed VPN query should not succeed'
fi
[[ "${VPN_STATE}" == 'unknown' ]] || fail 'failed VPN query was not reported unknown'

printf 'VPN state tests passed.\n'
