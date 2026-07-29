import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control import system


class PrivilegedRuntimeStatusTests(unittest.TestCase):
    def test_runtime_manifest_excludes_legacy_display_modules(self):
        self.assertNotIn("status-report.sh", system.RUNTIME_FILES)
        self.assertNotIn("radio-state.sh", system.RUNTIME_FILES)

    def test_non_traversable_runtime_is_reported_separately_from_missing_or_invalid(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            runtime = Path(temporary) / "runtime"
            repository.mkdir()
            runtime.mkdir()
            (repository / "VERSION").write_text("3\n")
            (runtime / "VERSION").write_text("3\n")

            with (
                patch.object(system, "RUNTIME_DIR", runtime),
                patch.object(system, "_safe", return_value=True),
                patch.object(system, "_publicly_traversable", return_value=False),
            ):
                self.assertEqual(system.component_status(repository), "NOT ACCESSIBLE")


if __name__ == "__main__":
    unittest.main()
