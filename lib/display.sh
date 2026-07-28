#!/usr/bin/env bash
# Terminal presentation helpers. ANSI color is used only for interactive output.

UI_COLOR_RESET=''
UI_COLOR_BOLD=''
UI_COLOR_DIM=''
UI_COLOR_GREEN=''
UI_COLOR_YELLOW=''
UI_COLOR_RED=''
UI_COLOR_CYAN=''

ui_init() {
  [[ -t 1 && -z "${NO_COLOR:-}" ]] || return 0
  UI_COLOR_RESET=$'\033[0m'
  UI_COLOR_BOLD=$'\033[1m'
  UI_COLOR_DIM=$'\033[2m'
  UI_COLOR_GREEN=$'\033[32m'
  UI_COLOR_YELLOW=$'\033[33m'
  UI_COLOR_RED=$'\033[31m'
  UI_COLOR_CYAN=$'\033[36m'
}

ui_heading() {
  printf '%s%s%s\n' "${UI_COLOR_BOLD}${UI_COLOR_CYAN}" "$1" "${UI_COLOR_RESET}"
  printf '%s\n' '============================================================'
}

ui_rule() {
  printf '%s\n' '------------------------------------------------------------'
}

ui_section() {
  printf '\n%s%s%s\n' "${UI_COLOR_BOLD}" "$1" "${UI_COLOR_RESET}"
}

ui_label() {
  printf '  %-22s %s\n' "$1" "$2"
}

ui_note() {
  printf '%s%s%s\n' "${UI_COLOR_DIM}" "$1" "${UI_COLOR_RESET}"
}

ui_clear_screen() {
  # Do not emit control characters when output is captured for logs or tests.
  [[ -t 1 ]] || return 0
  printf '\033[2J\033[H'
}

ui_wait_for_return() {
  [[ -t 0 && -t 1 ]] || return 0
  printf '\nPress Enter to return to the menu... ' > /dev/tty
  IFS= read -r < /dev/tty || true
}

ui_result() {
  local label="$1"
  local color="${UI_COLOR_YELLOW}"
  case "${label}" in
    'LOCKED DOWN'|DISABLED) color="${UI_COLOR_GREEN}" ;;
    'NOT LOCKED DOWN'|'STATE UNKNOWN'|'NOT FULLY DISABLED') color="${UI_COLOR_RED}" ;;
  esac
  printf '%s%s%s' "${color}" "${label}" "${UI_COLOR_RESET}"
}
