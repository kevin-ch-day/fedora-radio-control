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
