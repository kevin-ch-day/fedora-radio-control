#!/usr/bin/env bash
# Interactive menu flow used by the internal application dispatcher.

show_main_menu() {
  local policy selection
  {
    ui_clear_screen
    refresh_radio_state
    policy="$(current_policy_result)"
    ui_heading 'Fedora Radio Control'
    ui_note 'DEF CON radio exposure posture — live, read-only state'
    printf '\n  Policy:                %s\n' "$(ui_result "${policy}")"
    ui_rule
    printf '  Wi-Fi      NetworkManager: %-10s RFKill: %-12s Hardware block: %s\n' \
      "${WIFI_RADIO_STATE}" "$(rfkill_summary "${WIFI_RFKILL[@]}")" \
      "$(rfkill_hardware_block_present "${WIFI_RFKILL[@]}" && printf present || printf not-present)"
    if rfkill_hardware_block_present "${WIFI_RFKILL[@]}"; then
      ui_note '  Wi-Fi hardware block prevents software from enabling that adapter.'
    fi
    printf '  Bluetooth Service: %-14s RFKill: %-12s Controller: %s\n' \
      "${BLUETOOTH_SERVICE_ACTIVE}" "$(rfkill_summary "${BLUETOOTH_RFKILL[@]}")" "${BLUETOOTH_CONTROLLER}"
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
  if [[ -L "${APPLICATION_ROOT}/logs/latest.log" && -r "${APPLICATION_ROOT}/logs/latest.log" ]]; then
    tail -n 40 "${APPLICATION_ROOT}/logs/latest.log"
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
