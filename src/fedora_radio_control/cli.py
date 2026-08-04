"""Argument parsing and command dispatch for Fedora Radio Control."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
from typing import Callable

from . import readiness, reports
from .menus import MenuController
from .operations import PrivilegedOperation
from .system import EXIT_OK, EXIT_UNKNOWN, EXIT_USAGE, delegate, exists, fedora
from .ui import UI


REPOSITORY = Path(__file__).resolve().parents[2]
Handler = Callable[[argparse.Namespace], int]
EXIT_INTERRUPTED = 130


def require_fedora(*commands: str) -> bool:
    """Validate the supported platform and required read-only command tools."""
    if not fedora():
        print("Error: This utility supports Fedora Linux only.", file=sys.stderr)
        return False
    missing = [command for command in commands if not exists(command)]
    if missing:
        print(f"Error: Required command not found: {', '.join(missing)}", file=sys.stderr)
        return False
    return True


def show_status(_arguments: argparse.Namespace) -> int:
    if not require_fedora("nmcli", "rfkill", "systemctl"):
        return EXIT_UNKNOWN
    return reports.status(UI())


def show_readiness(_arguments: argparse.Namespace) -> int:
    if not require_fedora("nmcli", "rfkill", "systemctl"):
        return EXIT_UNKNOWN
    return readiness.report(UI())


def show_profiles(_arguments: argparse.Namespace) -> int:
    if not require_fedora("nmcli"):
        return EXIT_UNKNOWN
    return reports.profiles(UI())


def run_interactive(_arguments: argparse.Namespace) -> int:
    if not require_fedora("nmcli", "rfkill", "systemctl"):
        return EXIT_UNKNOWN
    return MenuController(UI(), REPOSITORY).run()


def delegate_operation(operation: PrivilegedOperation) -> Handler:
    return lambda _arguments: delegate(REPOSITORY, operation)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="./run.sh",
        description="Report Fedora radio posture or request a verified control action.",
    )
    commands = parser.add_subparsers(dest="command", title="commands")
    commands.add_parser("status", help="show detailed radio state").set_defaults(handler=show_status)
    commands.add_parser("readiness", help="show DEF CON readiness").set_defaults(handler=show_readiness)
    commands.add_parser("activity", help="show protected recent activity").set_defaults(
        handler=delegate_operation(PrivilegedOperation.RECENT_ACTIVITY)
    )
    commands.add_parser("help", help="show this help").set_defaults(
        handler=lambda _arguments: parser.print_help() or EXIT_OK
    )

    lockdown = commands.add_parser("lockdown", help="apply verified radio lockdown")
    lockdown.add_argument("--non-interactive", action="store_true", help="skip helper confirmation")
    lockdown.set_defaults(
        handler=lambda arguments: delegate(
            REPOSITORY,
            PrivilegedOperation.LOCKDOWN_NON_INTERACTIVE if arguments.non_interactive else PrivilegedOperation.LOCKDOWN,
        )
    )

    wifi = commands.add_parser("wifi", help="Wi-Fi controls")
    wifi_commands = wifi.add_subparsers(dest="wifi_command", required=True)
    wifi_commands.add_parser("profiles", help="review autoconnect profile count").set_defaults(
        handler=show_profiles
    )
    wifi_commands.add_parser("disable", help="disable and RFKill-block Wi-Fi").set_defaults(
        handler=delegate_operation(PrivilegedOperation.WIFI_DISABLE)
    )
    wifi_commands.add_parser("enable", help="enable Wi-Fi after confirmation").set_defaults(
        handler=delegate_operation(PrivilegedOperation.WIFI_ENABLE)
    )

    bluetooth = commands.add_parser("bluetooth", help="Bluetooth controls")
    bluetooth_commands = bluetooth.add_subparsers(dest="bluetooth_command", required=True)
    bluetooth_commands.add_parser("disable", help="disable and RFKill-block Bluetooth").set_defaults(
        handler=delegate_operation(PrivilegedOperation.BLUETOOTH_DISABLE)
    )
    return parser


def main(arguments: list[str] | None = None) -> int:
    # The source checkout is intentionally never a privileged execution
    # environment.  State changes are elevated only by the installed,
    # root-owned helper through ``delegate``.
    if os.geteuid() == 0:
        print(
            "Error: Do not run Fedora Radio Control as root. "
            "Start it as your normal user: ./run.sh",
            file=sys.stderr,
        )
        return EXIT_USAGE
    try:
        parser = build_parser()
        parsed = parser.parse_args(arguments)
        handler: Handler = getattr(parsed, "handler", run_interactive)
        return handler(parsed)
    except KeyboardInterrupt:
        print("\nInterrupted. Exiting Fedora Radio Control without further changes.", file=sys.stderr)
        return EXIT_INTERRUPTED
