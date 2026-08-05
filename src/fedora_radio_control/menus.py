"""Interactive menu controller; it delegates all mutations to the installed helper."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys

from . import readiness, reports
from .operations import PrivilegedOperation
from .state import autoconnect_count, collect, connections, wifi_interface
from .system import EXIT_OK, component_status, delegate
from .ui import UI


@dataclass(frozen=True)
class MenuController:
    ui: UI
    repository: Path

    def _main_menu(self) -> int | None:
        state, connection = collect(), connections()
        interface, interface_known = wifi_interface()
        profiles = autoconnect_count()
        self.ui.heading("Fedora Radio Control")
        self.ui.note("DEF CON // RADIO EXPOSURE POSTURE // LIVE")
        print()
        self.ui.label("Policy:", self.ui.result(state.policy))
        if state.policy != "LOCKED DOWN":
            self.ui.label("Primary blocker:", state.reason())
        self.ui.rule()
        self.ui.section("Wi-Fi")
        self.ui.label("Radio:", state.wifi_radio)
        self.ui.label("RFKill:", reports.rfkill_summary(state.wifi))
        self.ui.label("Hardware block:", "present — lockdown compatible" if any(item.hard == "blocked" for item in state.wifi) else "not present")
        self.ui.label("Active link:", f"CONNECTED ({interface})" if interface else "none" if interface_known else "UNKNOWN (query failed)")
        self.ui.label("Link duration:", connection.wifi_duration)
        self.ui.label("Autoconnect profiles:", "UNKNOWN (query failed)" if profiles is None else "none enabled" if profiles == 0 else f"REVIEW ({profiles} enabled; names omitted)")
        self.ui.section("Bluetooth")
        self.ui.label("Service:", state.bluetooth_active)
        self.ui.label("RFKill:", reports.rfkill_summary(state.bluetooth))
        self.ui.label("Controller:", state.controller)
        self.ui.section("System")
        status = component_status(self.repository)
        self.ui.label("Privileged component:", "INSTALLED AND VERIFIED" if status == "INSTALLED" else status)
        self.ui.label("VPN detected:", reports.vpn_text(connection))
        self.ui.rule()
        for option in ("[1] Show detailed radio status", "[2] Apply full radio lockdown (confirmation required)", "[3] Wi-Fi controls", "[4] Bluetooth controls", "[5] DEF CON readiness check", "[6] Show recent activity", "[7] Clear screen", "[8] NordVPN privacy posture", "[0] Exit"):
            self.ui.option(option)
        self.ui.rule()
        return self.ui.select(0, 8)

    def _wifi_menu(self) -> int | None:
        state, connection = collect(), connections()
        interface, known = wifi_interface()
        self.ui.heading("Wi-Fi Controls")
        self.ui.label("Current state:", reports.effective(state.wifi_effective))
        self.ui.label("NetworkManager:", state.wifi_radio)
        self.ui.label("RFKill:", reports.rfkill_summary(state.wifi))
        self.ui.label("Active link:", f"CONNECTED ({interface})" if interface else "none" if known else "UNKNOWN (query failed)")
        self.ui.label("Link duration:", connection.wifi_duration)
        if any(item.hard == "blocked" for item in state.wifi):
            self.ui.label("Hardware constraint:", "HARDWARE BLOCKED")
        self.ui.rule()
        for option in ("[1] Show detailed Wi-Fi state", "[2] Review saved profile autoconnect status", "[3] Disable and RFKill-block Wi-Fi", "[4] Enable Wi-Fi radio (explicit confirmation required)", "[0] Back"):
            self.ui.option(option)
        self.ui.rule()
        return self.ui.select(0, 4)

    def _bluetooth_menu(self) -> int | None:
        state = collect()
        self.ui.heading("Bluetooth Controls")
        self.ui.label("Current state:", reports.effective(state.bluetooth_effective))
        self.ui.label("Service:", state.bluetooth_active)
        self.ui.label("RFKill:", reports.rfkill_summary(state.bluetooth))
        self.ui.label("Controller:", state.controller)
        self.ui.label("Powered:", state.powered if state.controller == "available" else "NOT AVAILABLE")
        self.ui.rule()
        for option in ("[1] Show detailed Bluetooth state", "[2] Disable and RFKill-block Bluetooth", "[3] Enable Bluetooth (explicit confirmation required)", "[4] Controller power controls", "[0] Back"):
            self.ui.option(option)
        self.ui.rule()
        return self.ui.select(0, 4)

    def _bluetooth_power_menu(self) -> int | None:
        state = collect()
        self.ui.heading("Bluetooth Controller Power")
        self.ui.label("Controller:", state.controller)
        self.ui.label("Powered:", state.powered if state.controller == "available" else "NOT AVAILABLE")
        self.ui.label("Service:", state.bluetooth_active)
        self.ui.label("RFKill:", reports.rfkill_summary(state.bluetooth))
        self.ui.note("Controller power does not change Bluetooth service or RFKill state.")
        self.ui.rule()
        for option in ("[1] Turn Bluetooth controller off", "[2] Turn Bluetooth controller on (explicit confirmation required)", "[0] Back"):
            self.ui.option(option)
        self.ui.rule()
        return self.ui.select(0, 2)

    def run(self) -> int:
        while True:
            selection = self._main_menu()
            if selection is None:
                print("\nInput closed. Exiting menu without changes.")
                return EXIT_OK
            if selection == -1:
                self.ui.alert("Invalid selection. Please choose a numbered option.")
            elif selection == 0:
                return EXIT_OK
            elif selection == 1:
                reports.status(self.ui)
                if not self.ui.pause():
                    print("\nInput closed. Exiting menu without changes.")
                    return EXIT_OK
            elif selection == 2:
                delegate(self.repository, PrivilegedOperation.LOCKDOWN)
                if not self.ui.pause():
                    print("\nInput closed. Exiting menu without changes.")
                    return EXIT_OK
            elif selection == 3:
                print("\n")
                if not self._run_wifi():
                    print("Input closed. Exiting menu without changes.")
                    return EXIT_OK
            elif selection == 4:
                print("\n")
                if not self._run_bluetooth():
                    print("Input closed. Exiting menu without changes.")
                    return EXIT_OK
            elif selection == 5:
                readiness.report(self.ui)
                if not self.ui.pause():
                    print("\nInput closed. Exiting menu without changes.")
                    return EXIT_OK
            elif selection == 6:
                delegate(self.repository, PrivilegedOperation.RECENT_ACTIVITY)
                if not self.ui.pause():
                    print("\nInput closed. Exiting menu without changes.")
                    return EXIT_OK
            elif selection == 7 and sys.stdout.isatty():
                self.ui.clear()
            elif selection == 8:
                reports.nordvpn_detail(self.ui)
                if not self.ui.pause():
                    print("\nInput closed. Exiting menu without changes.")
                    return EXIT_OK

    def _run_wifi(self) -> bool:
        while True:
            selected = self._wifi_menu()
            if selected is None:
                return False
            if selected == 0:
                print("\n")
                return True
            if selected == -1:
                self.ui.alert("Invalid selection.")
            elif selected == 1:
                reports.wifi_detail(self.ui)
                if not self.ui.pause():
                    return False
            elif selected == 2:
                reports.profiles(self.ui)
                if not self.ui.pause():
                    return False
            elif selected == 3:
                delegate(self.repository, PrivilegedOperation.WIFI_DISABLE)
                if not self.ui.pause():
                    return False
            elif selected == 4:
                delegate(self.repository, PrivilegedOperation.WIFI_ENABLE)
                if not self.ui.pause():
                    return False

    def _run_bluetooth(self) -> bool:
        while True:
            selected = self._bluetooth_menu()
            if selected is None:
                return False
            if selected == 0:
                print("\n")
                return True
            if selected == -1:
                self.ui.alert("Invalid selection.")
            elif selected == 1:
                reports.bluetooth_detail(self.ui)
                if not self.ui.pause():
                    return False
            elif selected == 2:
                delegate(self.repository, PrivilegedOperation.BLUETOOTH_DISABLE)
                if not self.ui.pause():
                    return False
            elif selected == 3:
                delegate(self.repository, PrivilegedOperation.BLUETOOTH_ENABLE)
                if not self.ui.pause():
                    return False
            elif selected == 4:
                print("\n")
                if not self._run_bluetooth_power():
                    return False

    def _run_bluetooth_power(self) -> bool:
        while True:
            selected = self._bluetooth_power_menu()
            if selected is None:
                return False
            if selected == 0:
                print("\n")
                return True
            if selected == -1:
                self.ui.alert("Invalid selection.")
            elif selected == 1:
                delegate(self.repository, PrivilegedOperation.BLUETOOTH_POWER_OFF)
                if not self.ui.pause():
                    return False
            elif selected == 2:
                delegate(self.repository, PrivilegedOperation.BLUETOOTH_POWER_ON)
                if not self.ui.pause():
                    return False
