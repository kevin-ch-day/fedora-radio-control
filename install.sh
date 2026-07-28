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
INSTALL_STAGE=''
readonly -a SOURCE_FILES=(
  'privileged/helper.sh:radio-control-privileged:0755'
  'lib/common.sh:common.sh:0640'
  'wifi/state.sh:wifi-state.sh:0640'
  'bluetooth/state.sh:bluetooth-state.sh:0640'
  'lib/radio-state.sh:radio-state.sh:0640'
  'wifi/control.sh:wifi-control.sh:0640'
  'bluetooth/control.sh:bluetooth-control.sh:0640'
  'lib/lockdown.sh:lockdown.sh:0640'
  'VERSION:VERSION:0640'
)

error() { printf 'Error: %s\n' "$*" >&2; }

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
  local path="$1" owner mode
  [[ -f "${path}" && ! -L "${path}" ]] || return 1
  owner="$(stat -c '%u' "${path}")"
  mode="$(stat -c '%a' "${path}")"
  [[ "${owner}" == 0 ]] && (( ((8#${mode}) & 8#022) == 0 ))
}

verify_installation() {
  local record _source target _mode owner mode
  [[ -d "${INSTALL_DIR}" && ! -L "${INSTALL_DIR}" ]] || { error "Missing installed directory: ${INSTALL_DIR}"; return 3; }
  owner="$(stat -c '%u' "${INSTALL_DIR}")"; mode="$(stat -c '%a' "${INSTALL_DIR}")"
  [[ "${owner}" == 0 ]] && (( ((8#${mode}) & 8#022) == 0 )) || { error 'Installed directory ownership or permissions are unsafe.'; return 3; }
  for record in "${SOURCE_FILES[@]}"; do
    IFS=: read -r _source target _mode <<< "${record}"
    safe_file "${INSTALL_DIR}/${target}" || { error "Installed file is missing or unsafe: ${target}"; return 3; }
    bash -n "${INSTALL_DIR}/${target}" || { error "Installed script has invalid syntax: ${target}"; return 3; }
  done
  [[ -d "${LOG_DIR}" && ! -L "${LOG_DIR}" ]] || { error "Missing protected log directory: ${LOG_DIR}"; return 3; }
  owner="$(stat -c '%u' "${LOG_DIR}")"; mode="$(stat -c '%a' "${LOG_DIR}")"
  [[ "${owner}" == 0 && "${mode}" == 700 ]] || { error 'Protected log directory ownership or permissions are unsafe.'; return 3; }
  install -d -o root -g root -m 0700 "${RUNTIME_DIR}"
  printf 'Privileged component verified: %s\n' "${INSTALL_DIR}"
}

install_runtime() {
  local stage record source target mode
  INSTALL_STAGE="$(mktemp -d /root/.fedora-radio-control.XXXXXX)"
  install -d -o root -g root -m 0755 "${INSTALL_STAGE}/runtime"
  for record in "${SOURCE_FILES[@]}"; do
    IFS=: read -r source target mode <<< "${record}"
    install -o root -g root -m "${mode}" "${SOURCE_DIR}/${source}" "${INSTALL_STAGE}/runtime/${target}"
  done
  verify_staged_syntax "${INSTALL_STAGE}/runtime"
  prepare_install_directory
  for record in "${SOURCE_FILES[@]}"; do
    IFS=: read -r _source target _mode <<< "${record}"
    install -o root -g root -m "$(stat -c '%a' "${INSTALL_STAGE}/runtime/${target}")" "${INSTALL_STAGE}/runtime/${target}" "${INSTALL_DIR}/.${target}.new"
    mv -f "${INSTALL_DIR}/.${target}.new" "${INSTALL_DIR}/${target}"
  done
  install -d -o root -g root -m 0700 "${LOG_DIR}" "${RUNTIME_DIR}"
  printf 'Installed privileged component: %s\n' "${INSTALL_DIR}/radio-control-privileged"
  printf 'Protected logs: %s\n' "${LOG_DIR}"
  verify_installation
  cleanup_install_stage
  INSTALL_STAGE=''
}

case "${1:-}" in
  '') require_fedora_root && verify_syntax && install_runtime ;;
  --verify) require_fedora_root && verify_installation ;;
  *) error 'Usage: sudo ./install.sh [--verify]'; exit 2 ;;
esac
