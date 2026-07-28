# fedora-radio-control

`fedora-radio-control` is a small, auditable command-line utility for
reporting Wi-Fi and Bluetooth lockdown state on Fedora Linux laptops.

## Current milestone

The application reports NetworkManager Wi-Fi state, WLAN and Bluetooth RFKill
devices, Bluetooth service state, and Bluetooth controller availability. It
can apply verified full radio lockdown plus focused Wi-Fi and Bluetooth
disable actions; it does not change saved NetworkManager profiles, paired
devices, firewall rules, or systemd boot settings.

The `lib/` directory also contains small UI helpers for consistent terminal
display, optional color, safe confirmations, and numbered menus. `status`
does not invoke menus or prompts. Future state-changing commands may use them
to obtain an explicit terminal confirmation; they never collect credentials.

## Requirements

- Fedora Linux
- Bash
- `nmcli`, `rfkill`, and `systemctl`
- `bluetoothctl` is optional. When present, the tool reports controller
  exposure and powers down an available controller during Bluetooth disable.

## Usage

```bash
./run.sh
./run.sh status
./run.sh readiness
./run.sh wifi profiles
./run.sh --help

# Verified state-changing actions
sudo ./run.sh lockdown
sudo ./run.sh lockdown --non-interactive

# Wi-Fi controls (enable requires an interactive typed confirmation)
sudo ./run.sh wifi disable
sudo ./run.sh wifi enable

# Bluetooth disable (enable is intentionally not yet implemented)
sudo ./run.sh bluetooth disable
```

`run.sh` is the sole supported public entry point. It resolves the repository
path and loads the internal application modules. Running `./run.sh` with no
arguments opens the menu. The
menu refreshes live state before each action. Bluetooth enable remains shown
as not implemented; it does not run placeholder commands or change system
state.

## Internal layout

Radio-specific state collection is kept separate from shared policy logic:

```text
wifi/state.sh           # NetworkManager Wi-Fi state
bluetooth/state.sh      # Bluetooth service and controller state
lib/radio-state.sh      # Shared RFKill parsing and lockdown policy
lib/readiness.sh        # Cross-radio DEF CON readiness checks
```

These are internal modules; use `./run.sh` for normal operation.

Menu option `7` clears the interactive terminal and redraws the current menu.
It emits no control characters when output is redirected.

The menu exits safely without changing anything if input closes (for example,
with Ctrl+D). When started through `sudo`, status reports both the invoking
user and the effective `root` account for audit clarity.

The Wi-Fi submenu includes a read-only saved-profile autoconnect inspection.
Wi-Fi enable requires a typed terminal confirmation because it can allow saved
profiles to reconnect. Bluetooth enable remains unavailable until a separate
exposure-confirmation and recovery path is implemented and tested. `sudo` is
required only for state-changing commands.

The supported read-only commands use machine-readable output where the
platform provides it and verify the reported policy rather than relying on a
prior command's exit status.

For this milestone, Wi-Fi is effectively disabled only when NetworkManager
reports it disabled and every detected WLAN RFKill entry is soft- or
hard-blocked. Bluetooth is effectively disabled only when every detected
Bluetooth RFKill entry is soft- or hard-blocked and `bluetooth.service` is
inactive. Missing RFKill hardware is reported as `NOT DETECTED`, not treated
as secure; a Bluetooth controller being unavailable does not by itself make
an active Bluetooth service safe.

The readiness report is intentionally conservative: it reports the active
wireless interface without exposing its SSID, checks whether firewalld is
running when available, evaluates the assigned wireless firewall zone, counts
saved Wi-Fi profiles with autoconnect enabled without showing their names, and
labels incomplete checks as `REVIEW` or `UNKNOWN`. A failed required query
produces `STATE UNKNOWN`; it is never silently shown as a safe or absent
condition.
It does not change profiles, firewall zones, or connections. DEF CON network
settings must always come from the current DEF CON NOC instructions; this tool
does not guess or hard-code SSIDs, certificates, usernames, or URLs.

`./run.sh wifi profiles` is a read-only autoconnect exposure check. It
reports only a count because profile names often reveal SSIDs, locations, or
organizations. It never displays saved passwords or NetworkManager secrets.

## Exit codes

| Code | Meaning |
| ---: | --- |
| 0 | Wi-Fi and Bluetooth are verified effectively disabled (`LOCKED DOWN`). |
| 1 | State was queried successfully, but the lockdown policy is not satisfied. |
| 2 | Invalid usage or unsupported platform. |
| 3 | A required dependency or state query failed, so the state is unknown. |
| 4 | Root privileges are required for the requested state-changing action. |

For `status` and `readiness`, exit code `1` is a policy result—such as a radio
that remains enabled—not a program crash. Exit code `5` is reserved for future
state-changing commands.

## Tests

Run the non-destructive static checks with:

```bash
./tests/test-static.sh
```

The test checks Bash syntax, required files, executable permissions, help and
invalid-command behavior, and ensures the entry point has no radio mutation
commands. It also runs hardware-independent policy fixtures for RFKill,
Bluetooth service, missing-adapter, and query-failure behavior. If installed,
ShellCheck is run as an additional check; otherwise it is reported as skipped.

## Limitations

`sudo ./run.sh lockdown` and `sudo ./run.sh lockdown --non-interactive` now
perform a verified full radio lockdown. They disable NetworkManager Wi-Fi,
RFKill-block WLAN and Bluetooth, power off an available Bluetooth controller
when possible, stop `bluetooth.service`, and return nonzero unless final state
verification succeeds. Each run writes a sanitized, owner-only log under
`logs/` and updates `logs/latest.log`.

Wi-Fi disable, explicitly confirmed Wi-Fi enable, and Bluetooth disable are
implemented and write sanitized logs. Bluetooth disable RFKill-blocks the
radio, stops `bluetooth.service`, and powers off an available controller as a
best-effort step; it also applies a runtime-only systemd mask before stopping
the service to prevent D-Bus activation from restarting it. The mask is
cleared at reboot and will be explicitly removed by the future Bluetooth
enable action. Final state verification is authoritative. Bluetooth enable
remains unimplemented. Read-only status calls do not create logs, and no
persistent systemd boot-time changes are made. NetworkManager may retain its
Wi-Fi radio preference across a NetworkManager restart or reboot; use the
explicit Wi-Fi enable action when reopening that radio is intended.

When an action is started with `sudo`, its owner-only log is assigned to the
invoking user so it can be reviewed from menu option `6` without exposing it
to other local users.

The Wi-Fi menu includes a Wi-Fi-only detailed view. A `HARDWARE BLOCKED`
constraint means the physical RFKill state must be cleared outside this
application before Wi-Fi can be enabled.
A verified one-time lockdown is not continuous enforcement: another
application, hardware event, suspend/resume cycle, or reboot can change radio
state afterward.
