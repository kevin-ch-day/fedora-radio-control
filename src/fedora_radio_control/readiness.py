"""Read-only conference posture checks, separated from command dispatch."""

from __future__ import annotations

import os
from typing import Protocol
import time

from .reports import vpn_text
from .state import autoconnect_count, collect, connections, wifi_interface
from .system import EXIT_OK, EXIT_POLICY, EXIT_UNKNOWN, exists, run


class ReadinessUI(Protocol):
    def heading(self, value: str) -> None: ...
    def label(self, name: str, value: object) -> None: ...
    def note(self, value: str) -> None: ...


def _wireless_zone(interface: str) -> str:
    result = run(["firewall-cmd", f"--get-zone-of-interface={interface}"])
    zone = result.stdout.strip()
    if result.returncode or not zone or zone == "no zone":
        default = run(["firewall-cmd", "--get-default-zone"])
        return "UNKNOWN (zone query failed)" if default.returncode else f"REVIEW ({default.stdout.strip()}, default)"
    if zone in {"trusted", "home", "work", "internal"}:
        return f"FAIL ({zone} is permissive for conference Wi-Fi)"
    if zone in {"public", "external", "block", "drop"}:
        return f"PASS ({zone})"
    return f"REVIEW ({zone})"


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


def report(ui: ReadinessUI) -> int:
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
    bluetooth = "FAIL (service remains active)" if service.startswith("FAIL") else "PASS" if controller == "PASS" or controller.startswith("NOT APPLICABLE") else "REVIEW (controller not assessed)" if controller.startswith("REVIEW") else controller
    firewall = "PASS" if exists("firewall-cmd") and run(["firewall-cmd", "--state"]).returncode == 0 else "FAIL" if exists("firewall-cmd") else "UNKNOWN"
    zone = "NOT APPLICABLE" if interface is None and interface_known else "UNKNOWN (interface not verified)" if not interface_known else _wireless_zone(interface)

    ui.heading("DEF CON Readiness")
    ui.label("Radio lockdown:", radio)
    ui.label("Bluetooth service:", service)
    ui.label("Bluetooth controller exposure:", controller)
    ui.label("Bluetooth overall posture:", bluetooth)
    ui.label("Active wireless link:", f"REVIEW ({interface})" if interface else "NONE" if interface_known else "UNKNOWN (query failed)")
    ui.label("Wireless zone:", zone)
    ui.label("Wi-Fi autoconnect:", "UNKNOWN (query failed)" if autoconnect is None else "PASS (none enabled)" if autoconnect == 0 else f"REVIEW ({autoconnect} enabled; names omitted)")
    ui.label("Firewall service:", firewall)
    ui.label("VPN detected:", vpn_text(connection))
    ui.label("Kernel patch freshness:", _kernel_age())
    ui.label("Device hygiene:", "REVIEW (patch before travel; use a purpose-limited device)")
    ui.label("Unexpected adapters:", "REVIEW (baseline not recorded)")
    print()
    unknown = any((radio == "UNKNOWN", bluetooth == "UNKNOWN", firewall == "UNKNOWN", connection.vpn_state == "unknown", not interface_known, autoconnect is None, zone.startswith("UNKNOWN")))
    failed = any((radio == "FAIL", bluetooth.startswith("FAIL"), firewall == "FAIL", zone.startswith("FAIL")))
    ui.label("Overall:", "STATE UNKNOWN" if unknown else "NOT READY" if failed else "READY WITH REVIEW ITEMS" if radio == bluetooth == "PASS" else "NOT READY")
    if failed and radio == "FAIL":
        ui.note("Recommended action: apply full radio lockdown (main-menu option 2).")
    return EXIT_UNKNOWN if unknown else EXIT_POLICY if failed or radio != "PASS" or bluetooth != "PASS" else EXIT_OK
