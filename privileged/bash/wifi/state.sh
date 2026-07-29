#!/usr/bin/env bash
# Read-only Wi-Fi state collection.

WIFI_RADIO_STATE='unknown'
WIFI_RFKILL_COUNT=0
WIFI_EFFECTIVE='unknown'
WIFI_ACTIVE_LINK='none'
WIFI_ACTIVE_LINK_DURATION='not connected'
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

collect_wifi_connection_duration() {
  local output line connection_type timestamp now
  WIFI_ACTIVE_LINK='none'
  WIFI_ACTIVE_LINK_DURATION='not connected'
  if ! output="$(LC_ALL=C nmcli --terse --fields TYPE,TIMESTAMP connection show --active 2>/dev/null)"; then
    WIFI_ACTIVE_LINK='unknown'
    WIFI_ACTIVE_LINK_DURATION='unknown (query failed)'
    return 1
  fi
  while IFS= read -r line; do
    IFS=':' read -r connection_type timestamp <<< "${line}"
    [[ "${connection_type}" == 'wifi' || "${connection_type}" == '802-11-wireless' ]] || continue
    WIFI_ACTIVE_LINK='connected'
    if [[ "${timestamp}" =~ ^[0-9]+$ ]]; then
      now="$(date -u +%s)"
      if (( now >= timestamp )); then
        WIFI_ACTIVE_LINK_DURATION="$(format_elapsed_seconds "$(( now - timestamp ))")"
      else
        WIFI_ACTIVE_LINK_DURATION='unknown (timestamp invalid)'
      fi
    else
      WIFI_ACTIVE_LINK_DURATION='unknown (timestamp unavailable)'
    fi
    return 0
  done <<< "${output}"
}

# Return the active Wi-Fi interface without exposing its network name, address,
# or connection profile. Exit 1 means NetworkManager reported no active Wi-Fi
# connection; exit 2 means the query itself could not be completed.
wifi_active_connection_interface() {
  local output line device connection_type state
  if ! output="$(LC_ALL=C nmcli --terse --fields DEVICE,TYPE,STATE device status 2>/dev/null)"; then
    return 2
  fi
  while IFS= read -r line; do
    IFS=':' read -r device connection_type state <<< "${line}"
    if [[ "${connection_type}" == 'wifi' && "${state}" == 'connected' ]]; then
      printf '%s' "${device}"
      return 0
    fi
  done <<< "${output}"
  return 1
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

report_wifi_state() {
  local entry _index _device _soft hard hard_block_present=0
  refresh_radio_state

  ui_heading 'Wi-Fi State'
  ui_label 'NetworkManager radio:' "${WIFI_RADIO_STATE}"
  ui_label 'RFKill devices:' "${WIFI_RFKILL_COUNT}"
  if (( WIFI_RFKILL_COUNT == 0 )); then
    ui_label 'Hardware:' 'NOT DETECTED'
  else
    print_rfkill_entries "${WIFI_RFKILL[@]}"
    for entry in "${WIFI_RFKILL[@]}"; do
      IFS='|' read -r _index _device _soft hard <<< "${entry}"
      [[ "${hard}" == 'blocked' ]] && hard_block_present=1
    done
  fi
  printf '\n'
  if (( hard_block_present )); then
    ui_label 'Hardware constraint:' 'HARDWARE BLOCKED (software cannot remove it)'
  fi
  case "${WIFI_EFFECTIVE}" in
    disabled) ui_label 'Effective state:' 'DISABLED' ;;
    unknown) ui_label 'Effective state:' 'STATE UNKNOWN' ;;
    *) ui_label 'Effective state:' 'NOT FULLY DISABLED' ;;
  esac
  ui_note 'Enable does not select a network; saved profiles may reconnect according to NetworkManager policy.'
}
