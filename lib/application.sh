#!/usr/bin/env bash
# Internal command dispatch for the public run.sh entry point.

APPLICATION_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck source=common.sh
source "${APPLICATION_ROOT}/lib/common.sh"
# shellcheck source=display.sh
source "${APPLICATION_ROOT}/lib/display.sh"
# shellcheck source=prompts.sh
source "${APPLICATION_ROOT}/lib/prompts.sh"
# shellcheck source=menu.sh
source "${APPLICATION_ROOT}/lib/menu.sh"
# shellcheck source=../wifi/state.sh
source "${APPLICATION_ROOT}/wifi/state.sh"
# shellcheck source=../wifi/control.sh
source "${APPLICATION_ROOT}/wifi/control.sh"
# shellcheck source=../bluetooth/state.sh
source "${APPLICATION_ROOT}/bluetooth/state.sh"
# shellcheck source=../bluetooth/control.sh
source "${APPLICATION_ROOT}/bluetooth/control.sh"
# shellcheck source=radio-state.sh
source "${APPLICATION_ROOT}/lib/radio-state.sh"
# shellcheck source=readiness.sh
source "${APPLICATION_ROOT}/lib/readiness.sh"
# shellcheck source=lockdown.sh
source "${APPLICATION_ROOT}/lib/lockdown.sh"
# shellcheck source=menu-controller.sh
source "${APPLICATION_ROOT}/lib/menu-controller.sh"

app_usage() {
  cat <<'EOF'
Usage: ./run.sh status
       ./run.sh readiness
       ./run.sh wifi profiles
       sudo ./run.sh wifi disable|enable
       sudo ./run.sh bluetooth disable
       sudo ./run.sh lockdown [--non-interactive]
       ./run.sh help
       ./run.sh --help

Report the current Wi-Fi and Bluetooth lockdown status, or run a verified
control action. State-changing actions require root. Running without
arguments opens the interactive menu.
EOF
}

app_unimplemented_action() {
  printf 'This state-changing action is not yet implemented. No changes were made.\n' >&2
  return "${EXIT_USAGE}"
}

app_lockdown() {
  require_fedora
  require_commands nmcli rfkill systemctl
  require_root 'lockdown'
  lockdown_apply
}

app_wifi_disable() {
  require_fedora
  require_commands nmcli rfkill
  require_root 'wifi disable'
  wifi_disable_apply
}

app_wifi_enable() {
  require_fedora
  require_commands nmcli rfkill
  require_root 'wifi enable'
  wifi_confirm_enable
  wifi_enable_apply
}

app_bluetooth_disable() {
  require_fedora
  require_commands rfkill systemctl
  require_root 'bluetooth disable'
  bluetooth_disable_apply
}

app_main() {
  local command="${1:-}"

  ui_init

  case "${command}" in
    '')
      if (( $# != 0 )); then
        app_usage >&2
        return "${EXIT_USAGE}"
      fi
      require_fedora
      require_commands nmcli rfkill systemctl
      run_menu
      ;;
    status)
      if (( $# != 1 )); then
        app_usage >&2
        return "${EXIT_USAGE}"
      fi
      require_fedora
      require_commands nmcli rfkill systemctl
      report_status
      ;;
    readiness)
      if (( $# != 1 )); then
        app_usage >&2
        return "${EXIT_USAGE}"
      fi
      require_fedora
      require_commands nmcli rfkill systemctl
      report_readiness
      ;;
    lockdown)
      if (( $# != 1 )) && { (( $# != 2 )) || [[ "${2:-}" != '--non-interactive' ]]; }; then
        app_usage >&2
        return "${EXIT_USAGE}"
      fi
      app_lockdown
      ;;
    wifi|bluetooth)
      if [[ "${command}" == 'wifi' && "${2:-}" == 'profiles' && $# -eq 2 ]]; then
        require_fedora
        require_commands nmcli
        report_wifi_profile_autoconnect
        return $?
      fi
      if (( $# != 2 )) || [[ "${2}" != 'enable' && "${2}" != 'disable' ]]; then
        app_usage >&2
        return "${EXIT_USAGE}"
      fi
      if [[ "${command}" == 'wifi' && "${2}" == 'disable' ]]; then
        app_wifi_disable
      elif [[ "${command}" == 'wifi' && "${2}" == 'enable' ]]; then
        app_wifi_enable
      elif [[ "${command}" == 'bluetooth' && "${2}" == 'disable' ]]; then
        app_bluetooth_disable
      else
        app_unimplemented_action
      fi
      ;;
    help|--help)
      if (( $# != 1 )); then
        app_usage >&2
        return "${EXIT_USAGE}"
      fi
      app_usage
      ;;
    *)
      error "Unsupported command: ${command}"
      app_usage >&2
      return "${EXIT_USAGE}"
      ;;
  esac
}
