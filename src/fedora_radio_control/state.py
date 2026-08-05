"""Read-only radio and connection collection for the Python frontend."""

from __future__ import annotations

from dataclasses import dataclass, field
import json
import re
import shutil

from .system import elapsed, now, run


@dataclass(frozen=True)
class RFKill:
    identifier: str
    device: str
    soft: str
    hard: str

    @property
    def blocked(self) -> bool:
        return self.soft == "blocked" or self.hard == "blocked"


@dataclass
class State:
    wifi_radio: str = "unknown"
    wifi: list[RFKill] = field(default_factory=list)
    bluetooth: list[RFKill] = field(default_factory=list)
    bluetooth_active: str = "unknown"
    bluetooth_enabled: str = "unknown"
    controller: str = "unknown"
    powered: str = "unknown"
    discoverable: str = "unknown"
    pairable: str = "unknown"
    wifi_failed: bool = False
    bluetooth_failed: bool = False
    failed: bool = False

    @property
    def query_failed(self) -> bool:
        return self.failed or self.wifi_failed or self.bluetooth_failed

    @property
    def wifi_effective(self) -> str:
        if self.failed or self.wifi_failed:
            return "unknown"
        return "disabled" if self.wifi_radio == "disabled" and self.wifi and all(item.blocked for item in self.wifi) else "not fully disabled"

    @property
    def bluetooth_effective(self) -> str:
        if self.failed or self.bluetooth_failed:
            return "unknown"
        controller_secure = self.controller != "available" or (self.powered, self.discoverable, self.pairable) == ("no", "no", "no")
        return "disabled" if self.bluetooth_active == "inactive" and self.bluetooth and all(item.blocked for item in self.bluetooth) and controller_secure else "not fully disabled"

    @property
    def policy(self) -> str:
        if self.query_failed:
            return "STATE UNKNOWN"
        return "LOCKED DOWN" if self.wifi_effective == self.bluetooth_effective == "disabled" else "NOT LOCKED DOWN"

    def reason(self) -> str:
        if self.query_failed:
            return "one or more radio states could not be queried reliably"
        if self.wifi_effective != "disabled":
            if not self.wifi:
                return "Wi-Fi hardware was not detected"
            return f"NetworkManager Wi-Fi radio remains {self.wifi_radio}" if self.wifi_radio != "disabled" else "a Wi-Fi RFKill device remains unblocked"
        if not self.bluetooth:
            return "Bluetooth hardware was not detected"
        return f"bluetooth.service remains {self.bluetooth_active}" if self.bluetooth_active != "inactive" else "a Bluetooth RFKill device remains unblocked"


@dataclass(frozen=True)
class Connections:
    wifi_duration: str
    vpn_state: str
    vpn_count: int
    vpn_duration: str


def _rfkill() -> tuple[list[RFKill], list[RFKill], bool]:
    result = run(["rfkill", "--json"])
    if result.returncode:
        return [], [], True
    try:
        devices = json.loads(result.stdout)["rfkilldevices"]
    except (KeyError, TypeError, json.JSONDecodeError):
        return [], [], True
    wifi: list[RFKill] = []
    bluetooth: list[RFKill] = []
    failed = False
    for item in devices:
        if not isinstance(item, dict) or item.get("type") not in {"wlan", "bluetooth"}:
            continue
        values = (item.get("id", item.get("index")), item.get("device", item.get("name")), item.get("soft"), item.get("hard"))
        if any(value is None for value in values):
            failed = True
            continue
        parsed = RFKill(*(str(value) for value in values))
        (wifi if item["type"] == "wlan" else bluetooth).append(parsed)
    return wifi, bluetooth, failed


def collect() -> State:
    state = State()
    state.wifi, state.bluetooth, state.failed = _rfkill()
    wifi = run(["nmcli", "--terse", "--fields", "WIFI", "general", "status"])
    state.wifi_radio = wifi.stdout.strip() if wifi.returncode == 0 else "unknown"
    state.wifi_failed = state.wifi_radio not in {"enabled", "disabled"}
    active = run(["systemctl", "show", "bluetooth.service", "--property=ActiveState", "--value"])
    enabled = run(["systemctl", "show", "bluetooth.service", "--property=UnitFileState", "--value"])
    state.bluetooth_active = active.stdout.strip() if active.returncode == 0 else "unknown"
    state.bluetooth_enabled = enabled.stdout.strip() if enabled.returncode == 0 else "unknown"
    state.bluetooth_failed = active.returncode != 0 or enabled.returncode != 0
    if shutil.which("bluetoothctl") is None:
        state.controller = "tool-unavailable"
        return state
    # bluetoothctl can fail without output after bluetooth.service is stopped
    # because its D-Bus endpoint is intentionally absent. The stopped service
    # plus RFKill state remains sufficient disable evidence.
    if state.bluetooth_active == "inactive":
        state.controller = "unavailable"
        return state
    controller = run(["bluetoothctl", "--timeout", "2", "show"], timeout=4)
    output = f"{controller.stdout}\n{controller.stderr}"
    if "No default controller available" in output:
        state.controller = "unavailable"
        return state
    if controller.returncode or not re.search(r"^\s*Controller\s+[0-9A-Fa-f:]+\s+", output, re.MULTILINE):
        state.bluetooth_failed = True
        return state
    state.controller = "available"
    for attribute, label in (("powered", "Powered"), ("discoverable", "Discoverable"), ("pairable", "Pairable")):
        found = re.search(rf"^\s*{label}:\s*(yes|no)\s*$", output, re.MULTILINE)
        if found:
            setattr(state, attribute, found.group(1))
    return state


def connections() -> Connections:
    result = run(["nmcli", "--terse", "--fields", "TYPE,TIMESTAMP", "connection", "show", "--active"])
    if result.returncode:
        return Connections("unknown (query failed)", "unknown", 0, "unknown (query failed)")
    current = now()
    wifi_timestamp: int | None = None
    vpn_timestamps: list[int] = []
    for line in result.stdout.splitlines():
        kind, _, timestamp = line.partition(":")
        if not timestamp.isdigit():
            continue
        if kind in {"wifi", "802-11-wireless"} and wifi_timestamp is None:
            wifi_timestamp = int(timestamp)
        if kind in {"vpn", "wireguard", "tun", "ppp"}:
            vpn_timestamps.append(int(timestamp))
    wifi_duration = "not connected" if wifi_timestamp is None else elapsed(current - wifi_timestamp) if current >= wifi_timestamp else "unknown (timestamp invalid)"
    if not vpn_timestamps:
        return Connections(wifi_duration, "inactive", 0, "not connected")
    oldest = min(vpn_timestamps)
    return Connections(wifi_duration, "active", len(vpn_timestamps), elapsed(current - oldest) if current >= oldest else "unknown (timestamp invalid)")


def wifi_interface() -> tuple[str | None, bool]:
    result = run(["nmcli", "--terse", "--fields", "DEVICE,TYPE,STATE", "device", "status"])
    if result.returncode:
        return None, False
    for line in result.stdout.splitlines():
        parts = line.split(":", 2)
        if len(parts) == 3 and parts[1:] == ["wifi", "connected"]:
            return parts[0], True
    return None, True


def wifi_mac_privacy(interface: str | None, interface_known: bool) -> str:
    """Classify an active Wi-Fi MAC without retaining or displaying either address."""
    if not interface_known:
        return "unknown"
    if interface is None:
        return "not-applicable"
    result = run([
        "nmcli", "--terse", "--fields", "GENERAL.HWADDR,GENERAL.PERM-HWADDR",
        "device", "show", interface,
    ])
    if result.returncode:
        return "unknown"
    values: dict[str, str] = {}
    for line in result.stdout.splitlines():
        key, separator, value = line.partition(":")
        if separator and key in {"GENERAL.HWADDR", "GENERAL.PERM-HWADDR"}:
            values[key] = value.strip().casefold()
    current = values.get("GENERAL.HWADDR")
    permanent = values.get("GENERAL.PERM-HWADDR")
    if not current or not permanent:
        return "unknown"
    return "randomized" if current != permanent else "hardware"


def autoconnect_count() -> int | None:
    result = run(["nmcli", "--terse", "--fields", "TYPE,AUTOCONNECT", "connection", "show"])
    if result.returncode:
        return None
    return sum(1 for line in result.stdout.splitlines() if line.partition(":")[0] in {"wifi", "802-11-wireless"} and line.partition(":")[2] == "yes")
