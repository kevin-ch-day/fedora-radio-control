#!/usr/bin/env bash
# Read-only Wi-Fi state collection.

WIFI_RADIO_STATE='unknown'
WIFI_RFKILL_COUNT=0
WIFI_EFFECTIVE='unknown'
declare -a WIFI_RFKILL=()

collect_wifi_state() {
  if ! WIFI_RADIO_STATE="$(nmcli --terse --fields WIFI general status 2>/dev/null)"; then
    error 'Unable to query the NetworkManager Wi-Fi radio state.'
    WIFI_RADIO_STATE='unknown'
    mark_query_failure
    return
  fi
  WIFI_RADIO_STATE="${WIFI_RADIO_STATE//$'\n'/}"
  case "${WIFI_RADIO_STATE}" in
    enabled|disabled) ;;
    *)
      error 'NetworkManager returned an unrecognized Wi-Fi radio state.'
      WIFI_RADIO_STATE='unknown'
      mark_query_failure
      ;;
  esac
}

# Count saved Wi-Fi profiles that NetworkManager may reconnect automatically.
# Profile names are deliberately omitted because they frequently disclose SSIDs,
# locations, or organizations.  LC_ALL=C makes the parsed machine output stable
# even when the interactive shell uses a translated locale.
wifi_autoconnect_profile_count() {
  local output line connection_type autoconnect count=0
  if ! output="$(LC_ALL=C nmcli --terse --fields TYPE,AUTOCONNECT connection show 2>/dev/null)"; then
    return 1
  fi
  while IFS= read -r line; do
    IFS=':' read -r connection_type autoconnect <<< "${line}"
    if [[ "${connection_type}" == 'wifi' || "${connection_type}" == '802-11-wireless' ]] && [[ "${autoconnect}" == 'yes' ]]; then
      ((count += 1))
    fi
  done <<< "${output}"
  printf '%s' "${count}"
}
