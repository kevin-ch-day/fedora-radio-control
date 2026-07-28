#!/usr/bin/env bash
# Interactive menu flow used by the internal application dispatcher.

show_main_menu() {
  local policy selection component_status blocker hardware_note autoconnect_count autoconnect_status
  {
    refresh_radio_state
    policy="$(current_policy_result)"
    blocker="$(policy_reason)"
    component_status="$(privileged_component_status)"
    hardware_note='not present'
    if rfkill_hardware_block_present "${WIFI_RFKILL[@]}"; then
      hardware_note='present — lockdown compatible'
    fi
    if autoconnect_count="$(readiness_wifi_autoconnect_count)"; then
      if (( autoconnect_count == 0 )); then
        autoconnect_status='none enabled'
      else
        autoconnect_status="REVIEW (${autoconnect_count} enabled; names omitted)"
      fi
    else
      autoconnect_status='UNKNOWN (query failed)'
    fi
    ui_heading 'Fedora Radio Control'
    ui_note 'DEF CON radio exposure posture — live state'
    printf '\n  Policy:                %s\n' "$(ui_result "${policy}")"
    [[ "${policy}" == 'LOCKED DOWN' ]] || ui_label 'Primary blocker:' "${blocker}"
    ui_rule
    printf '%s\n' 'Wi-Fi'
    ui_label 'Radio:' "${WIFI_RADIO_STATE}"
    ui_label 'RFKill:' "$(rfkill_summary "${WIFI_RFKILL[@]}")"
    ui_label 'Hardware block:' "${hardware_note}"
    ui_label 'Autoconnect profiles:' "${autoconnect_status}"
    if rfkill_hardware_block_present "${WIFI_RFKILL[@]}"; then
      ui_note '  Hardware block strengthens lockdown but prevents software enablement.'
    fi
    printf '\n%s\n' 'Bluetooth'
    ui_label 'Service:' "${BLUETOOTH_SERVICE_ACTIVE}"
    ui_label 'RFKill:' "$(rfkill_summary "${BLUETOOTH_RFKILL[@]}")"
    ui_label 'Controller:' "${BLUETOOTH_CONTROLLER}"
    printf '\n%s\n' 'System'
    if [[ "${component_status}" == 'INSTALLED' ]]; then
      ui_label 'Privileged component:' 'INSTALLED AND VERIFIED'
    else
      ui_label 'Privileged component:' "${component_status}"
    fi
    ui_rule
    printf '%s\n' '[1] Show detailed radio status'
    printf '%s\n' '[2] Apply full radio lockdown'
    printf '%s\n' '[3] Wi-Fi controls'
    printf '%s\n' '[4] Bluetooth controls'
    printf '%s\n' '[5] DEF CON readiness check'
    printf '%s\n' '[6] Show recent activity'
    printf '%s\n' '[7] Clear screen'
    printf '%s\n' '[0] Exit'
    ui_rule
  } >&2

  selection="$(menu_read_selection 0 7)" || return $?
  printf '%s' "${selection}"
}

show_recent_activity() {
  local latest_log='/var/log/fedora-radio-control/latest.log'
  if (( EUID != 0 )); then
    ui_note 'Action logs are protected. Review them with: sudo tail -n 40 /var/log/fedora-radio-control/latest.log'
  elif [[ -L "${latest_log}" && -r "${latest_log}" ]]; then
    tail -n 40 "${latest_log}"
  else
    ui_note 'No state-changing activity has been logged yet.'
  fi
}

show_wifi_menu() {
  {
    refresh_radio_state
    ui_heading 'Wi-Fi Controls'
    ui_label 'Current state:' "${WIFI_EFFECTIVE^^}"
    ui_label 'NetworkManager:' "${WIFI_RADIO_STATE}"
    ui_label 'RFKill:' "$(rfkill_summary "${WIFI_RFKILL[@]}")"
    if rfkill_hardware_block_present "${WIFI_RFKILL[@]}"; then
      ui_label 'Hardware constraint:' 'HARDWARE BLOCKED'
    fi
    printf '%s\n' '------------------------------------------------------------'
    printf '%s\n' '[1] Show detailed Wi-Fi state'
    printf '%s\n' '[2] Review saved profile autoconnect status'
    printf '%s\n' '[3] Disable and RFKill-block Wi-Fi'
    printf '%s\n' '[4] Enable Wi-Fi radio (explicit confirmation required)'
    printf '%s\n' '[0] Back'
    printf '%s\n' '------------------------------------------------------------'
  } >&2
  menu_read_selection 0 4
}

show_bluetooth_menu() {
  {
    refresh_radio_state
    ui_heading 'Bluetooth Controls'
    ui_label 'Current state:' "${BLUETOOTH_EFFECTIVE^^}"
    ui_label 'Service:' "${BLUETOOTH_SERVICE_ACTIVE}"
    ui_label 'RFKill:' "$(rfkill_summary "${BLUETOOTH_RFKILL[@]}")"
    ui_label 'Controller:' "${BLUETOOTH_CONTROLLER}"
    printf '%s\n' '------------------------------------------------------------'
    printf '%s\n' '[1] Show detailed Bluetooth state'
    printf '%s\n' '[2] Disable and RFKill-block Bluetooth'
    printf '%s\n' '[3] Enable Bluetooth [Not yet implemented]'
    printf '%s\n' '[0] Back'
    printf '%s\n' '------------------------------------------------------------'
  } >&2
  menu_read_selection 0 3
}

run_wifi_menu() {
  local selection menu_status
  while true; do
    selection="$(show_wifi_menu)" || {
      menu_status=$?
      if [[ "${menu_status}" -eq 1 ]]; then
        printf 'Invalid selection.\n' >&2
        continue
      fi
      [[ "${menu_status}" -eq 2 ]] && return 0
      return "${menu_status}"
    }
    case "${selection}" in
      0) return 0 ;;
      1) report_wifi_state || true; ui_wait_for_return ;;
      2) report_wifi_profile_autoconnect || true; ui_wait_for_return ;;
      3) app_wifi_disable || true; ui_wait_for_return ;;
      4) app_wifi_enable || true; ui_wait_for_return ;;
    esac
  done
}

run_bluetooth_menu() {
  local selection menu_status
  while true; do
    selection="$(show_bluetooth_menu)" || {
      menu_status=$?
      if [[ "${menu_status}" -eq 1 ]]; then
        printf 'Invalid selection.\n' >&2
        continue
      fi
      [[ "${menu_status}" -eq 2 ]] && return 0
      return "${menu_status}"
    }
    case "${selection}" in
      0) return 0 ;;
      1) report_bluetooth_state || true; ui_wait_for_return ;;
      2) app_bluetooth_disable || true; ui_wait_for_return ;;
      3) app_unimplemented_action || true; ui_wait_for_return ;;
    esac
  done
}

run_menu() {
  local selection menu_status
  trap 'printf "\nMenu cancelled. No changes were made.\n" >&2; exit 130' INT
  while true; do
    selection="$(show_main_menu)" || {
      menu_status=$?
      if [[ "${menu_status}" -eq 1 ]]; then
        printf 'Invalid selection. Please choose a numbered option.\n' >&2
        continue
      fi
      if [[ "${menu_status}" -eq 2 ]]; then
        printf '\nInput closed. Exiting menu without changes.\n' >&2
        return 0
      fi
      return "${menu_status}"
    }
    case "${selection}" in
      0) return 0 ;;
      1) report_status || true; ui_wait_for_return ;;
      2) app_lockdown || true; ui_wait_for_return ;;
      3) run_wifi_menu ;;
      4) run_bluetooth_menu ;;
      5) report_readiness || true; ui_wait_for_return ;;
      6) show_recent_activity; ui_wait_for_return ;;
      7) ui_clear_screen ;;
      *) printf 'Invalid selection. Please choose a numbered option.\n' >&2 ;;
    esac
  done
}
