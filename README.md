# fedora-radio-control

`fedora-radio-control` is a small, auditable command-line utility for
reporting Wi-Fi and Bluetooth lockdown state on Fedora Linux laptops.

The public application is now a dependency-free Python frontend. `run.sh`
remains the only supported entry point and starts that frontend; the reviewed
Bash runtime remains temporarily inside the installed, root-owned helper for
the narrow set of verified radio mutations. This staged migration keeps the
privilege boundary stable while read-only state collection, reports, menus,
and command dispatch move to typed Python modules.

## Current milestone

The application reports NetworkManager Wi-Fi state, WLAN and Bluetooth RFKill
devices, Bluetooth service state, and Bluetooth controller availability. It
can apply verified full radio lockdown plus focused Wi-Fi and Bluetooth
disable actions; it does not change saved NetworkManager profiles, paired
devices, firewall rules, or systemd boot settings.

The Python package contains the terminal display, optional color, safe
confirmations, and numbered menus. `status` does not invoke menus or prompts.
The remaining Bash files are isolated to the privileged helper runtime and do
not collect credentials.

## Requirements

- Fedora Linux
- Python 3.10 or newer (standard library only)
- Bash (only for the installed privileged mutation helper)
- `nmcli`, `rfkill`, and `systemctl`
- `bluetoothctl` is optional. When present, the tool reports controller
  exposure and powers down an available controller during Bluetooth disable.

## Usage

```bash
./run.sh
./run.sh status
./run.sh readiness
./run.sh vpn
./run.sh wifi profiles
./run.sh --help

# Verified state-changing actions (the helper requests sudo only when needed)
./run.sh lockdown  # requires typing APPLY-LOCKDOWN

# Only for reviewed, non-interactive automation
./run.sh lockdown --non-interactive

# Wi-Fi controls (enable requires an interactive typed confirmation)
./run.sh wifi disable
./run.sh wifi enable

# Bluetooth controls (enable and controller power-on require confirmation)
./run.sh bluetooth disable
./run.sh bluetooth enable
./run.sh bluetooth power off
./run.sh bluetooth power on

# Read a concise, root-protected action history
./run.sh activity
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

If the dashboard shows `NOT ACCESSIBLE` for the privileged component, its
directory cannot be inspected by the normal user. Repair that installation
with `sudo ./install.sh`; a healthy installed directory is root-owned mode
`0755`, the public version metadata is mode `0644`, and the supporting
mutation modules remain root-readable only.
The same install step prunes superseded, root-owned helper display modules
from prior releases; it never removes user files or action logs.

`VERSION` is the installed-helper compatibility protocol, not the Python
package version. It advances whenever the reviewed runtime or its installation
contract changes, so a dashboard can require a reinstall instead of treating
an older helper as current.

Action logs are root-protected under `/var/log/fedora-radio-control/`. Each
log uses a stable `key=value` schema with action metadata, timestamped state
snapshots, command outcomes, and a final verified result. Values are sanitized
before writing; the application does not log SSIDs, profile names, addresses,
VPN endpoints, peers, or command output. To review a concise action history:

```bash
./run.sh activity
```

For full detail, use `sudo tail -n 80 /var/log/fedora-radio-control/latest.log`.

`run.sh` is the sole supported public entry point. It resolves the repository
path and starts the Python package from `src/`. Running `./run.sh` with no
arguments opens the menu, which refreshes live state before each action.
Bluetooth controls provide verified full disable, explicit full enable, and
separate controller power on/off actions; no menu item is a placeholder.
`run.sh` refuses root before loading the Python package from the checkout.
Use `./run.sh` as your normal user; approved actions elevate only through the
installed root-owned helper.
Press `Ctrl-C` at any prompt or during a read-only operation to exit cleanly
with status `130`; the frontend makes no further changes after interruption.

Run the application as `./run.sh`, never `sudo ./run.sh`. When an approved
radio action needs privileges, the normal-user frontend invokes the fixed
installed helper through `sudo` and prompts for your password as needed.
`sudo ./install.sh` is only needed to install or update that helper.
On success, the installer reports its staged/deployed file count, compatibility
protocol, verified runtime and log protection, plus the normal-user launch
command.

The Python frontend and reviewed Bash entry points share the same industrial
terminal palette: red FRC identity, cyan operational signals, green verified
results, yellow review warnings, and red errors. Bash output honors `NO_COLOR`
and `TERM=dumb`, and automatically remains plain when it is not connected to a
terminal. Logs always remain uncolored key/value records.

## Internal layout

The Python frontend is split by responsibility:

```text
pyproject.toml                  # standard Python packaging metadata
src/fedora_radio_control/system.py    # fixed-vector process execution and helper validation
src/fedora_radio_control/state.py     # RFKill JSON, radio, Wi-Fi, and VPN state
src/fedora_radio_control/host.py      # passive host exposure and desktop-lock inspection
src/fedora_radio_control/vpn.py       # privacy-safe optional NordVPN inspection
src/fedora_radio_control/readiness.py # conference posture checks
src/fedora_radio_control/reports.py   # detailed radio and profile reports
src/fedora_radio_control/ui.py        # terminal rendering and prompts
src/fedora_radio_control/menus.py     # interactive menu controller
src/fedora_radio_control/cli.py       # thin public command dispatcher
```

The following Bash tree is retained only for the installed privileged runtime
while its mutation paths are migrated separately:

```text
privileged/bash/helper.sh       # installed root-owned helper entry point
privileged/bash/wifi/           # verified Wi-Fi mutation and state helpers
privileged/bash/bluetooth/      # verified Bluetooth mutation and state helpers
privileged/bash/lib/            # helper policy, locking, and log support
```

These are internal modules; use `./run.sh` for normal operation.

See [the architecture guide](docs/architecture.md) for the Python/privileged
runtime boundary and the repository layout.

Menu option `7` clears the interactive terminal and redraws the current menu.
Normal menu refreshes do not clear the screen, so terminal scrollback and
`sudo` prompts do not leave a large blank gap. Clear-screen control characters
are never emitted when output is redirected.

Interactive terminals use a restrained industrial console theme: a stark
`[ FRC ]` masthead, graphite broken-line dividers, white subsystem headers,
cyan controls, green verified-safe states, amber review states, and red
exposure/alert markers. Main policy results also carry explicit `[ SAFE ]`,
`[ REVIEW ]`, or `[ ALERT ]` badges, so meaning remains visible without
color. It is functional color rather than a signal of policy success; always
read the text. Color is automatically omitted from redirected output and can
be disabled with `NO_COLOR=1 ./run.sh`.

The menu exits safely without changing anything if input closes (for example,
with Ctrl+D).

The Wi-Fi submenu includes a read-only saved-profile autoconnect inspection.
Wi-Fi enable requires a typed terminal confirmation because it can allow saved
profiles to reconnect. Bluetooth enable requires `ENABLE-BLUETOOTH`; it
runtime-unmasks and starts `bluetooth.service`, unblocks Bluetooth RFKill where
possible, powers on an available controller, and fails unless final state is
verified. Controller power is separate from service/RFKill state: power-on
requires `POWER-ON-BLUETOOTH`, while power-off does not. `sudo` is required
only for state-changing commands.

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
running when available, evaluates the assigned wireless firewall zone (or its
default zone when an active interface has no explicit assignment), counts
saved Wi-Fi profiles with autoconnect enabled without showing their names, and
labels incomplete checks as `REVIEW` or `UNKNOWN`. A failed required query
produces `STATE UNKNOWN`; it is never silently shown as a safe or absent
condition.
It also checks the local SELinux enforcement mode and counts network-visible
TCP/UDP listeners using only the local `ss` table. Listener addresses, ports,
processes, and peers are intentionally omitted, and the check sends no network
traffic or probes. A listener is a review item; disabled or permissive SELinux
is a readiness failure for a conference-connected device.
For an active Wi-Fi link, it also compares the active and permanent interface
MAC addresses without retaining or displaying either value. A changed address
is a privacy-positive signal; a hardware address is a review item, not proof
of compromise. The application never modifies NetworkManager MAC-randomization
settings or reconnects the interface.
On Fedora Workstation's GNOME desktop, the report also checks only the screen
lock, idle-delay, and lock-delay settings. Disabled screen locking or disabled
idle activation fails readiness; an unavailable GNOME settings service is
reported as not applicable rather than guessed. The application never changes
desktop preferences.
When Wi-Fi is active, VPN posture is deliberately advisory: the app can detect
an active NetworkManager VPN connection but does not claim to verify a full
tunnel, DNS routing, or IPv6 leak protection.
When the optional NordVPN CLI is installed, the readiness report also reads its
status and only the tunnel technology plus Kill Switch, auto-connect, routing,
LAN-discovery, and Meshnet settings. It never retains, displays, or writes
server, IP, DNS, account, or transfer details. The report is observational; it
does not connect, disconnect, or change NordVPN settings. It also does not
audit NordVPN allowlists, which can intentionally bypass the VPN and Kill
Switch for selected traffic; review those settings directly before using an
untrusted network.
`./run.sh vpn` and main-menu option `8` provide the same focused, read-only
NordVPN review. They report only connection state, tunnel technology, and the
security-relevant settings; they never print connection destinations or
allowlist entries.
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

The dashboard and readiness view report whether NetworkManager sees active VPN
connections and their approximate duration. They intentionally show neither
VPN profile names, endpoints, peers, nor addresses. Wi-Fi link duration is
similarly shown only while a Wi-Fi connection is active and never includes its
SSID. These are passive observations; the application does not create, stop,
or reconfigure VPN connections.

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

The test checks Bash and Python syntax, required files, executable permissions, help and
invalid-command behavior, and ensures the entry point has no radio mutation
commands. It also runs hardware-independent policy fixtures for RFKill,
Bluetooth service, missing-adapter, and query-failure behavior. If installed,
ShellCheck is run as an additional check; otherwise it is reported as skipped.

## Limitations

`./run.sh lockdown` requires an interactive typed confirmation before it
performs a verified full radio lockdown through the
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
cleared at reboot; Bluetooth restoration is deliberately outside this
application until a verified recovery path exists. Final state verification is
authoritative. Read-only status calls do not create logs, and no
persistent systemd boot-time changes are made. NetworkManager may retain its
Wi-Fi radio preference across a NetworkManager restart or reboot; use the
explicit Wi-Fi enable action when reopening that radio is intended.

Mutations are serialized with a root-owned runtime lock, so two radio-control
actions cannot interleave. Option `6` and `./run.sh activity` request sudo
only to produce a concise, root-protected activity summary.
`lockdown --non-interactive` is intentionally available only for reviewed
automation; it bypasses the typed confirmation but retains the same privileged
verification and logging transaction. It uses `sudo -n`, so automation must
already have a non-prompting sudo authorization; this installer never creates
one.

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
