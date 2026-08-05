#!/usr/bin/env bash
# Shared Bash display helpers must remain useful when output is captured.
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../privileged/bash/lib/display.sh
source "${REPO_DIR}/privileged/bash/lib/display.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ "${DISPLAY_COLOR}" == 0 ]] || fail 'captured output must not contain ANSI color codes'
heading="$(display_heading 'runtime verified')"
[[ "${heading}" == *'[ FRC ] // RUNTIME VERIFIED'* ]] || fail 'heading did not preserve the FRC identity'
[[ "${heading}" != *$'\033['* ]] || fail 'captured heading contains ANSI escape codes'
[[ "$(display_info 'staging reviewed files')" == '[ FRC ] staging reviewed files' ]] || fail 'info line was not rendered clearly'
[[ "$(display_label 'Status:' 'VERIFIED' safe)" == *'Status:'*'VERIFIED' ]] || fail 'label line was not rendered clearly'
[[ "$(display_success 'verified')" == '[ SAFE ] verified' ]] || fail 'success line was not rendered clearly'
[[ "$(display_warning 'review needed')" == '[ REVIEW ] review needed' ]] || fail 'warning line was not rendered clearly'
[[ "$(display_error 'verification failed' 2>&1)" == '!! verification failed' ]] || fail 'error line was not rendered clearly'

printf 'Display tests passed.\n'
