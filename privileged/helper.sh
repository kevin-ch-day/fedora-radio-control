#!/usr/bin/env bash
# Root-owned installed mutation entry point. This file is never sourced from
# the development checkout after installation.
set -Eeuo pipefail

PATH=/usr/sbin:/usr/bin:/sbin:/bin
umask 077
readonly PATH

readonly RUNTIME_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROTOCOL_VERSION='2'

helper_error() {
  printf 'Error: %s\n' "$*" >&2
}

runtime_file_safe() {
  local path="$1" owner mode
  [[ -f "${path}" && ! -L "${path}" ]] || return 1
  owner="$(stat -c '%u' "${path}")"
  mode="$(stat -c '%a' "${path}")"
  [[ "${owner}" == 0 ]] && (( ((8#${mode}) & 8#022) == 0 ))
}

verify_runtime() {
  local required path owner mode
  [[ -d "${RUNTIME_DIR}" && ! -L "${RUNTIME_DIR}" ]] || return 1
  owner="$(stat -c '%u' "${RUNTIME_DIR}")"
  mode="$(stat -c '%a' "${RUNTIME_DIR}")"
  [[ "${owner}" == 0 ]] && (( ((8#${mode}) & 8#022) == 0 )) || return 1
  for required in common.sh wifi-state.sh bluetooth-state.sh radio-state.sh wifi-control.sh bluetooth-control.sh lockdown.sh VERSION; do
    path="${RUNTIME_DIR}/${required}"
    runtime_file_safe "${path}" || return 1
  done
  [[ "$(<"${RUNTIME_DIR}/VERSION")" == "${PROTOCOL_VERSION}" ]]
}

(( EUID == 0 )) || { helper_error 'This action requires root.'; exit 4; }
verify_runtime || { helper_error 'Installed privileged component is invalid.'; exit 3; }

# All paths below resolve inside the root-owned installed runtime directory.
source "${RUNTIME_DIR}/common.sh"
source "${RUNTIME_DIR}/wifi-state.sh"
source "${RUNTIME_DIR}/bluetooth-state.sh"
source "${RUNTIME_DIR}/radio-state.sh"
source "${RUNTIME_DIR}/wifi-control.sh"
source "${RUNTIME_DIR}/bluetooth-control.sh"
source "${RUNTIME_DIR}/lockdown.sh"

helper_wifi_enable_confirmation() {
  local reply autoconnect_count
  [[ -t 0 && -t 1 ]] || { error 'Wi-Fi enable requires an interactive terminal confirmation.'; return "${EXIT_USAGE}"; }
  if ! autoconnect_count="$(wifi_autoconnect_profile_count)"; then
    error 'Unable to inspect saved Wi-Fi autoconnect profiles. Wi-Fi enable cancelled.'
    return "${EXIT_UNKNOWN}"
  fi
  printf '%s\n' 'WARNING: Enabling Wi-Fi increases radio exposure.' >&2
  if (( autoconnect_count > 0 )); then
    printf 'WARNING: %s saved Wi-Fi profile(s) have autoconnect enabled; names are not displayed.\n' "${autoconnect_count}" >&2
  else
    printf '%s\n' 'Saved Wi-Fi autoconnect profiles: none enabled.' >&2
  fi
  printf '%s' 'Type ENABLE-WIFI to continue: ' >&2
  IFS= read -r reply < /dev/tty || { error 'Wi-Fi enable cancelled.'; return "${EXIT_USAGE}"; }
  [[ "${reply}" == 'ENABLE-WIFI' ]] || { error 'Wi-Fi enable cancelled.'; return "${EXIT_POLICY}"; }
}

(( $# == 1 )) || { helper_error 'Unsupported privileged operation.'; exit 2; }
case "$1" in
  lockdown|lockdown-non-interactive)
    require_commands nmcli rfkill systemctl flock
    with_mutation_lock lockdown_apply
    ;;
  wifi-disable)
    require_commands nmcli rfkill flock
    with_mutation_lock wifi_disable_apply
    ;;
  wifi-enable)
    require_commands nmcli rfkill flock
    helper_wifi_enable_confirmation
    with_mutation_lock wifi_enable_apply
    ;;
  bluetooth-disable)
    require_commands rfkill systemctl flock
    with_mutation_lock bluetooth_disable_apply
    ;;
  *) helper_error 'Unsupported privileged operation.'; exit 2 ;;
esac
