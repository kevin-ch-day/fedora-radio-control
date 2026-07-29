"""Read-only report rendering, kept separate from command dispatch and menus."""

from __future__ import annotations

import os
import socket
from typing import Protocol

from .state import autoconnect_count, collect
from .system import EXIT_OK, EXIT_POLICY, EXIT_UNKNOWN, os_name


class ReportUI(Protocol):
    def heading(self, value: str) -> None: ...
    def section(self, value: str) -> None: ...
    def label(self, name: str, value: object) -> None: ...
    def note(self, value: str) -> None: ...
    def result(self, value: str) -> str: ...


def effective(value: str) -> str:
    if value == "disabled":
        return "DISABLED"
    if value == "unknown":
        return "STATE UNKNOWN"
    return "NOT FULLY DISABLED"


def rfkill_summary(items: list) -> str:
    if not items:
        return "NOT DETECTED"
    return "BLOCKED" if all(item.blocked for item in items) else "UNBLOCKED"


def render_rfkill(items: list) -> None:
    for item in items:
        print(f"\n  [{item.identifier}] {item.device}")
        print(f"      Soft blocked: {'yes' if item.soft == 'blocked' else 'no'}")
        print(f"      Hard blocked: {'yes' if item.hard == 'blocked' else 'no'}")


def vpn_text(connection) -> str:
    if connection.vpn_state == "active":
        return f"INFORMATIONAL ({connection.vpn_count} active; approx. {connection.vpn_duration})"
    if connection.vpn_state == "inactive":
        return "INFORMATIONAL (none detected)"
    return f"UNKNOWN ({connection.vpn_duration})"


def status(ui: ReportUI) -> int:
    state = collect()
    ui.heading("Fedora Radio Control")
    ui.section("System")
    ui.label("Fedora:", os_name())
    ui.label("Hostname:", socket.gethostname() or "unavailable")
    ui.label("User:", os.environ.get("USER", "unavailable"))

    ui.section("Wi-Fi")
    ui.label("NetworkManager radio:", state.wifi_radio)
    ui.label("RFKill devices:", len(state.wifi))
    if state.wifi:
        render_rfkill(state.wifi)
    else:
        ui.label("Hardware:", "NOT DETECTED")
    print()
    ui.label("Effective state:", effective(state.wifi_effective))

    ui.section("Bluetooth")
    ui.label("Service active:", state.bluetooth_active)
    ui.label("Service enabled:", state.bluetooth_enabled)
    controller = "ADAPTER UNAVAILABLE" if state.controller == "unavailable" else "NOT ASSESSED (bluetoothctl unavailable)" if state.controller == "tool-unavailable" else state.controller
    ui.label("Controller:", controller)
    ui.label("RFKill devices:", len(state.bluetooth))
    if state.bluetooth:
        render_rfkill(state.bluetooth)
    else:
        ui.label("Hardware:", "NOT DETECTED")
    print()
    ui.label("Effective state:", effective(state.bluetooth_effective))

    ui.section("Policy")
    ui.label("Result:", ui.result(state.policy))
    if state.policy != "LOCKED DOWN":
        ui.label("Reason:", state.reason())
    return EXIT_OK if state.policy == "LOCKED DOWN" else EXIT_UNKNOWN if state.policy == "STATE UNKNOWN" else EXIT_POLICY


def profiles(ui: ReportUI) -> int:
    count = autoconnect_count()
    if count is None:
        ui.label("Wi-Fi autoconnect profiles:", "UNKNOWN (query failed)")
        return EXIT_UNKNOWN
    ui.label("Wi-Fi autoconnect profiles:", "NONE" if count == 0 else f"REVIEW ({count} enabled; names omitted)")
    return EXIT_OK


def wifi_detail(ui: ReportUI) -> None:
    state = collect()
    ui.heading("Wi-Fi State")
    ui.label("NetworkManager radio:", state.wifi_radio)
    ui.label("RFKill devices:", len(state.wifi))
    if state.wifi:
        render_rfkill(state.wifi)
    else:
        ui.label("Hardware:", "NOT DETECTED")
    print()
    ui.label("Effective state:", effective(state.wifi_effective))
    ui.note("Enable does not select a network; saved profiles may reconnect according to NetworkManager policy.")


def bluetooth_detail(ui: ReportUI) -> None:
    state = collect()
    ui.heading("Bluetooth State")
    ui.label("Service active:", state.bluetooth_active)
    ui.label("Service enabled:", state.bluetooth_enabled)
    controller = "ADAPTER UNAVAILABLE" if state.controller == "unavailable" else "NOT ASSESSED (bluetoothctl unavailable)" if state.controller == "tool-unavailable" else state.controller
    ui.label("Controller:", controller)
    ui.label("RFKill devices:", len(state.bluetooth))
    if state.bluetooth:
        render_rfkill(state.bluetooth)
    else:
        ui.label("Hardware:", "NOT DETECTED")
    print()
    ui.label("Effective state:", effective(state.bluetooth_effective))
    if state.bluetooth_effective == "not fully disabled":
        blocker = state.reason() if state.wifi_effective == "disabled" else "Bluetooth service and radio state require review"
        ui.label("Policy blocker:", blocker)
