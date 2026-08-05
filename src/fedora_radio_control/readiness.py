"""Read-only conference posture checks, separated from command dispatch."""

from __future__ import annotations

from dataclasses import dataclass, field
import os
from typing import Protocol
import time

from .reports import vpn_text
from .host import HostInspector, ListenerExposure, ScreenLock
from .state import Connections, autoconnect_count, collect, connections, wifi_interface, wifi_mac_privacy
from .system import EXIT_OK, EXIT_POLICY, EXIT_UNKNOWN, exists, run
from .vpn import NordVPNInspector, nordvpn_readiness, nordvpn_technology


class ReadinessUI(Protocol):
    def heading(self, value: str) -> None: ...
    def label(self, name: str, value: object) -> None: ...
    def note(self, value: str) -> None: ...


def _zone_posture(zone: str, source: str = "") -> str:
    suffix = f"; {source}" if source else ""
    if zone in {"trusted", "home", "work", "internal"}:
        return f"FAIL ({zone} is permissive for conference Wi-Fi{suffix})"
    if zone in {"public", "external", "block", "drop"}:
        return f"PASS ({zone}{suffix})"
    return f"REVIEW ({zone}{suffix})"


def _wireless_zone(interface: str) -> str:
    result = run(["firewall-cmd", f"--get-zone-of-interface={interface}"])
    zone = result.stdout.strip()
    if not result.returncode and zone and zone != "no zone":
        return _zone_posture(zone)
    default = run(["firewall-cmd", "--get-default-zone"])
    if default.returncode or not default.stdout.strip():
        return "UNKNOWN (zone query failed)"
    return _zone_posture(default.stdout.strip(), "default zone")


def _vpn_posture(connection: Connections, interface: str | None, interface_known: bool) -> str:
    """Describe observed VPN presence without claiming full-tunnel verification."""
    if not interface_known:
        return "UNKNOWN (wireless interface query failed)"
    if interface is None:
        return "NOT APPLICABLE (no active Wi-Fi)"
    if connection.vpn_state == "active":
        return "REVIEW (active VPN detected; routing and DNS not verified)"
    if connection.vpn_state == "inactive":
        return "REVIEW (no active VPN detected)"
    return "UNKNOWN (VPN query failed)"


def _selinux_posture(state: str) -> str:
    if state == "enforcing":
        return "PASS (enforcing)"
    if state in {"permissive", "disabled"}:
        return f"FAIL ({state})"
    return "UNKNOWN (mode unavailable)"


def _listener_posture(exposure: ListenerExposure) -> str:
    if not exposure.known:
        return "UNKNOWN (listener query unavailable)"
    if exposure.network_visible == 0:
        return "PASS (none detected)"
    return f"REVIEW ({exposure.network_visible} network-visible; details omitted)"


def _mac_privacy_posture(value: str) -> str:
    if value == "randomized":
        return "PASS (active address differs from hardware address)"
    if value == "hardware":
        return "REVIEW (active hardware address)"
    if value == "not-applicable":
        return "NOT APPLICABLE (no active Wi-Fi)"
    return "UNKNOWN (address comparison unavailable)"


def _screen_lock_posture(lock: ScreenLock) -> str:
    if not lock.known:
        return "NOT APPLICABLE (GNOME setting unavailable)"
    if not lock.lock_enabled:
        return "FAIL (screen lock disabled)"
    if lock.idle_delay == 0:
        return "FAIL (automatic idle lock disabled)"
    if lock.lock_delay > 60:
        return f"REVIEW (locks {lock.lock_delay}s after idle activation)"
    return f"PASS (idle {lock.idle_delay}s; lock delay {lock.lock_delay}s)"


def _kernel_age() -> str:
    if not exists("rpm"):
        return "REVIEW (rpm unavailable)"
    result = run(["rpm", "-q", "--qf", "%{INSTALLTIME}", f"kernel-core-{os.uname().release}"])
    if result.returncode or not result.stdout.strip().isdigit():
        return "REVIEW (running kernel package not verified)"
    installed = int(result.stdout.strip())
    current = int(time.time())
    if current < installed:
        return "REVIEW (running kernel package timestamp is invalid)"
    return f"REVIEW (running kernel package installed {(current - installed) // 86400} days ago; update status not verified)"


@dataclass(frozen=True)
class ReadinessAssessment:
    """Immutable, privacy-safe result of one complete readiness evaluation."""

    radio: str
    bluetooth_service: str
    bluetooth_controller: str
    bluetooth: str
    wireless_link: str
    wireless_zone: str
    autoconnect: str
    firewall: str
    selinux: str
    listeners: str
    mac_privacy: str
    desktop_lock: str
    vpn_detected: str
    vpn: str
    nordvpn_client: str
    nordvpn_technology: str
    kernel: str
    hygiene: str
    adapters: str

    @property
    def unknown(self) -> bool:
        return any((
            self.radio == "UNKNOWN",
            self.bluetooth == "UNKNOWN",
            self.firewall == "UNKNOWN",
            self.selinux.startswith("UNKNOWN"),
            self.listeners.startswith("UNKNOWN"),
            self.mac_privacy.startswith("UNKNOWN"),
            self.vpn.startswith("UNKNOWN"),
            self.nordvpn_client.startswith("UNKNOWN"),
            self.wireless_link.startswith("UNKNOWN"),
            self.autoconnect.startswith("UNKNOWN"),
            self.wireless_zone.startswith("UNKNOWN"),
        ))

    @property
    def failed(self) -> bool:
        return any((
            self.radio == "FAIL",
            self.bluetooth.startswith("FAIL"),
            self.firewall == "FAIL",
            self.selinux.startswith("FAIL"),
            self.desktop_lock.startswith("FAIL"),
            self.wireless_zone.startswith("FAIL"),
        ))

    @property
    def overall(self) -> str:
        if self.unknown:
            return "STATE UNKNOWN"
        if self.failed:
            return "NOT READY"
        return "READY WITH REVIEW ITEMS" if self.radio == self.bluetooth == "PASS" else "NOT READY"

    @property
    def exit_code(self) -> int:
        if self.unknown:
            return EXIT_UNKNOWN
        return EXIT_POLICY if self.failed or self.radio != "PASS" or self.bluetooth != "PASS" else EXIT_OK

    @property
    def requires_lockdown(self) -> bool:
        return self.failed and self.radio == "FAIL"

    def rows(self) -> tuple[tuple[str, str], ...]:
        return (
            ("Radio lockdown:", self.radio),
            ("Bluetooth service:", self.bluetooth_service),
            ("Bluetooth controller exposure:", self.bluetooth_controller),
            ("Bluetooth overall posture:", self.bluetooth),
            ("Active wireless link:", self.wireless_link),
            ("Wireless zone:", self.wireless_zone),
            ("Wi-Fi autoconnect:", self.autoconnect),
            ("Firewall service:", self.firewall),
            ("SELinux:", self.selinux),
            ("Network-visible listeners:", self.listeners),
            ("Wi-Fi MAC privacy:", self.mac_privacy),
            ("Desktop auto-lock:", self.desktop_lock),
            ("VPN detected:", self.vpn_detected),
            ("VPN posture:", self.vpn),
            ("NordVPN client:", self.nordvpn_client),
            ("NordVPN technology:", self.nordvpn_technology),
            ("Kernel patch freshness:", self.kernel),
            ("Device hygiene:", self.hygiene),
            ("Unexpected adapters:", self.adapters),
        )


class ReadinessEvaluator:
    """Collect local state and convert it into one immutable readiness assessment."""

    def __init__(
        self,
        host_inspector: HostInspector | None = None,
        nordvpn_inspector: NordVPNInspector | None = None,
    ) -> None:
        self._host = host_inspector or HostInspector()
        self._nordvpn = nordvpn_inspector or NordVPNInspector()

    def assess(self) -> ReadinessAssessment:
        state, connection = collect(), connections()
        interface, interface_known = wifi_interface()
        autoconnect = autoconnect_count()
        radio = "PASS" if state.policy == "LOCKED DOWN" else "UNKNOWN" if state.policy == "STATE UNKNOWN" else "FAIL"
        service = "PASS (inactive)" if state.bluetooth_active == "inactive" else f"FAIL ({state.bluetooth_active})"
        if state.controller == "unavailable":
            controller = "NOT APPLICABLE (no controller)"
        elif state.controller == "tool-unavailable":
            controller = "REVIEW (bluetoothctl unavailable)"
        elif state.controller == "available":
            controller = "PASS" if (state.powered, state.discoverable, state.pairable) == ("no", "no", "no") else "FAIL"
        else:
            controller = "UNKNOWN"
        bluetooth = (
            "FAIL (service remains active)" if service.startswith("FAIL") else "PASS"
            if controller == "PASS" or controller.startswith("NOT APPLICABLE") else
            "REVIEW (controller not assessed)" if controller.startswith("REVIEW") else controller
        )
        firewall = "PASS" if exists("firewall-cmd") and run(["firewall-cmd", "--state"]).returncode == 0 else "FAIL" if exists("firewall-cmd") else "UNKNOWN"
        zone = "NOT APPLICABLE" if interface is None and interface_known else "UNKNOWN (interface not verified)" if not interface_known else _wireless_zone(interface)
        nordvpn = self._nordvpn.collect()
        return ReadinessAssessment(
            radio=radio,
            bluetooth_service=service,
            bluetooth_controller=controller,
            bluetooth=bluetooth,
            wireless_link=f"REVIEW ({interface})" if interface else "NONE" if interface_known else "UNKNOWN (query failed)",
            wireless_zone=zone,
            autoconnect="UNKNOWN (query failed)" if autoconnect is None else "PASS (none enabled)" if autoconnect == 0 else f"REVIEW ({autoconnect} enabled; names omitted)",
            firewall=firewall,
            selinux=_selinux_posture(self._host.selinux_state()),
            listeners=_listener_posture(self._host.listening_sockets()),
            mac_privacy=_mac_privacy_posture(wifi_mac_privacy(interface, interface_known)),
            desktop_lock=_screen_lock_posture(self._host.screen_lock()),
            vpn_detected=vpn_text(connection),
            vpn=_vpn_posture(connection, interface, interface_known),
            nordvpn_client=nordvpn_readiness(nordvpn),
            nordvpn_technology=nordvpn_technology(nordvpn),
            kernel=_kernel_age(),
            hygiene="REVIEW (patch before travel; use a purpose-limited device)",
            adapters="REVIEW (baseline not recorded)",
        )


@dataclass
class ReadinessReport:
    """Render a readiness assessment without coupling policy to terminal output."""

    ui: ReadinessUI
    evaluator: ReadinessEvaluator = field(default_factory=ReadinessEvaluator)

    def render(self) -> int:
        assessment = self.evaluator.assess()
        self.ui.heading("DEF CON Readiness")
        for name, value in assessment.rows():
            self.ui.label(name, value)
        print()
        self.ui.label("Overall:", assessment.overall)
        if assessment.requires_lockdown:
            self.ui.note("Recommended action: apply full radio lockdown (main-menu option 2).")
        return assessment.exit_code


def report(ui: ReadinessUI) -> int:
    """Retain the simple public function while using the object-oriented model."""
    return ReadinessReport(ui).render()
