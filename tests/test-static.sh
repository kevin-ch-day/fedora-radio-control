#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${REPO_DIR}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for file in run.sh wifi/state.sh wifi/control.sh bluetooth/state.sh bluetooth/control.sh lib/application.sh lib/menu-controller.sh lib/common.sh lib/display.sh lib/prompts.sh lib/menu.sh lib/radio-state.sh lib/readiness.sh lib/lockdown.sh tests/test-static.sh tests/test-policy.sh tests/test-lockdown.sh tests/test-bluetooth-control.sh README.md LICENSE logs/.gitkeep .gitignore; do
  [[ -e "${file}" ]] || fail "Missing required file: ${file}"
done

[[ -x run.sh ]] || fail 'run.sh must be executable'

for file in run.sh wifi/state.sh wifi/control.sh bluetooth/state.sh bluetooth/control.sh lib/application.sh lib/menu-controller.sh lib/common.sh lib/display.sh lib/prompts.sh lib/menu.sh lib/radio-state.sh lib/readiness.sh lib/lockdown.sh tests/test-static.sh tests/test-policy.sh tests/test-lockdown.sh tests/test-bluetooth-control.sh; do
  bash -n "${file}"
done

./run.sh --help >/dev/null
./run.sh help >/dev/null

set +e
./run.sh invalid-command >/dev/null 2>&1
invalid_status=$?
./run.sh status >/dev/null 2>&1
status_status=$?
./run.sh readiness >/dev/null 2>&1
readiness_status=$?
./run.sh wifi profiles >/dev/null 2>&1
wifi_profiles_status=$?
./run.sh bluetooth enable >/dev/null 2>&1
bluetooth_enable_status=$?
./run.sh bluetooth disable >/dev/null 2>&1
bluetooth_disable_status=$?
./run.sh </dev/null >/dev/null 2>&1
closed_input_menu_status=$?
printf '1\n0\n' | ./run.sh >/dev/null 2>&1
menu_status=$?
printf '5\n0\n' | ./run.sh >/dev/null 2>&1
readiness_menu_status=$?
printf '2\n0\n' | ./run.sh >/dev/null 2>&1
lockdown_menu_status=$?
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
[[ "${bluetooth_enable_status}" -eq 2 ]] || fail "Unimplemented Bluetooth enable returned ${bluetooth_enable_status}, expected 2"
[[ "${bluetooth_disable_status}" -eq 4 ]] || fail "Bluetooth disable without root returned ${bluetooth_disable_status}, expected 4"
case "${wifi_profiles_status}" in
  0|3) ;;
  *) fail "Wi-Fi profile inspection returned ${wifi_profiles_status}, expected 0 or 3" ;;
esac
[[ "${menu_status}" -eq 0 ]] || fail "Read-only menu returned ${menu_status}, expected 0"
[[ "${readiness_menu_status}" -eq 0 ]] || fail "Readiness menu returned ${readiness_menu_status}, expected 0"
[[ "${lockdown_menu_status}" -eq 0 ]] || fail "Lockdown placeholder menu returned ${lockdown_menu_status}, expected 0"
[[ "${wifi_menu_status}" -eq 0 ]] || fail "Wi-Fi read-only menu returned ${wifi_menu_status}, expected 0"
[[ "${bluetooth_menu_status}" -eq 0 ]] || fail "Bluetooth menu returned ${bluetooth_menu_status}, expected 0"
[[ "${invalid_menu_status}" -eq 0 ]] || fail "Invalid-input menu returned ${invalid_menu_status}, expected 0"
[[ "${closed_input_menu_status}" -eq 0 ]] || fail "Closed-input menu returned ${closed_input_menu_status}, expected 0"

./tests/test-policy.sh
./tests/test-lockdown.sh
./tests/test-bluetooth-control.sh

for prohibited in 'nmcli device wifi rescan' 'systemctl start' 'systemctl enable' 'systemctl disable' 'systemctl unmask' 'nmcli connection modify'; do
  if grep -Fq "${prohibited}" run.sh wifi/*.sh bluetooth/*.sh lib/*.sh; then
    fail "Runtime code contains prohibited mutation command: ${prohibited}"
  fi
done

for prohibited in 'nmcli radio wifi on' 'nmcli radio wifi off' 'rfkill block' 'rfkill unblock' 'systemctl stop' 'systemctl mask' 'bluetoothctl power'; do
  if grep -Fl "${prohibited}" run.sh wifi/*.sh bluetooth/*.sh lib/*.sh | grep -Fxv 'lib/lockdown.sh' | grep -Fxv 'wifi/control.sh' | grep -Fxv 'bluetooth/control.sh' >/dev/null; then
    fail "Mutation command appears outside an approved control module: ${prohibited}"
  fi
done

grep -Fq 'source "${APPLICATION}"' run.sh || fail 'run.sh must load the internal application library'
grep -Fq 'app_main "$@"' run.sh || fail 'run.sh must pass unchanged arguments to the application'
grep -Fq 'APPLICATION="${SCRIPT_DIR}/lib/application.sh"' run.sh || fail 'run.sh must resolve the application library absolutely'
if grep -Eq 'EUID|show_main_menu|refresh_radio_state|rfkill|nmcli|bluetoothctl' run.sh; then
  fail 'run.sh must not contain privilege, menu, or radio-state implementation logic'
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck run.sh wifi/state.sh wifi/control.sh bluetooth/state.sh bluetooth/control.sh lib/application.sh lib/menu-controller.sh lib/common.sh lib/display.sh lib/prompts.sh lib/menu.sh lib/radio-state.sh lib/readiness.sh lib/lockdown.sh tests/test-static.sh tests/test-policy.sh tests/test-lockdown.sh tests/test-bluetooth-control.sh
else
  printf 'SKIP: ShellCheck is not installed.\n'
fi

printf 'Static checks passed.\n'
