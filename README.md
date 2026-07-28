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

# Verified state-changing actions (the helper requests sudo only when needed)
./run.sh lockdown

# Wi-Fi controls (enable requires an interactive typed confirmation)
./run.sh wifi disable
./run.sh wifi enable

# Bluetooth disable (enable is intentionally not yet implemented)
./run.sh bluetooth disable
```

Read-only commands work directly from the checkout. Run the interactive menu
as your normal user; it refuses to start as root. Before any mutation
command is available, install the reviewed root-owned component:

```bash
sudo ./install.sh
sudo ./install.sh --verify
```

The installer does not change sudoers, create `NOPASSWD` access, install a
daemon, or modify any radio state. It installs only the mutation runtime under
`/usr/local/libexec/fedora-radio-control/`; the checkout then delegates each
approved mutation to that fixed helper. The helper rejects missing, unsafe, or
version-mismatched installed files. If the checkout reports that the component
is missing, invalid, or version-mismatched, rerun `sudo ./install.sh` and then
`sudo ./install.sh --verify`.

The installed helper directory and helper entry point are root-owned and
non-writable but world-traversable/executable, so the normal-user dashboard
can verify their integrity. Supporting mutation modules remain readable only
by root.

Action logs are root-protected under `/var/log/fedora-radio-control/`. To
review the current sanitized log without running the menu as root, use:

```bash
sudo tail -n 40 /var/log/fedora-radio-control/latest.log
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
Normal menu refreshes do not clear the screen, so terminal scrollback and
`sudo` prompts do not leave a large blank gap. Clear-screen control characters
are never emitted when output is redirected.

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
The dashboard also surfaces that sanitized count, because enabling Wi-Fi can
allow saved profiles to reconnect. The application never chooses a network,
changes a profile, or hard-codes DEF CON network names, certificates, or
connection details; use current DEF CON NOC instructions for those decisions.
The trusted Wi-Fi-enable helper rechecks this count and refuses enablement if
it cannot inspect it; when profiles are enabled for autoconnect, it warns with
the count before requiring the `ENABLE-WIFI` confirmation.

## Conference posture

Treat conference connectivity as a hostile environment. Before travel, apply
operating-system and application updates, use a purpose-limited device when
practical, and review saved Wi-Fi autoconnect profiles. During the event,
prefer current official NOC guidance for network selection and authentication
details. This application deliberately does not embed SSIDs, certificates,
credentials, or event-specific network settings. Its readiness report marks
device hygiene as `REVIEW`, because radio state alone cannot prove a system is
patched or purpose-limited.
The readiness view also reports the age of the installed package for the
currently running kernel, using only local RPM metadata. This is a reminder to
verify updates before travel—not proof that the system is fully patched.

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

`./run.sh lockdown` performs a verified full radio lockdown through the
installed privileged helper. It disables NetworkManager Wi-Fi, RFKill-blocks
WLAN and Bluetooth, powers off an available Bluetooth controller when
possible, stops `bluetooth.service`, and returns nonzero unless final state
verification succeeds. Root-run actions write sanitized, owner-only logs under
`/var/log/fedora-radio-control/` and update `latest.log` there. The repository
`logs/` directory is retained only as a non-root mocked-test fixture.

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

Mutations are serialized with a root-owned runtime lock, so two radio-control
actions cannot interleave. Start the menu with `sudo` to review protected
action logs from option `6`.

For DEF CON deployment, install a reviewed release before using privileged
actions. A normal-user-owned Git checkout is suitable for development and
mocked tests, but it never supplies the mutation code executed after privilege
elevation. The root-owned installed helper loads only its own installed support
files with a controlled `PATH` and restrictive `umask`.

The Wi-Fi menu includes a Wi-Fi-only detailed view. A `HARDWARE BLOCKED`
constraint means the physical RFKill state must be cleared outside this
application before Wi-Fi can be enabled.
A verified one-time lockdown is not continuous enforcement: another
application, hardware event, suspend/resume cycle, or reboot can change radio
state afterward.
