"""Read-only VPN posture collection with privacy-preserving NordVPN support."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from .system import Result, exists, run


@dataclass(frozen=True)
class NordVPNPosture:
    available: bool
    status: str = "unknown"
    technology: str = "unknown"
    kill_switch: str = "unknown"
    auto_connect: str = "unknown"
    routing: str = "unknown"
    lan_discovery: str = "unknown"
    meshnet: str = "unknown"


def _field(output: str, label: str) -> str:
    for line in output.splitlines():
        key, separator, value = line.partition(":")
        if separator and key.strip().casefold() == label.casefold():
            return value.strip().casefold()
    return "unknown"


class NordVPNInspector:
    """Read only the small, privacy-safe subset of NordVPN client state we use."""

    def __init__(
        self,
        command_exists: Callable[[str], bool] | None = None,
        command_run: Callable[..., Result] | None = None,
    ) -> None:
        self._exists = command_exists or exists
        self._run = command_run or run

    def collect(self) -> NordVPNPosture:
        """Collect only status booleans; never retain NordVPN connection metadata."""
        if not self._exists("nordvpn"):
            return NordVPNPosture(False)
        status = self._run(["nordvpn", "status"], timeout=4)
        settings = self._run(["nordvpn", "settings"], timeout=4)
        return NordVPNPosture(
            available=True,
            status=_field(status.stdout, "Status") if status.returncode == 0 else "unknown",
            technology=_field(settings.stdout, "Technology") if settings.returncode == 0 else "unknown",
            kill_switch=_field(settings.stdout, "Kill Switch") if settings.returncode == 0 else "unknown",
            auto_connect=_field(settings.stdout, "Auto-connect") if settings.returncode == 0 else "unknown",
            routing=_field(settings.stdout, "Routing") if settings.returncode == 0 else "unknown",
            lan_discovery=_field(settings.stdout, "LAN Discovery") if settings.returncode == 0 else "unknown",
            meshnet=_field(settings.stdout, "Meshnet") if settings.returncode == 0 else "unknown",
        )


def nordvpn_posture() -> NordVPNPosture:
    """Compatibility wrapper for the default read-only NordVPN inspector."""
    return NordVPNInspector().collect()


def nordvpn_technology(posture: NordVPNPosture) -> str:
    """Render the privacy-safe tunnel technology reported by the local client."""
    if not posture.available:
        return "NOT DETECTED"
    if posture.technology == "nordlynx":
        return "NORDLYNX (WireGuard-based)"
    if posture.technology == "openvpn":
        return "OPENVPN"
    return "UNKNOWN"


def nordvpn_connection(posture: NordVPNPosture) -> str:
    """Render connection state without retaining a server, endpoint, or address."""
    if not posture.available:
        return "NOT DETECTED"
    if posture.status == "connected":
        return "PASS (connected)"
    if posture.status == "disconnected":
        return "REVIEW (disconnected)"
    return "UNKNOWN (status unavailable)"


def nordvpn_setting(value: str, desired: str) -> str:
    """Render a setting without conflating an unavailable query with a value."""
    if value == "unknown":
        return "UNKNOWN (not verified)"
    if value == desired:
        return f"PASS ({value})"
    return f"REVIEW ({value})"


def nordvpn_readiness(posture: NordVPNPosture) -> str:
    if not posture.available:
        return "NOT DETECTED"
    if posture.status == "connected":
        concerns: list[str] = []
        if posture.kill_switch == "disabled":
            concerns.append("kill switch disabled")
        elif posture.kill_switch != "enabled":
            concerns.append("kill switch not verified")
        if posture.auto_connect == "disabled":
            concerns.append("auto-connect disabled")
        elif posture.auto_connect != "enabled":
            concerns.append("auto-connect not verified")
        if posture.routing == "disabled":
            concerns.append("routing disabled")
        elif posture.routing != "enabled":
            concerns.append("routing not verified")
        if posture.lan_discovery == "enabled":
            concerns.append("LAN discovery enabled")
        elif posture.lan_discovery != "disabled":
            concerns.append("LAN discovery not verified")
        if posture.meshnet == "enabled":
            concerns.append("Meshnet enabled")
        return "PASS (connected; safety settings observed)" if not concerns else f"REVIEW (connected; {'; '.join(concerns)})"
    if posture.status == "disconnected":
        return "REVIEW (installed, disconnected)"
    return "UNKNOWN (NordVPN status unavailable)"
