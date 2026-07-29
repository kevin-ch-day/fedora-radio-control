#!/usr/bin/env bash
# RFKill JSON collection and rendering shared by Wi-Fi and Bluetooth state.

json_field() {
  local object="$1" field="$2" expression
  expression="\"${field}\"[[:space:]]*:[[:space:]]*\"?([^\",}[:space:]]+)\"?"
  [[ "${object}" =~ ${expression} ]] && { printf '%s' "${BASH_REMATCH[1]}"; return 0; }
  return 1
}

collect_rfkill() {
  local raw_json object index type device soft hard
  WIFI_RFKILL=(); BLUETOOTH_RFKILL=()
  WIFI_RFKILL_COUNT=0; BLUETOOTH_RFKILL_COUNT=0
  if ! raw_json="$(rfkill --json 2>/dev/null)"; then
    error 'Unable to query RFKill state.'; mark_query_failure; return
  fi
  if [[ "${raw_json}" != *'"rfkilldevices"'* ]]; then
    error 'RFKill JSON output did not contain a device list.'; mark_query_failure; return
  fi
  while IFS= read -r object || [[ -n "${object}" ]]; do
    type="$(json_field "${object}" type || true)"
    [[ -n "${type}" ]] || continue
    index="$(json_field "${object}" id || json_field "${object}" index || true)"
    device="$(json_field "${object}" device || json_field "${object}" name || true)"
    soft="$(json_field "${object}" soft || true)"; hard="$(json_field "${object}" hard || true)"
    if [[ -z "${index}" || -z "${device}" || -z "${soft}" || -z "${hard}" ]]; then
      error 'RFKill JSON output contained an incomplete device entry.'; mark_query_failure; continue
    fi
    case "${type}" in
      wlan) WIFI_RFKILL+=("${index}|${device}|${soft}|${hard}"); ((WIFI_RFKILL_COUNT += 1)) ;;
      bluetooth) BLUETOOTH_RFKILL+=("${index}|${device}|${soft}|${hard}"); ((BLUETOOTH_RFKILL_COUNT += 1)) ;;
    esac
  done < <(printf '%s\n' "${raw_json}" | tr '\n' ' ' | sed -E 's/}[[:space:]]*,?[[:space:]]*\{/}\n\{/g')
}

rfkill_entries_disabled() {
  local entry _index _device soft hard
  (( $# > 0 )) || return 1
  for entry in "$@"; do
    IFS='|' read -r _index _device soft hard <<< "${entry}"
    [[ "${soft}" == 'blocked' || "${hard}" == 'blocked' ]] || return 1
  done
}

rfkill_summary() {
  local entry _index _device soft hard
  (( $# > 0 )) || { printf 'NOT DETECTED'; return; }
  for entry in "$@"; do
    IFS='|' read -r _index _device soft hard <<< "${entry}"
    [[ "${soft}" == 'blocked' || "${hard}" == 'blocked' ]] || { printf 'UNBLOCKED'; return; }
  done
  printf 'BLOCKED'
}

rfkill_hardware_block_present() {
  local entry _index _device _soft hard
  for entry in "$@"; do
    IFS='|' read -r _index _device _soft hard <<< "${entry}"
    [[ "${hard}" == 'blocked' ]] && return 0
  done
  return 1
}

print_rfkill_entries() {
  local entry index device soft hard
  for entry in "$@"; do
    IFS='|' read -r index device soft hard <<< "${entry}"
    printf '\n  [%s] %s\n' "${index}" "${device}"
    printf '      Soft blocked: %s\n' "$([[ "${soft}" == 'blocked' ]] && printf yes || printf no)"
    printf '      Hard blocked: %s\n' "$([[ "${hard}" == 'blocked' ]] && printf yes || printf no)"
  done
}
