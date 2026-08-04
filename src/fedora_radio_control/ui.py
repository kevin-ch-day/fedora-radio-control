"""Terminal rendering and interaction for the unprivileged Python frontend."""

from __future__ import annotations

import os
import sys


class UI:
    """Render an industrial, high-contrast console without sacrificing plain output."""

    _RESET = "\033[0m"
    _GRAPHITE = "90"
    _PAPER = "1;97"
    _SIGNAL = "1;36"
    _SAFE = "1;32"
    _REVIEW = "1;33"
    _DANGER = "1;31"
    _INFO = "36"

    def __init__(self, color: bool | None = None) -> None:
        self.color = self._supports_color() if color is None else color

    @staticmethod
    def _supports_color() -> bool:
        return (
            sys.stdout.isatty()
            and os.environ.get("TERM", "") != "dumb"
            and "NO_COLOR" not in os.environ
        )

    def _style(self, value: str, code: str) -> str:
        return f"\033[{code}m{value}{self._RESET}" if self.color else value

    def _tone(self, value: object) -> str:
        text = str(value)
        normalized = text.upper()
        if normalized.startswith(("LOCKED DOWN", "DISABLED", "BLOCKED", "INACTIVE", "PASS", "READY")):
            return self._style(text, self._SAFE)
        if normalized in {"NONE", "NOT DETECTED", "NOT APPLICABLE", "INSTALLED AND VERIFIED"}:
            return self._style(text, self._SAFE)
        if normalized.startswith(("FAIL", "NOT LOCKED", "NOT FULLY", "NOT ACCESSIBLE", "VERSION MISMATCH", "VERSION UNREADABLE", "UNBLOCKED", "MISSING", "INVALID", "ACTIVE", "ENABLED")):
            return self._style(text, self._DANGER)
        if normalized.startswith(("STATE UNKNOWN", "UNKNOWN", "REVIEW", "HARDWARE BLOCKED")):
            return self._style(text, self._REVIEW)
        if normalized.startswith("INFORMATIONAL"):
            return self._style(text, self._INFO)
        return text

    def heading(self, value: str) -> None:
        marker = self._style("[ FRC ]", self._DANGER)
        title = self._style(f" // {value.upper()}", self._PAPER)
        print(f"{marker}{title}")
        print(self._style("=" * 27 + "//" + "=" * 31, self._GRAPHITE))

    def section(self, value: str) -> None:
        print()
        marker = self._style("[", self._DANGER)
        title = self._style(f" {value.upper()} ", self._PAPER)
        print(f"{marker}{title}{self._style("]", self._DANGER)}")

    def label(self, name: str, value: object) -> None:
        label = self._style(f"  {name:<22}", self._GRAPHITE)
        print(f"{label} {self._tone(value)}")

    def rule(self) -> None:
        print(self._style("-" * 27 + "//" + "-" * 31, self._GRAPHITE))

    def note(self, value: str) -> None:
        print(self._style(f"// {value}", self._GRAPHITE))

    def result(self, value: str) -> str:
        normalized = value.upper()
        if normalized.startswith(("LOCKED DOWN", "DISABLED", "BLOCKED", "PASS", "READY")):
            badge = self._style("[ SAFE ]", self._SAFE)
        elif normalized.startswith(("STATE UNKNOWN", "UNKNOWN", "REVIEW")):
            badge = self._style("[ REVIEW ]", self._REVIEW)
        else:
            badge = self._style("[ ALERT ]", self._DANGER)
        return f"{badge} {self._tone(value)}"

    def option(self, value: str) -> None:
        prefix, separator, label = value.partition("]")
        if not separator:
            print(value)
            return
        code = self._GRAPHITE if prefix == "[0" else self._SIGNAL
        normalized = label.lower()
        if "enable" in normalized:
            label = self._style(label, self._REVIEW)
        elif "lockdown" in normalized or "disable" in normalized:
            label = self._style(label, self._DANGER)
        elif prefix == "[0":
            label = self._style(label, self._GRAPHITE)
        print(f"{self._style(prefix + separator, code)}{label}")

    def alert(self, value: str) -> None:
        print(self._style(f"!! {value}", self._DANGER))

    def select(self, low: int, high: int) -> int | None:
        try:
            value = input(self._style(f"COMMAND [{low}-{high}] > ", self._SIGNAL)).strip()
        except EOFError:
            return None
        return int(value) if value.isdigit() and low <= int(value) <= high else -1

    def clear(self) -> None:
        if sys.stdout.isatty():
            print("\033[2J\033[H", end="")

    @staticmethod
    def pause() -> bool:
        """Wait for a menu acknowledgement, returning false when input closes."""
        if sys.stdin.isatty() and sys.stdout.isatty():
            try:
                input("\nPress Enter to return to the menu... ")
            except EOFError:
                return False
        return True
