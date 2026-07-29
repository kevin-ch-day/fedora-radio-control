#!/usr/bin/env bash
set -Eeuo pipefail

(( EUID != 0 )) || {
  printf 'REFUSE: static tests must not run as root.\n' >&2
  exit 77
}

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${REPO_DIR}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for file in run.sh install.sh VERSION pyproject.toml docs/architecture.md privileged/bash/helper.sh privileged/bash/wifi/state.sh privileged/bash/wifi/control.sh privileged/bash/bluetooth/state.sh privileged/bash/bluetooth/control.sh src/fedora_radio_control/__init__.py src/fedora_radio_control/__main__.py src/fedora_radio_control/cli.py src/fedora_radio_control/menus.py src/fedora_radio_control/readiness.py src/fedora_radio_control/reports.py src/fedora_radio_control/state.py src/fedora_radio_control/system.py src/fedora_radio_control/ui.py privileged/bash/lib/common.sh privileged/bash/lib/logging.sh privileged/bash/lib/rfkill.sh privileged/bash/lib/radio-policy.sh privileged/bash/lib/lockdown.sh tests/test-static.sh tests/test-python.sh tests/python/test_cli.py tests/python/test_state.py tests/python/test_collectors.py tests/python/test_reports.py tests/python/test_system.py tests/python/test_ui.py tests/test-logging.sh tests/test-policy.sh tests/test-lockdown.sh tests/test-bluetooth-control.sh tests/test-wifi-control.sh tests/test-wifi-state.sh README.md LICENSE logs/.gitkeep .gitignore; do
  [[ -e "${file}" ]] || fail "Missing required file: ${file}"
done

[[ -x run.sh && -x install.sh && -x privileged/bash/helper.sh && -x tests/test-python.sh ]] || fail 'public and privileged scripts must be executable'
grep -Fq 'package-dir = { "" = "src" }' pyproject.toml || fail 'Python package must use the src layout'
grep -Fq 'requires-python = ">=3.10"' pyproject.toml || fail 'Python version support must be declared'

for file in run.sh install.sh privileged/bash/helper.sh privileged/bash/wifi/state.sh privileged/bash/wifi/control.sh privileged/bash/bluetooth/state.sh privileged/bash/bluetooth/control.sh privileged/bash/lib/common.sh privileged/bash/lib/logging.sh privileged/bash/lib/rfkill.sh privileged/bash/lib/radio-policy.sh privileged/bash/lib/lockdown.sh tests/test-static.sh tests/test-logging.sh tests/test-policy.sh tests/test-lockdown.sh tests/test-bluetooth-control.sh tests/test-wifi-control.sh tests/test-wifi-state.sh; do
  bash -n "${file}"
done

./run.sh --help >/dev/null
./run.sh help >/dev/null
set +e
./install.sh --verify >/dev/null 2>&1
installer_verify_status=$?
set -e
[[ "${installer_verify_status}" -eq 4 ]] || fail "Installer verification without root returned ${installer_verify_status}, expected 4"

set +e
./run.sh invalid-command >/dev/null 2>&1
invalid_status=$?
./run.sh status >/dev/null 2>&1
status_status=$?
./run.sh readiness >/dev/null 2>&1
readiness_status=$?
./run.sh activity >/dev/null 2>&1
activity_status=$?
./run.sh wifi profiles >/dev/null 2>&1
wifi_profiles_status=$?
./run.sh bluetooth enable >/dev/null 2>&1
unsupported_bluetooth_status=$?
./run.sh </dev/null >/dev/null 2>&1
closed_input_menu_status=$?
printf '1\n0\n' | ./run.sh >/dev/null 2>&1
menu_status=$?
printf '5\n0\n' | ./run.sh >/dev/null 2>&1
readiness_menu_status=$?
printf '7\n0\n' | ./run.sh >/dev/null 2>&1
clear_menu_status=$?
printf '3\n0\n0\n' | ./run.sh >/dev/null 2>&1
wifi_menu_status=$?
printf '4\n0\n0\n' | ./run.sh >/dev/null 2>&1
bluetooth_menu_status=$?
printf 'invalid\n0\n' | ./run.sh >/dev/null 2>&1
invalid_menu_status=$?
set -e

[[ "${invalid_status}" -eq 2 ]] || fail "Invalid command returned ${invalid_status}, expected 2"
case "${status_status}" in
  0|1|3) ;;
  *) fail "status returned ${status_status}, expected 0, 1, or 3" ;;
esac
case "${readiness_status}" in
  0|1|3) ;;
  *) fail "readiness returned ${readiness_status}, expected 0, 1, or 3" ;;
esac
case "${activity_status}" in
  0|3) ;;
  *) fail "activity returned ${activity_status}, expected 0 or 3" ;;
esac
[[ "${unsupported_bluetooth_status}" -eq 2 ]] || fail "Unsupported Bluetooth enable returned ${unsupported_bluetooth_status}, expected 2"
case "${wifi_profiles_status}" in
  0|3) ;;
  *) fail "Wi-Fi profile inspection returned ${wifi_profiles_status}, expected 0 or 3" ;;
esac
[[ "${menu_status}" -eq 0 ]] || fail "Read-only menu returned ${menu_status}, expected 0"
[[ "${readiness_menu_status}" -eq 0 ]] || fail "Readiness menu returned ${readiness_menu_status}, expected 0"
[[ "${clear_menu_status}" -eq 0 ]] || fail "Clear-screen menu returned ${clear_menu_status}, expected 0"
[[ "${wifi_menu_status}" -eq 0 ]] || fail "Wi-Fi read-only menu returned ${wifi_menu_status}, expected 0"
[[ "${bluetooth_menu_status}" -eq 0 ]] || fail "Bluetooth menu returned ${bluetooth_menu_status}, expected 0"
[[ "${invalid_menu_status}" -eq 0 ]] || fail "Invalid-input menu returned ${invalid_menu_status}, expected 0"
[[ "${closed_input_menu_status}" -eq 0 ]] || fail "Closed-input menu returned ${closed_input_menu_status}, expected 0"

./tests/test-logging.sh
./tests/test-python.sh
./tests/test-policy.sh
./tests/test-lockdown.sh
./tests/test-bluetooth-control.sh
./tests/test-wifi-control.sh
./tests/test-wifi-state.sh

for prohibited in 'nmcli device wifi rescan' 'systemctl start' 'systemctl enable' 'systemctl disable' 'systemctl unmask' 'nmcli connection modify'; do
  if grep -Fq "${prohibited}" run.sh privileged/bash/wifi/*.sh privileged/bash/bluetooth/*.sh privileged/bash/lib/*.sh; then
    fail "Runtime code contains prohibited mutation command: ${prohibited}"
  fi
done

for prohibited in 'nmcli device wifi rescan' 'systemctl start' 'systemctl enable' 'systemctl disable' 'systemctl unmask' 'nmcli connection modify' 'nmcli radio wifi on' 'nmcli radio wifi off' 'rfkill block' 'rfkill unblock' 'systemctl stop' 'systemctl mask' 'bluetoothctl power'; do
  if grep -R --include='*.py' -Fq "${prohibited}" src/fedora_radio_control; then
    fail "Python frontend contains a direct radio mutation command: ${prohibited}"
  fi
done
if grep -R --include='*.py' -Eq 'shell[[:space:]]*=[[:space:]]*True|os\.system|Popen\(' src/fedora_radio_control; then
  fail 'Python frontend must not use shell execution'
fi

for prohibited in 'nmcli radio wifi on' 'nmcli radio wifi off' 'rfkill block' 'rfkill unblock' 'systemctl stop' 'systemctl mask' 'bluetoothctl power'; do
  if grep -Fl "${prohibited}" run.sh privileged/bash/wifi/*.sh privileged/bash/bluetooth/*.sh privileged/bash/lib/*.sh | grep -Fxv 'privileged/bash/lib/lockdown.sh' | grep -Fxv 'privileged/bash/wifi/control.sh' | grep -Fxv 'privileged/bash/bluetooth/control.sh' >/dev/null; then
    fail "Mutation command appears outside an approved control module: ${prohibited}"
  fi
done

grep -Fq 'python3 -m fedora_radio_control "$@"' run.sh || fail 'run.sh must pass unchanged arguments to the Python application'
grep -Fq 'APPLICATION="${SCRIPT_DIR}/src/fedora_radio_control/__main__.py"' run.sh || fail 'run.sh must resolve the Python application absolutely'
grep -Fq 'PYTHONPATH=${SCRIPT_DIR}/src' run.sh || fail 'run.sh must load Python from the source package root'
if grep -Eq 'EUID|show_main_menu|refresh_radio_state|rfkill|nmcli|bluetoothctl' run.sh; then
  fail 'run.sh must not contain privilege, menu, or radio-state implementation logic'
fi
grep -Fq 'source "${RUNTIME_DIR}/wifi-control.sh"' privileged/bash/helper.sh || fail 'Helper must source installed Wi-Fi mutation module'
grep -Fq 'recent-activity)' privileged/bash/helper.sh || fail 'Helper must provide protected recent activity output'
grep -Fq 'PATH=/usr/sbin:/usr/bin:/sbin:/bin' privileged/bash/helper.sh || fail 'Helper must set a controlled PATH'
if grep -Eq '\beval\b|bash[[:space:]]+-c|sh[[:space:]]+-c' install.sh privileged/bash/helper.sh; then
  fail 'Privileged boundary contains dynamic command execution'
fi

if command -v shellcheck >/dev/null 2>&1; then
  # Modules exchange state after being sourced by the installed helper, which
  # ShellCheck cannot follow from a source checkout. Test literals and mocked
  # functions are likewise intentionally not expanded or called directly.
  shellcheck -e SC1091,SC2016,SC2034,SC2329 run.sh privileged/bash/wifi/state.sh privileged/bash/wifi/control.sh privileged/bash/bluetooth/state.sh privileged/bash/bluetooth/control.sh privileged/bash/lib/common.sh privileged/bash/lib/logging.sh privileged/bash/lib/rfkill.sh privileged/bash/lib/radio-policy.sh privileged/bash/lib/lockdown.sh tests/test-static.sh tests/test-logging.sh tests/test-policy.sh tests/test-lockdown.sh tests/test-bluetooth-control.sh tests/test-wifi-control.sh tests/test-wifi-state.sh
else
  printf 'SKIP: ShellCheck is not installed.\n'
fi

printf 'Static checks passed.\n'
