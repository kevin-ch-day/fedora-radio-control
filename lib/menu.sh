#!/usr/bin/env bash
# Numbered menus. The selected zero-based index is written to stdout; menu text
# uses the terminal when available and otherwise stderr for pipe-friendly tests.

menu_select() {
  local title="$1"
  shift
  local -a options=("$@")
  local index reply

  (( ${#options[@]} > 0 )) || return 2
  prompt_is_interactive || return 2

  local output='/dev/stderr'
  [[ -t 0 && -w /dev/tty ]] && output='/dev/tty'
  printf '\n%s\n' "${title}" > "${output}"
  for index in "${!options[@]}"; do
    printf '  %d) %s\n' "$((index + 1))" "${options[index]}" > "${output}"
  done

  reply="$(prompt_read 'Choose an option (or press Enter to cancel): ')" || return $?
  [[ -n "${reply}" ]] || return 1
  [[ "${reply}" =~ ^[0-9]+$ ]] || return 1
  (( reply >= 1 && reply <= ${#options[@]} )) || return 1
  printf '%s\n' "$((reply - 1))"
}

menu_read_selection() {
  local minimum="$1"
  local maximum="$2"
  local reply

  [[ "${minimum}" =~ ^[0-9]+$ && "${maximum}" =~ ^[0-9]+$ ]] || return 2
  (( minimum <= maximum )) || return 2
  reply="$(prompt_read 'Selection: ')" || return $?
  [[ "${reply}" =~ ^[0-9]+$ ]] || return 1
  (( reply >= minimum && reply <= maximum )) || return 1
  printf '%s' "${reply}"
}
