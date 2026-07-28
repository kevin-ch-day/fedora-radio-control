#!/usr/bin/env bash
# Read-only DEF CON radio-exposure readiness checks. No profiles or firewall
# configuration are changed, and network names are intentionally omitted.

readiness_active_wifi_interface() {
  local output line device type state
  if ! output="$(nmcli --terse --fields DEVICE,TYPE,STATE device status 2>/dev/null)"; then
    return 2
  fi
  while IFS= read -r line; do
    IFS=':' read -r device type state <<< "${line}"
    if [[ "${type}" == 'wifi' && "${state}" == 'connected' ]]; then
      printf '%s' "${device}"
      return 0
    fi
  done <<< "${output}"
  return 1
}

readiness_firewalld_state() {
  if ! command -v firewall-cmd >/dev/null 2>&1; then
    printf 'UNKNOWN'
    return
  fi
  if firewall-cmd --state >/dev/null 2>&1; then
    printf 'PASS'
  else
    printf 'FAIL'
  fi
}

readiness_wifi_autoconnect_count() {
  local output line connection_type autoconnect count=0
  if ! output="$(nmcli --terse --fields TYPE,AUTOCONNECT connection show 2>/dev/null)"; then
    return 2
  fi
  while IFS= read -r line; do
    IFS=':' read -r connection_type autoconnect <<< "${line}"
    if [[ "${connection_type}" == 'wifi' || "${connection_type}" == '802-11-wireless' ]] && [[ "${autoconnect}" == 'yes' ]]; then
      ((count += 1))
    fi
  done <<< "${output}"
  printf '%s' "${count}"
}

readiness_vpn_state() {
  local output line connection_type _device
  if ! output="$(nmcli --terse --fields TYPE,DEVICE connection show --active 2>/dev/null)"; then
    return 2
  fi
  while IFS= read -r line; do
    IFS=':' read -r connection_type _device <<< "${line}"
    case "${connection_type}" in
      vpn|wireguard|tun|ppp)
        printf 'INFORMATIONAL (active)'
        return 0
        ;;
    esac
  done <<< "${output}"
  printf 'INFORMATIONAL (none detected)'
}

readiness_wireless_zone() {
  local interface="$1"
  local zone
  if [[ -z "${interface}" ]]; then
    printf 'NOT APPLICABLE'
    return
  fi
  if ! command -v firewall-cmd >/dev/null 2>&1; then
    printf 'UNKNOWN (firewalld unavailable)'
    return
  fi
  if ! zone="$(firewall-cmd --get-zone-of-interface="${interface}" 2>/dev/null)" || [[ -z "${zone}" || "${zone}" == 'no zone' ]]; then
    if ! zone="$(firewall-cmd --get-default-zone 2>/dev/null)"; then
      printf 'UNKNOWN (zone query failed)'
      return
    fi
    printf 'REVIEW (%s, default)' "${zone}"
    return
  fi
  case "${zone}" in
    trusted|home|work|internal)
      printf 'FAIL (%s is permissive for conference Wi-Fi)' "${zone}"
      ;;
    public|external|block|drop)
      printf 'PASS (%s)' "${zone}"
      ;;
    *)
      printf 'REVIEW (%s)' "${zone}"
      ;;
  esac
}

report_wifi_profile_autoconnect() {
  local count
  if ! count="$(readiness_wifi_autoconnect_count)"; then
    ui_label 'Wi-Fi autoconnect profiles:' 'UNKNOWN (query failed)'
    return "${EXIT_UNKNOWN}"
  fi
  if (( count == 0 )); then
    ui_label 'Wi-Fi autoconnect profiles:' 'NONE'
  else
    ui_label 'Wi-Fi autoconnect profiles:' "REVIEW (${count} enabled; names omitted)"
  fi
}

report_readiness() {
  local policy wifi_interface firewall_state radio_verdict bluetooth_service bluetooth_exposure wifi_autoconnect vpn_state wireless_zone
  local wifi_interface_known=1 wifi_autoconnect_known=1 readiness_unknown=0 readiness_failed=0 wifi_interface_status
  refresh_radio_state
  policy="$(current_policy_result)"
  case "${policy}" in
    'LOCKED DOWN') radio_verdict='PASS' ;;
    'STATE UNKNOWN') radio_verdict='UNKNOWN' ;;
    *) radio_verdict='FAIL' ;;
  esac
  [[ "${BLUETOOTH_SERVICE_ACTIVE}" == 'inactive' ]] && bluetooth_service='PASS' || bluetooth_service='FAIL'
  case "${BLUETOOTH_CONTROLLER}" in
    unavailable) bluetooth_exposure='NOT APPLICABLE' ;;
    tool-unavailable) bluetooth_exposure='REVIEW (bluetoothctl unavailable)' ;;
    unknown) bluetooth_exposure='UNKNOWN' ;;
    available)
      if [[ "${BLUETOOTH_POWERED}" == 'no' && "${BLUETOOTH_DISCOVERABLE}" == 'no' && "${BLUETOOTH_PAIRABLE}" == 'no' ]]; then
        bluetooth_exposure='PASS'
      else
        bluetooth_exposure='FAIL'
      fi
      ;;
  esac
  if wifi_interface="$(readiness_active_wifi_interface)"; then
    :
  else
    wifi_interface_status=$?
    wifi_interface=''
    # Exit 1 means the query succeeded and no wireless connection is active.
    [[ "${wifi_interface_status}" -eq 1 ]] || wifi_interface_known=0
  fi
  firewall_state="$(readiness_firewalld_state)"
  if ! wifi_autoconnect="$(readiness_wifi_autoconnect_count)"; then
    wifi_autoconnect=''
    wifi_autoconnect_known=0
  fi
  vpn_state="$(readiness_vpn_state || printf 'UNKNOWN')"
  wireless_zone="$(readiness_wireless_zone "${wifi_interface}")"

  ui_heading 'DEF CON Readiness'
  ui_label 'Radio lockdown:' "${radio_verdict}"
  ui_label 'Bluetooth service:' "${bluetooth_service}"
  ui_label 'Bluetooth exposure:' "${bluetooth_exposure}"
  if (( ! wifi_interface_known )); then
    ui_label 'Active wireless link:' 'UNKNOWN (query failed)'
    ui_label 'Wireless zone:' 'UNKNOWN (interface not verified)'
    readiness_unknown=1
  elif [[ -n "${wifi_interface}" ]]; then
    ui_label 'Active wireless link:' "REVIEW (${wifi_interface})"
    ui_label 'Wireless zone:' "${wireless_zone}"
    [[ "${wireless_zone}" == FAIL* ]] && readiness_failed=1
    [[ "${wireless_zone}" == UNKNOWN* ]] && readiness_unknown=1
  else
    ui_label 'Active wireless link:' 'NONE'
    ui_label 'Wireless zone:' 'NOT APPLICABLE'
  fi
  if (( wifi_autoconnect_known )); then
    if (( wifi_autoconnect == 0 )); then
      ui_label 'Wi-Fi autoconnect:' 'PASS (none enabled)'
    else
      ui_label 'Wi-Fi autoconnect:' "REVIEW (${wifi_autoconnect} enabled; names omitted)"
    fi
  else
    ui_label 'Wi-Fi autoconnect:' 'UNKNOWN (query failed)'
    readiness_unknown=1
  fi
  ui_label 'Firewall service:' "${firewall_state}"
  ui_label 'VPN detected:' "${vpn_state}"
  ui_label 'Unexpected adapters:' 'REVIEW (baseline not recorded)'
  printf '\n'
  [[ "${radio_verdict}" == 'UNKNOWN' || "${bluetooth_exposure}" == 'UNKNOWN' || "${firewall_state}" == 'UNKNOWN' || "${vpn_state}" == 'UNKNOWN' ]] && readiness_unknown=1
  [[ "${radio_verdict}" == 'FAIL' || "${bluetooth_service}" == 'FAIL' || "${bluetooth_exposure}" == 'FAIL' || "${firewall_state}" == 'FAIL' ]] && readiness_failed=1
  if (( readiness_unknown )); then
    ui_label 'Overall:' 'STATE UNKNOWN'
    return "${EXIT_UNKNOWN}"
  fi
  if (( readiness_failed )); then
    ui_label 'Overall:' 'NOT READY'
    return "${EXIT_POLICY}"
  fi
  if [[ "${radio_verdict}" == 'PASS' && "${bluetooth_service}" == 'PASS' ]]; then
    ui_label 'Overall:' 'READY WITH REVIEW ITEMS'
    return 0
  fi
  ui_label 'Overall:' 'NOT READY'
  return 1
}
