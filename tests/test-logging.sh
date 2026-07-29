#!/usr/bin/env bash
# Logging fixture tests. All output is confined to a temporary directory.
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT

# shellcheck source=../lib/common.sh
source "${REPO_DIR}/privileged/bash/lib/common.sh"
APPLICATION_ROOT="${TEST_DIR}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

begin_action_log 'fixture-action' || fail 'could not create a fixture action log'
action_log_write "${ACTION_LOG_FILE}" 'sample_value' $'first line\nsecond line' || fail 'could not write sanitized fixture field'
action_log_result "${ACTION_LOG_FILE}" 'VERIFIED' '0' || fail 'could not write fixture completion'

[[ -L "${ACTION_LOG_DIRECTORY}/latest.log" ]] || fail 'latest log link was not created'
grep -Fqx 'log_schema_version=1' "${ACTION_LOG_FILE}" || fail 'schema version is missing'
grep -Fqx 'sample_value=first line second line' "${ACTION_LOG_FILE}" || fail 'newlines were not sanitized'
grep -Fqx 'final_result=VERIFIED' "${ACTION_LOG_FILE}" || fail 'final result is missing'
grep -Fqx 'exit_code=0' "${ACTION_LOG_FILE}" || fail 'final exit code is missing'

activity="$(action_log_show_recent_activity)"
[[ "${activity}" == *'fixture-action'* ]] || fail 'activity summary omitted the action'
[[ "${activity}" == *'VERIFIED'* ]] || fail 'activity summary omitted the verified result'

printf 'Logging tests passed.\n'
