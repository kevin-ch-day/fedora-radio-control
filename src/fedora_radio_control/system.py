"""Operating-system boundary helpers. Commands are never passed through a shell."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import os
from pathlib import Path
import shutil
import stat
import subprocess
from typing import Sequence

from .operations import PrivilegedOperation

EXIT_OK = 0
EXIT_POLICY = 1
EXIT_USAGE = 2
EXIT_UNKNOWN = 3
EXIT_PRIVILEGE = 4

RUNTIME_DIR = Path("/usr/local/libexec/fedora-radio-control")
HELPER = RUNTIME_DIR / "radio-control-privileged"
RUNTIME_FILE_MODES = {
    "radio-control-privileged": 0o755,
    "common.sh": 0o640,
    "display.sh": 0o640,
    "logging.sh": 0o640,
    "wifi-state.sh": 0o640,
    "bluetooth-state.sh": 0o640,
    "rfkill.sh": 0o640,
    "radio-policy.sh": 0o640,
    "wifi-control.sh": 0o640,
    "bluetooth-control.sh": 0o640,
    "lockdown.sh": 0o640,
    "VERSION": 0o644,
}
RUNTIME_FILES = tuple(RUNTIME_FILE_MODES)


@dataclass(frozen=True)
class Result:
    returncode: int
    stdout: str
    stderr: str


def run(arguments: Sequence[str], *, timeout: int = 5) -> Result:
    environment = os.environ.copy()
    environment["LC_ALL"] = "C"
    try:
        process = subprocess.run(list(arguments), text=True, capture_output=True, check=False,
                                 timeout=timeout, env=environment)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return Result(EXIT_UNKNOWN, "", "")
    return Result(process.returncode, process.stdout, process.stderr)


def exists(name: str) -> bool:
    return shutil.which(name) is not None


def fedora() -> bool:
    try:
        return any(line.strip() == "ID=fedora" for line in Path("/etc/os-release").read_text().splitlines())
    except OSError:
        return False


def os_name() -> str:
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            if line.startswith("PRETTY_NAME="):
                return line.split("=", 1)[1].strip('"')
    except OSError:
        pass
    return "Fedora Linux"


def elapsed(seconds: int) -> str:
    days, remainder = divmod(max(seconds, 0), 86400)
    hours, remainder = divmod(remainder, 3600)
    minutes = remainder // 60
    if days:
        return f"{days}d {hours:02d}h {minutes:02d}m"
    if hours:
        return f"{hours}h {minutes:02d}m"
    return f"{minutes}m"


def now() -> int:
    return int(datetime.now(timezone.utc).timestamp())


def _safe(path: Path, directory: bool = False, expected_mode: int | None = None) -> bool:
    try:
        info = path.lstat()
    except OSError:
        return False
    expected_type = stat.S_ISDIR if directory else stat.S_ISREG
    mode = stat.S_IMODE(info.st_mode)
    return (not stat.S_ISLNK(info.st_mode) and expected_type(info.st_mode) and info.st_uid == 0
            and (mode & 0o022) == 0 and (expected_mode is None or mode == expected_mode))


def _publicly_traversable(path: Path) -> bool:
    """Return whether a normal user can inspect an installed runtime directory."""
    try:
        info = path.lstat()
    except OSError:
        return False
    return stat.S_ISDIR(info.st_mode) and bool(stat.S_IMODE(info.st_mode) & stat.S_IXOTH)


def component_status(repository: Path) -> str:
    if not _safe(RUNTIME_DIR, directory=True):
        return "MISSING"
    if not _publicly_traversable(RUNTIME_DIR):
        return "NOT ACCESSIBLE"
    if not _safe(RUNTIME_DIR, directory=True, expected_mode=0o755):
        return "INVALID"
    if not all(_safe(RUNTIME_DIR / name, expected_mode=mode) for name, mode in RUNTIME_FILE_MODES.items()):
        return "INVALID"
    try:
        source_version = (repository / "VERSION").read_text().strip()
        installed_version = (RUNTIME_DIR / "VERSION").read_text().strip()
    except PermissionError:
        return "VERSION UNREADABLE"
    except OSError:
        return "INVALID"
    return "INSTALLED" if source_version == installed_version else "VERSION MISMATCH"


def delegate(repository: Path, operation: PrivilegedOperation) -> int:
    status = component_status(repository)
    if status != "INSTALLED":
        if status == "MISSING":
            message = "The privileged Fedora Radio Control component is not installed. Run: sudo ./install.sh"
        elif status in {"NOT ACCESSIBLE", "VERSION UNREADABLE"}:
            message = "The privileged component cannot be verified by your normal user. Run: sudo ./install.sh"
        elif status == "VERSION MISMATCH":
            message = (
                "The installed privileged component is out of date. "
                "Run: sudo ./install.sh once. Then start normally with ./run.sh; "
                "radio actions will request sudo when needed."
            )
        else:
            message = "The privileged component is invalid. Run: sudo ./install.sh --verify"
        print(f"Error: {message}", file=os.sys.stderr)
        return EXIT_UNKNOWN
    command = [str(HELPER), operation.value]
    if os.geteuid() != 0:
        if not exists("sudo"):
            print("Error: Required command not found: sudo", file=os.sys.stderr)
            return EXIT_UNKNOWN
        sudo_arguments = ["sudo", "--"]
        if operation is PrivilegedOperation.LOCKDOWN_NON_INTERACTIVE:
            sudo_arguments = ["sudo", "-n", "--"]
        command[:0] = sudo_arguments
    try:
        return subprocess.run(command, check=False).returncode
    except OSError:
        print("Error: Unable to start the installed privileged component.", file=os.sys.stderr)
        return EXIT_UNKNOWN
