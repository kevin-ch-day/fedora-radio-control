#!/usr/bin/env bash
# Install or verify the root-owned privileged mutation runtime.
set -Eeuo pipefail

PATH=/usr/sbin:/usr/bin:/sbin:/bin
umask 077
readonly PATH

readonly SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly INSTALL_DIR='/usr/local/libexec/fedora-radio-control'
readonly LOG_DIR='/var/log/fedora-radio-control'
readonly RUNTIME_DIR='/run/fedora-radio-control'
source "${SOURCE_DIR}/privileged/bash/lib/display.sh"
INSTALL_STAGE=''
readonly -a OBSOLETE_FILES=(
  'status-report.sh'
  'radio-state.sh'
)
readonly -a SOURCE_FILES=(
  'privileged/bash/helper.sh:radio-control-privileged:0755'
  'privileged/bash/lib/common.sh:common.sh:0640'
  'privileged/bash/lib/display.sh:display.sh:0640'
  'privileged/bash/lib/logging.sh:logging.sh:0640'
  'privileged/bash/wifi/state.sh:wifi-state.sh:0640'
  'privileged/bash/bluetooth/state.sh:bluetooth-state.sh:0640'
  'privileged/bash/lib/rfkill.sh:rfkill.sh:0640'
  'privileged/bash/lib/radio-policy.sh:radio-policy.sh:0640'
  'privileged/bash/wifi/control.sh:wifi-control.sh:0640'
  'privileged/bash/bluetooth/control.sh:bluetooth-control.sh:0640'
  'privileged/bash/lib/lockdown.sh:lockdown.sh:0640'
  'VERSION:VERSION:0644'
)

error() { display_error "$*"; }
info() { display_info "$*"; }

cleanup_install_stage() {
  [[ -n "${INSTALL_STAGE:-}" ]] || return 0
  rm -rf -- "${INSTALL_STAGE}"
}

trap cleanup_install_stage EXIT

require_fedora_root() {
  [[ -r /etc/os-release ]] || { error 'Cannot read /etc/os-release.'; return 2; }
  [[ "$(. /etc/os-release && printf '%s' "${ID:-}")" == fedora ]] || { error 'This installer supports Fedora Linux only.'; return 2; }
  (( EUID == 0 )) || { error 'Install with: sudo ./install.sh'; return 4; }
}

verify_syntax() {
  local record source _target _mode
  for record in "${SOURCE_FILES[@]}"; do
    IFS=: read -r source _target _mode <<< "${record}"
    bash -n "${SOURCE_DIR}/${source}"
  done
}

verify_staged_syntax() {
  local directory="$1" record _source target _mode
  for record in "${SOURCE_FILES[@]}"; do
    IFS=: read -r _source target _mode <<< "${record}"
    bash -n "${directory}/${target}"
  done
}

prepare_install_directory() {
  local owner mode
  if [[ -e "${INSTALL_DIR}" || -L "${INSTALL_DIR}" ]]; then
    [[ -d "${INSTALL_DIR}" && ! -L "${INSTALL_DIR}" ]] || { error "Unsafe install path: ${INSTALL_DIR}"; return 3; }
    owner="$(stat -c '%u' "${INSTALL_DIR}")"; mode="$(stat -c '%a' "${INSTALL_DIR}")"
    [[ "${owner}" == 0 ]] && (( ((8#${mode}) & 8#022) == 0 )) || { error 'Existing install directory ownership or permissions are unsafe.'; return 3; }
    chmod 0755 "${INSTALL_DIR}"
  else
    install -d -o root -g root -m 0755 "${INSTALL_DIR}"
  fi
}

safe_file() {
  local path="$1" expected_mode="${2:-}" owner mode
  [[ -f "${path}" && ! -L "${path}" ]] || return 1
  owner="$(stat -c '%u' "${path}")"
  mode="$(stat -c '%a' "${path}")"
  [[ "${owner}" == 0 ]] && (( ((8#${mode}) & 8#022) == 0 )) || return 1
  [[ -z "${expected_mode}" || "${mode}" == "${expected_mode}" ]]
}

remove_obsolete_runtime_files() {
  local target path
  for target in "${OBSOLETE_FILES[@]}"; do
    path="${INSTALL_DIR}/${target}"
    [[ -e "${path}" || -L "${path}" ]] || continue
    safe_file "${path}" || { error "Obsolete installed file is unsafe: ${target}"; return 3; }
    rm -f -- "${path}"
  done
}

verify_installation() {
  local record _source target expected_mode owner mode
  [[ -d "${INSTALL_DIR}" && ! -L "${INSTALL_DIR}" ]] || { error "Missing installed directory: ${INSTALL_DIR}"; return 3; }
  owner="$(stat -c '%u' "${INSTALL_DIR}")"; mode="$(stat -c '%a' "${INSTALL_DIR}")"
  [[ "${owner}" == 0 && "${mode}" == 755 ]] || { error 'Installed directory must be root-owned with mode 0755 for normal-user verification.'; return 3; }
  for record in "${SOURCE_FILES[@]}"; do
    IFS=: read -r _source target expected_mode <<< "${record}"
    safe_file "${INSTALL_DIR}/${target}" "${expected_mode#0}" || { error "Installed file is missing or has unexpected permissions: ${target}"; return 3; }
    bash -n "${INSTALL_DIR}/${target}" || { error "Installed script has invalid syntax: ${target}"; return 3; }
  done
  [[ -d "${LOG_DIR}" && ! -L "${LOG_DIR}" ]] || { error "Missing protected log directory: ${LOG_DIR}"; return 3; }
  owner="$(stat -c '%u' "${LOG_DIR}")"; mode="$(stat -c '%a' "${LOG_DIR}")"
  [[ "${owner}" == 0 && "${mode}" == 700 ]] || { error 'Protected log directory ownership or permissions are unsafe.'; return 3; }
  install -d -o root -g root -m 0700 "${RUNTIME_DIR}"
}

show_verification_summary() {
  display_heading 'Privileged Runtime Verified'
  display_label 'Runtime files:' "${#SOURCE_FILES[@]} reviewed files verified" safe
  display_label 'Helper:' "${INSTALL_DIR}/radio-control-privileged" paper
  display_label 'Compatibility protocol:' "$(<"${SOURCE_DIR}/VERSION")" safe
  display_label 'Runtime directory:' 'root:root, mode 0755' safe
  display_label 'Protected logs:' "${LOG_DIR} (root-only, mode 0700)" safe
}

show_install_summary() {
  show_verification_summary
  display_rule
  display_success 'Installation complete.'
  display_label 'Next:' 'start normally with ./run.sh' signal
  display_warning 'Do not use sudo ./run.sh; selected radio actions prompt for sudo as needed.'
}

install_runtime() {
  local stage record source target mode
  info 'Validating reviewed runtime files...'
  INSTALL_STAGE="$(mktemp -d /root/.fedora-radio-control.XXXXXX)"
  install -d -o root -g root -m 0755 "${INSTALL_STAGE}/runtime"
  info "Staging ${#SOURCE_FILES[@]} root-owned runtime files..."
  for record in "${SOURCE_FILES[@]}"; do
    IFS=: read -r source target mode <<< "${record}"
    install -o root -g root -m "${mode}" "${SOURCE_DIR}/${source}" "${INSTALL_STAGE}/runtime/${target}"
  done
  verify_staged_syntax "${INSTALL_STAGE}/runtime"
  prepare_install_directory
  remove_obsolete_runtime_files
  info 'Deploying the privileged helper and support modules...'
  for record in "${SOURCE_FILES[@]}"; do
    IFS=: read -r _source target _mode <<< "${record}"
    install -o root -g root -m "$(stat -c '%a' "${INSTALL_STAGE}/runtime/${target}")" "${INSTALL_STAGE}/runtime/${target}" "${INSTALL_DIR}/.${target}.new"
    mv -f "${INSTALL_DIR}/.${target}.new" "${INSTALL_DIR}/${target}"
  done
  install -d -o root -g root -m 0700 "${LOG_DIR}" "${RUNTIME_DIR}"
  info 'Verifying ownership, permissions, syntax, and log protection...'
  verify_installation
  show_install_summary
  cleanup_install_stage
  INSTALL_STAGE=''
}

case "${1:-}" in
  '') require_fedora_root && verify_syntax && install_runtime ;;
  --verify) require_fedora_root && verify_installation && show_verification_summary ;;
  *) error 'Usage: sudo ./install.sh [--verify]'; exit 2 ;;
esac
