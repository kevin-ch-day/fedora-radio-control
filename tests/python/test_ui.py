import os
import sys
import contextlib
import io
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control.ui import UI


class TerminalThemeTests(unittest.TestCase):
    def test_no_color_environment_disables_ansi_even_when_output_is_a_terminal(self):
        with patch.object(sys.stdout, "isatty", return_value=True), patch.dict(os.environ, {"NO_COLOR": ""}):
            ui = UI()

        self.assertFalse(ui.color)
        self.assertEqual(ui.result("LOCKED DOWN"), "[ SAFE ] LOCKED DOWN")

    def test_dumb_terminal_disables_ansi(self):
        with patch.object(sys.stdout, "isatty", return_value=True), patch.dict(os.environ, {"TERM": "dumb"}, clear=True):
            ui = UI()

        self.assertFalse(ui.color)

    def test_status_palette_separates_safe_review_and_exposure_states(self):
        ui = UI(color=True)

        self.assertIn("[ SAFE ]", ui.result("LOCKED DOWN"))
        self.assertIn("[ REVIEW ]", ui.result("STATE UNKNOWN"))
        self.assertIn("[ ALERT ]", ui.result("NOT LOCKED DOWN"))
        self.assertIn("[1;32m", ui.result("LOCKED DOWN"))
        self.assertIn("[1;33m", ui.result("STATE UNKNOWN"))
        self.assertIn("[1;31m", ui.result("NOT LOCKED DOWN"))

    def test_plain_theme_preserves_a_clear_industrial_layout_without_ansi(self):
        ui = UI(color=False)
        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            ui.heading("Fedora Radio Control")
            ui.section("Wi-Fi")
            ui.label("RFKill:", "BLOCKED")
            ui.rule()
            ui.option("[1] Show detailed radio status")
            ui.alert("Radio state needs review.")

        self.assertEqual(
            output.getvalue(),
            "[ FRC ] // FEDORA RADIO CONTROL\n"
            "===========================//===============================\n"
            "\n[ WI-FI ]\n"
            "  RFKill:                BLOCKED\n"
            "---------------------------//-------------------------------\n"
            "[1] Show detailed radio status\n"
            "!! Radio state needs review.\n",
        )


if __name__ == "__main__":
    unittest.main()
