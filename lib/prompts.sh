#!/usr/bin/env bash
# Interactive helpers for future state-changing commands. Status never calls these.

prompt_is_interactive() {
  [[ -t 0 || -p /dev/stdin ]]
}

prompt_read() {
  local message="$1"
  local reply=''
  prompt_is_interactive || return 2
  if [[ -t 0 && -r /dev/tty && -w /dev/tty ]]; then
    printf '%s' "${message}" > /dev/tty
    IFS= read -r reply < /dev/tty || return 2
  else
    printf '%s' "${message}" >&2
    IFS= read -r reply || return 2
  fi
  printf '%s' "${reply}"
}

prompt_confirm() {
  local message="$1"
  local default="${2:-no}"
  local suffix reply
  case "${default}" in
    yes) suffix='[Y/n]' ;;
    no) suffix='[y/N]' ;;
    *) return 2 ;;
  esac

  reply="$(prompt_read "${message} ${suffix} ")" || return $?
  case "${reply}" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    [Nn]|[Nn][Oo]) return 1 ;;
    '') [[ "${default}" == 'yes' ]] ;;
    *) return 1 ;;
  esac
}
