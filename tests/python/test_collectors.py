import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control import state
from fedora_radio_control.system import Result


class CollectorTests(unittest.TestCase):
    def test_inactive_bluetooth_service_skips_controller_query(self):
        results = iter((
            Result(0, '{"rfkilldevices":[{"id":1,"type":"wlan","device":"wifi","soft":"blocked","hard":"unblocked"},{"id":2,"type":"bluetooth","device":"bt","soft":"blocked","hard":"unblocked"}]}', ""),
            Result(0, "disabled\n", ""),
            Result(0, "inactive\n", ""),
            Result(0, "masked-runtime\n", ""),
        ))
        with patch.object(state, "run", side_effect=lambda *_arguments, **_keywords: next(results)) as run:
            collected = state.collect()

        self.assertEqual(collected.controller, "unavailable")
        self.assertFalse(collected.bluetooth_failed)
        self.assertEqual(collected.bluetooth_effective, "disabled")
        self.assertEqual(run.call_count, 4)

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

    def test_wifi_interface_is_collected_in_python_without_profile_or_ssid_data(self):
        response = Result(0, "wlp0s20f3:wifi:connected\nenp0s31f6:ethernet:connected\n", "")
        with patch.object(state, "run", return_value=response):
            interface, known = state.wifi_interface()

        self.assertEqual(interface, "wlp0s20f3")
        self.assertTrue(known)

    def test_active_wifi_mac_privacy_is_compared_without_exposing_addresses(self):
        output = "GENERAL.HWADDR:02:00:00:00:00:01\nGENERAL.PERM-HWADDR:00:11:22:33:44:55\n"
        with patch.object(state, "run", return_value=Result(0, output, "")) as run:
            posture = state.wifi_mac_privacy("wlp0s20f3", True)

        self.assertEqual(posture, "randomized")
        self.assertEqual(run.call_args.args[0][-1], "wlp0s20f3")

    def test_inactive_wifi_mac_privacy_is_not_applicable(self):
        self.assertEqual(state.wifi_mac_privacy(None, True), "not-applicable")

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
