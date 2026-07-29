#!/usr/bin/env bash
# Compatibility loader for focused RFKill, policy, and status modules.

RADIO_STATE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=rfkill.sh
source "${RADIO_STATE_DIR}/rfkill.sh"
# shellcheck source=radio-policy.sh
source "${RADIO_STATE_DIR}/radio-policy.sh"
# shellcheck source=status-report.sh
source "${RADIO_STATE_DIR}/status-report.sh"
