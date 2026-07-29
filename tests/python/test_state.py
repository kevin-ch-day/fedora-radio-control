import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control.state import RFKill, State
from fedora_radio_control.system import elapsed


class StatePolicyTests(unittest.TestCase):
    def test_locked_down_requires_both_radio_controls(self):
        state = State(
            wifi_radio="disabled",
            wifi=[RFKill("1", "wifi0", "blocked", "unblocked")],
            bluetooth=[RFKill("2", "bt0", "blocked", "unblocked")],
            bluetooth_active="inactive",
            controller="unavailable",
        )
        self.assertEqual(state.policy, "LOCKED DOWN")

    def test_active_bluetooth_blocks_policy(self):
        state = State(
            wifi_radio="disabled",
            wifi=[RFKill("1", "wifi0", "blocked", "unblocked")],
            bluetooth=[RFKill("2", "bt0", "blocked", "unblocked")],
            bluetooth_active="active",
            controller="unavailable",
        )
        self.assertEqual(state.policy, "NOT LOCKED DOWN")
        self.assertEqual(state.reason(), "bluetooth.service remains active")

    def test_elapsed_format_is_stable(self):
        self.assertEqual(elapsed(3661), "1h 01m")
        self.assertEqual(elapsed(90061), "1d 01h 01m")


if __name__ == "__main__":
    unittest.main()
