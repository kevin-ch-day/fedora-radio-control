"""Terminal output and interaction for the unprivileged Python frontend."""

from __future__ import annotations

import os
import sys


class UI:
    """Keep terminal styling and prompt behavior out of radio-policy code."""

    def __init__(self) -> None:
        self.color = sys.stdout.isatty() and not os.environ.get("NO_COLOR")

    def _style(self, value: str, code: str) -> str:
        return f"\033[{code}m{value}\033[0m" if self.color else value

    def heading(self, value: str) -> None:
        print(self._style(value, "1;36"))
        print("============================================================")

    def section(self, value: str) -> None:
        print()
        print(self._style(value, "1"))

    @staticmethod
    def label(name: str, value: object) -> None:
        print(f"  {name:<22} {value}")

    @staticmethod
    def rule() -> None:
        print("------------------------------------------------------------")

    def note(self, value: str) -> None:
        print(self._style(value, "2"))

    def result(self, value: str) -> str:
        if value in {"LOCKED DOWN", "DISABLED"}:
            return self._style(value, "32")
        if value in {"NOT LOCKED DOWN", "STATE UNKNOWN", "NOT FULLY DISABLED"}:
            return self._style(value, "31")
        return self._style(value, "33")

    @staticmethod
    def select(low: int, high: int) -> int | None:
        try:
            value = input("Selection: ").strip()
        except EOFError:
            return None
        return int(value) if value.isdigit() and low <= int(value) <= high else -1

    @staticmethod
    def pause() -> None:
        if sys.stdin.isatty() and sys.stdout.isatty():
            try:
                input("\nPress Enter to return to the menu... ")
            except EOFError:
                pass
