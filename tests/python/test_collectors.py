import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control import state
from fedora_radio_control.system import Result


class CollectorTests(unittest.TestCase):
    def test_rfkill_json_and_radio_state_are_collected_without_shell_parsing(self):
        responses = {
            ("rfkill", "--json"): Result(0, '{"rfkilldevices":[{"id":1,"type":"wlan","device":"wifi0","soft":"blocked","hard":"unblocked"},{"id":2,"type":"bluetooth","device":"bt0","soft":"blocked","hard":"unblocked"}]}', ""),
            ("nmcli", "--terse", "--fields", "WIFI", "general", "status"): Result(0, "disabled\n", ""),
            ("systemctl", "show", "bluetooth.service", "--property=ActiveState", "--value"): Result(0, "inactive\n", ""),
            ("systemctl", "show", "bluetooth.service", "--property=UnitFileState", "--value"): Result(0, "disabled\n", ""),
        }

        with patch.object(state, "run", side_effect=lambda command, **_kwargs: responses[tuple(command)]), patch.object(state.shutil, "which", return_value=None):
            collected = state.collect()

        self.assertEqual(collected.policy, "LOCKED DOWN")
        self.assertEqual(collected.wifi[0].device, "wifi0")
        self.assertEqual(collected.bluetooth[0].soft, "blocked")

    def test_connection_collection_omits_identifiers_and_uses_oldest_vpn(self):
        output = "wifi:4000\nwireguard:3000\nvpn:1000\nethernet:2000\n"
        with patch.object(state, "run", return_value=Result(0, output, "")), patch.object(state, "now", return_value=4661):
            collected = state.connections()

        self.assertEqual(collected.wifi_duration, "11m")
        self.assertEqual(collected.vpn_state, "active")
        self.assertEqual(collected.vpn_count, 2)
        self.assertEqual(collected.vpn_duration, "1h 01m")

    def test_failed_wifi_query_does_not_make_bluetooth_state_unknown(self):
        collected = state.State(
            wifi_radio="unknown",
            wifi_failed=True,
            bluetooth=[state.RFKill("2", "bt0", "blocked", "unblocked")],
            bluetooth_active="inactive",
            controller="unavailable",
        )
        self.assertEqual(collected.wifi_effective, "unknown")
        self.assertEqual(collected.bluetooth_effective, "disabled")
        self.assertEqual(collected.policy, "STATE UNKNOWN")


if __name__ == "__main__":
    unittest.main()
