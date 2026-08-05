"""Passive local host-exposure checks for the conference readiness report."""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Callable

from .system import Result, exists, run


@dataclass(frozen=True)
class ListenerExposure:
    known: bool
    total: int = 0
    network_visible: int = 0


@dataclass(frozen=True)
class ScreenLock:
    known: bool
    lock_enabled: bool = False
    idle_delay: int = 0
    lock_delay: int = 0


def _loopback(address: str) -> bool:
    host = address.rsplit(":", 1)[0].strip("[]")
    return host == "::1" or host.startswith("127.") or host == "localhost"


def _gsettings_integer(value: str) -> int | None:
    found = re.fullmatch(r"(?:uint32\s+)?(\d+)\s*", value)
    return int(found.group(1)) if found else None


class HostInspector:
    """Passive local collector for host exposure and desktop posture state."""

    def __init__(
        self,
        command_exists: Callable[[str], bool] | None = None,
        command_run: Callable[..., Result] | None = None,
    ) -> None:
        self._exists = command_exists or exists
        self._run = command_run or run

    def listening_sockets(self) -> ListenerExposure:
        """Count local TCP/UDP listeners without retaining ports, addresses, or processes."""
        if not self._exists("ss"):
            return ListenerExposure(False)
        result = self._run(["ss", "--no-header", "--listening", "--numeric", "--tcp", "--udp"])
        if result.returncode:
            return ListenerExposure(False)
        total = 0
        network_visible = 0
        for line in result.stdout.splitlines():
            fields = line.split()
            if len(fields) < 5:
                return ListenerExposure(False)
            total += 1
            if not _loopback(fields[4]):
                network_visible += 1
        return ListenerExposure(True, total, network_visible)

    def selinux_state(self) -> str:
        """Return only the SELinux enforcement mode, never policy details or audit data."""
        if not self._exists("getenforce"):
            return "unknown"
        result = self._run(["getenforce"])
        state = result.stdout.strip().casefold()
        return state if result.returncode == 0 and state in {"enforcing", "permissive", "disabled"} else "unknown"

    def screen_lock(self) -> ScreenLock:
        """Read GNOME's auto-lock posture without reading user content or changing settings."""
        if not self._exists("gsettings"):
            return ScreenLock(False)
        lock = self._run(["gsettings", "get", "org.gnome.desktop.screensaver", "lock-enabled"], timeout=2)
        idle = self._run(["gsettings", "get", "org.gnome.desktop.session", "idle-delay"], timeout=2)
        delay = self._run(["gsettings", "get", "org.gnome.desktop.screensaver", "lock-delay"], timeout=2)
        if lock.returncode or idle.returncode or delay.returncode:
            return ScreenLock(False)
        idle_seconds = _gsettings_integer(idle.stdout.strip())
        lock_seconds = _gsettings_integer(delay.stdout.strip())
        if lock.stdout.strip().casefold() not in {"true", "false"} or idle_seconds is None or lock_seconds is None:
            return ScreenLock(False)
        return ScreenLock(True, lock.stdout.strip().casefold() == "true", idle_seconds, lock_seconds)


def listening_sockets() -> ListenerExposure:
    """Compatibility wrapper for the default passive host inspector."""
    return HostInspector().listening_sockets()


def selinux_state() -> str:
    """Compatibility wrapper for the default passive host inspector."""
    return HostInspector().selinux_state()


def screen_lock() -> ScreenLock:
    """Compatibility wrapper for the default passive host inspector."""
    return HostInspector().screen_lock()
