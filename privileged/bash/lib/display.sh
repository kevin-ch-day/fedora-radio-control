#!/usr/bin/env bash
# Shared terminal presentation for reviewed Bash entry points. It intentionally
# emits no control sequences to non-terminal output, NO_COLOR, or TERM=dumb.

DISPLAY_COLOR=0
if [[ -t 1 && "${TERM:-dumb}" != 'dumb' && -z "${NO_COLOR+x}" ]]; then
  DISPLAY_COLOR=1
fi
readonly DISPLAY_COLOR

display_style() {
  local value="$1" code="$2"
  if (( DISPLAY_COLOR )); then
    printf '\033[%sm%s\033[0m' "${code}" "${value}"
  else
    printf '%s' "${value}"
  fi
}

display_tone() {
  local value="$1" tone="${2:-paper}" code
  case "${tone}" in
    safe) code='1;32' ;;
    review) code='1;33' ;;
    danger) code='1;31' ;;
    signal) code='1;36' ;;
    graphite) code='90' ;;
    info) code='36' ;;
    *) code='1;97' ;;
  esac
  display_style "${value}" "${code}"
}

display_heading() {
  local title="${1^^}"
  printf '\n'
  display_tone '[ FRC ]' danger
  display_tone " // ${title}" paper
  printf '\n'
  display_tone '===========================//===============================' graphite
  printf '\n'
}

display_rule() {
  display_tone '---------------------------//-------------------------------' graphite
  printf '\n'
}

display_info() {
  display_tone '[ FRC ]' danger
  printf ' '
  display_tone "$*" signal
  printf '\n'
}

display_label() {
  local name="$1" value="$2" tone="${3:-paper}" padded
  printf -v padded '  %-22s' "${name}"
  display_tone "${padded}" graphite
  printf ' '
  display_tone "${value}" "${tone}"
  printf '\n'
}

display_success() {
  display_tone '[ SAFE ]' safe
  printf ' '
  display_tone "$*" safe
  printf '\n'
}

display_warning() {
  display_tone '[ REVIEW ]' review
  printf ' '
  display_tone "$*" review
  printf '\n'
}

display_error() {
  display_tone '!!' danger >&2
  printf ' ' >&2
  display_tone "$*" danger >&2
  printf '\n' >&2
}

display_prompt() {
  display_tone 'COMMAND > ' signal
  display_tone "$*" paper
}
