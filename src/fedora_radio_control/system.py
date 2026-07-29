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
RUNTIME_FILES = (
    "radio-control-privileged", "common.sh", "logging.sh", "wifi-state.sh",
    "bluetooth-state.sh", "rfkill.sh", "radio-policy.sh", "status-report.sh",
    "radio-state.sh", "wifi-control.sh", "bluetooth-control.sh", "lockdown.sh", "VERSION",
)


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


def _safe(path: Path, directory: bool = False) -> bool:
    try:
        info = path.lstat()
    except OSError:
        return False
    expected_type = stat.S_ISDIR if directory else stat.S_ISREG
    return (not stat.S_ISLNK(info.st_mode) and expected_type(info.st_mode) and info.st_uid == 0
            and (stat.S_IMODE(info.st_mode) & 0o022) == 0)


def component_status(repository: Path) -> str:
    if not _safe(RUNTIME_DIR, directory=True):
        return "MISSING"
    if not all(_safe(RUNTIME_DIR / name) for name in RUNTIME_FILES):
        return "INVALID"
    try:
        return "INSTALLED" if (repository / "VERSION").read_text().strip() == (RUNTIME_DIR / "VERSION").read_text().strip() else "VERSION MISMATCH"
    except OSError:
        return "INVALID"


def delegate(repository: Path, operation: PrivilegedOperation) -> int:
    status = component_status(repository)
    if status != "INSTALLED":
        message = ("The privileged Fedora Radio Control component is not installed. Run: sudo ./install.sh"
                   if status == "MISSING" else "The privileged component is invalid or version-mismatched. Run: sudo ./install.sh --verify")
        print(f"Error: {message}", file=os.sys.stderr)
        return EXIT_UNKNOWN
    command = [str(HELPER), operation.value]
    if os.geteuid() != 0:
        if not exists("sudo"):
            print("Error: Required command not found: sudo", file=os.sys.stderr)
            return EXIT_UNKNOWN
        command[:0] = ["sudo", "--"]
    try:
        return subprocess.run(command, check=False).returncode
    except OSError:
        print("Error: Unable to start the installed privileged component.", file=os.sys.stderr)
        return EXIT_UNKNOWN
