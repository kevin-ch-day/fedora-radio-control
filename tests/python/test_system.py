import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control import system


class PrivilegedRuntimeStatusTests(unittest.TestCase):
    def test_version_mismatch_requires_install_not_verify(self):
        with (
            patch.object(system, "component_status", return_value="VERSION MISMATCH"),
            patch("sys.stderr") as stderr,
            patch.object(system.subprocess, "run") as run,
        ):
            self.assertEqual(
                system.delegate(Path("/repository"), system.PrivilegedOperation.LOCKDOWN),
                system.EXIT_UNKNOWN,
        )

        run.assert_not_called()
        output = "".join(call.args[0] for call in stderr.write.call_args_list)
        self.assertIn("Run: sudo ./install.sh", output)
        self.assertNotIn("--verify", output)
        self.assertIn("start normally with ./run.sh", output)

    def test_interactive_operation_uses_sudo_prompt(self):
        with (
            patch.object(system, "component_status", return_value="INSTALLED"),
            patch.object(system.os, "geteuid", return_value=1000),
            patch.object(system, "exists", return_value=True),
            patch.object(system.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run,
        ):
            self.assertEqual(
                system.delegate(Path("/repository"), system.PrivilegedOperation.WIFI_DISABLE),
                system.EXIT_OK,
            )

        self.assertEqual(
            run.call_args.args[0],
            ["sudo", "--", str(system.HELPER), "wifi-disable"],
        )

    def test_non_interactive_lockdown_uses_non_prompting_sudo(self):
        with (
            patch.object(system, "component_status", return_value="INSTALLED"),
            patch.object(system.os, "geteuid", return_value=1000),
            patch.object(system, "exists", return_value=True),
            patch.object(system.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run,
        ):
            self.assertEqual(
                system.delegate(Path("/repository"), system.PrivilegedOperation.LOCKDOWN_NON_INTERACTIVE),
                system.EXIT_OK,
            )

        self.assertEqual(
            run.call_args.args[0],
            ["sudo", "-n", "--", str(system.HELPER), "lockdown-non-interactive"],
        )

    def test_runtime_manifest_excludes_legacy_display_modules(self):
        self.assertNotIn("status-report.sh", system.RUNTIME_FILES)
        self.assertNotIn("radio-state.sh", system.RUNTIME_FILES)

    def test_runtime_manifest_declares_exact_installed_modes(self):
        self.assertEqual(tuple(system.RUNTIME_FILE_MODES), system.RUNTIME_FILES)
        self.assertEqual(system.RUNTIME_FILE_MODES["radio-control-privileged"], 0o755)
        self.assertEqual(system.RUNTIME_FILE_MODES["VERSION"], 0o644)
        self.assertTrue(
            all(mode == 0o640 for name, mode in system.RUNTIME_FILE_MODES.items()
                if name not in {"radio-control-privileged", "VERSION"})
        )

    def test_non_traversable_runtime_is_reported_separately_from_missing_or_invalid(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            runtime = Path(temporary) / "runtime"
            repository.mkdir()
            runtime.mkdir()
            (repository / "VERSION").write_text("5\n")
            (runtime / "VERSION").write_text("5\n")

            with (
                patch.object(system, "RUNTIME_DIR", runtime),
                patch.object(system, "_safe", return_value=True),
                patch.object(system, "_publicly_traversable", return_value=False),
            ):
                self.assertEqual(system.component_status(repository), "NOT ACCESSIBLE")

    def test_unreadable_installed_version_is_reported_separately(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            runtime = Path(temporary) / "runtime"
            repository.mkdir()
            runtime.mkdir()
            (repository / "VERSION").write_text("5\n")
            (runtime / "VERSION").write_text("5\n")

            original_read_text = Path.read_text

            def read_text(path, *arguments, **keywords):
                if path == runtime / "VERSION":
                    raise PermissionError
                return original_read_text(path, *arguments, **keywords)

            with (
                patch.object(system, "RUNTIME_DIR", runtime),
                patch.object(system, "_safe", return_value=True),
                patch.object(system, "_publicly_traversable", return_value=True),
                patch.object(Path, "read_text", read_text),
            ):
                self.assertEqual(system.component_status(repository), "VERSION UNREADABLE")


if __name__ == "__main__":
    unittest.main()
