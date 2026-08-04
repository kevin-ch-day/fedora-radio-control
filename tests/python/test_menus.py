import contextlib
import io
import sys
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control.menus import MenuController
from fedora_radio_control.system import EXIT_OK


class MenuInputTests(unittest.TestCase):
    def test_closed_input_in_submenu_exits_the_application(self):
        controller = MenuController(Mock(), Path("/repository"))

        with (
            patch.object(MenuController, "_main_menu", return_value=3),
            patch.object(MenuController, "_run_wifi", return_value=False),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            result = controller.run()

        self.assertEqual(result, EXIT_OK)
        self.assertIn("Input closed. Exiting menu without changes.", output.getvalue())


if __name__ == "__main__":
    unittest.main()
