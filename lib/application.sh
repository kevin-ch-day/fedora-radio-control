#!/usr/bin/env bash
# Internal command dispatch for the public run.sh entry point.

APPLICATION_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly PRIVILEGED_HELPER='/usr/local/libexec/fedora-radio-control/radio-control-privileged'
readonly PRIVILEGED_RUNTIME_DIR='/usr/local/libexec/fedora-radio-control'
readonly -a PRIVILEGED_RUNTIME_FILES=(
  'radio-control-privileged' 'common.sh' 'wifi-state.sh' 'bluetooth-state.sh'
  'radio-state.sh' 'wifi-control.sh' 'bluetooth-control.sh' 'lockdown.sh' 'VERSION'
)

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
# shellcheck source=../bluetooth/state.sh
source "${APPLICATION_ROOT}/bluetooth/state.sh"
# shellcheck source=radio-state.sh
source "${APPLICATION_ROOT}/lib/radio-state.sh"
# shellcheck source=readiness.sh
source "${APPLICATION_ROOT}/lib/readiness.sh"
# shellcheck source=menu-controller.sh
source "${APPLICATION_ROOT}/lib/menu-controller.sh"

app_usage() {
  cat <<'EOF'
Usage: ./run.sh status
       ./run.sh readiness
       ./run.sh wifi profiles
       ./run.sh wifi disable|enable
       ./run.sh bluetooth disable
       ./run.sh lockdown [--non-interactive]
       ./run.sh help
       ./run.sh --help

Report the current Wi-Fi and Bluetooth lockdown status, or request a verified
control action. Run the application as your normal user; approved control
actions elevate only the installed privileged helper. Running without
arguments opens the interactive menu.
EOF
}

app_unimplemented_action() {
  printf 'This state-changing action is not yet implemented. No changes were made.\n' >&2
  return "${EXIT_USAGE}"
}

privileged_component_status() {
  local path owner mode expected_version installed_version required
  [[ -d "${PRIVILEGED_RUNTIME_DIR}" && ! -L "${PRIVILEGED_RUNTIME_DIR}" ]] || { printf 'MISSING'; return; }
  [[ -x "${PRIVILEGED_HELPER}" && ! -L "${PRIVILEGED_HELPER}" && -f "${PRIVILEGED_HELPER}" ]] || { printf 'MISSING'; return; }
  for path in "${PRIVILEGED_RUNTIME_DIR}"; do
    owner="$(/usr/bin/stat -c '%u' "${path}" 2>/dev/null || true)"
    mode="$(/usr/bin/stat -c '%a' "${path}" 2>/dev/null || true)"
    [[ "${owner}" == 0 && "${mode}" =~ ^[0-7]+$ ]] && (( ((8#${mode}) & 8#022) == 0 )) || { printf 'INVALID'; return; }
  done
  for required in "${PRIVILEGED_RUNTIME_FILES[@]}"; do
    path="${PRIVILEGED_RUNTIME_DIR}/${required}"
    [[ -f "${path}" && ! -L "${path}" ]] || { printf 'INVALID'; return; }
    owner="$(/usr/bin/stat -c '%u' "${path}" 2>/dev/null || true)"
    mode="$(/usr/bin/stat -c '%a' "${path}" 2>/dev/null || true)"
    [[ "${owner}" == 0 && "${mode}" =~ ^[0-7]+$ ]] && (( ((8#${mode}) & 8#022) == 0 )) || { printf 'INVALID'; return; }
  done
  expected_version="$(<"${APPLICATION_ROOT}/VERSION")"
  installed_version="$(<"${PRIVILEGED_RUNTIME_DIR}/VERSION")"
  [[ "${installed_version}" == "${expected_version}" ]] || { printf 'VERSION MISMATCH'; return; }
  printf 'INSTALLED'
}

delegate_privileged_action() {
  local operation="$1" status
  status="$(privileged_component_status)"
  case "${status}" in
    INSTALLED)
      if (( EUID == 0 )); then
        "${PRIVILEGED_HELPER}" "${operation}"
      else
        require_commands sudo || return $?
        sudo -- "${PRIVILEGED_HELPER}" "${operation}"
      fi
      ;;
    MISSING)
      error $'The privileged Fedora Radio Control component is not installed.\n\nInstall the reviewed privileged component with:\n\n  sudo ./install.sh'
      return "${EXIT_UNKNOWN}"
      ;;
    'VERSION MISMATCH')
      error 'The privileged Fedora Radio Control component version does not match this checkout. Run: sudo ./install.sh'
      return "${EXIT_UNKNOWN}"
      ;;
    *)
      error 'The privileged Fedora Radio Control component is invalid. Run: sudo ./install.sh --verify'
      return "${EXIT_UNKNOWN}"
      ;;
  esac
}

app_lockdown() {
  delegate_privileged_action "${1:-lockdown}"
}

app_wifi_disable() {
  delegate_privileged_action 'wifi-disable'
}

app_wifi_enable() {
  delegate_privileged_action 'wifi-enable'
}

app_bluetooth_disable() {
  delegate_privileged_action 'bluetooth-disable'
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
      if (( EUID == 0 )); then
        error $'Do not run the interactive application as root.\n\nStart it as your normal user:\n\n  ./run.sh\n\nThe application requests privilege only for approved radio changes.'
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
      if [[ "${2:-}" == '--non-interactive' ]]; then
        app_lockdown 'lockdown-non-interactive'
      else
        app_lockdown 'lockdown'
      fi
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
