import sys
from dataclasses import replace
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control import readiness
from fedora_radio_control.host import ListenerExposure, ScreenLock
from fedora_radio_control.system import Result
from fedora_radio_control.system import EXIT_OK, EXIT_POLICY, EXIT_UNKNOWN
from fedora_radio_control.state import Connections


class FirewallReadinessTests(unittest.TestCase):
    @staticmethod
    def _assessment() -> readiness.ReadinessAssessment:
        return readiness.ReadinessAssessment(
            radio="PASS",
            bluetooth_service="PASS (inactive)",
            bluetooth_controller="NOT APPLICABLE (no controller)",
            bluetooth="PASS",
            wireless_link="NONE",
            wireless_zone="NOT APPLICABLE",
            autoconnect="PASS (none enabled)",
            firewall="PASS",
            selinux="PASS (enforcing)",
            listeners="PASS (none detected)",
            mac_privacy="NOT APPLICABLE (no active Wi-Fi)",
            desktop_lock="NOT APPLICABLE (GNOME setting unavailable)",
            vpn_detected="INFORMATIONAL (none detected)",
            vpn="NOT APPLICABLE (no active Wi-Fi)",
            nordvpn_client="NOT DETECTED",
            nordvpn_technology="NOT DETECTED",
            kernel="REVIEW (update status not verified)",
            hygiene="REVIEW (patch before travel)",
            adapters="REVIEW (baseline not recorded)",
        )

    def test_vpn_posture_is_conservative_on_active_wifi(self):
        active = Connections("12m", "active", 1, "12m")
        inactive = Connections("12m", "inactive", 0, "not connected")

        self.assertEqual(
            readiness._vpn_posture(active, "wlp0s20f3", True),
            "REVIEW (active VPN detected; routing and DNS not verified)",
        )
        self.assertEqual(
            readiness._vpn_posture(inactive, "wlp0s20f3", True),
            "REVIEW (no active VPN detected)",
        )

    def test_vpn_posture_is_not_applicable_without_active_wifi(self):
        connection = Connections("not connected", "active", 1, "12m")
        self.assertEqual(
            readiness._vpn_posture(connection, None, True),
            "NOT APPLICABLE (no active Wi-Fi)",
        )

    def test_permissive_default_zone_fails_when_interface_has_no_zone(self):
        with patch.object(
            readiness,
            "run",
            side_effect=(Result(0, "no zone\n", ""), Result(0, "trusted\n", "")),
        ):
            posture = readiness._wireless_zone("wlp0s20f3")

        self.assertEqual(posture, "FAIL (trusted is permissive for conference Wi-Fi; default zone)")

    def test_public_default_zone_is_accepted_when_interface_has_no_zone(self):
        with patch.object(
            readiness,
            "run",
            side_effect=(Result(1, "", ""), Result(0, "public\n", "")),
        ):
            posture = readiness._wireless_zone("wlp0s20f3")

        self.assertEqual(posture, "PASS (public; default zone)")

    def test_selinux_requires_enforcing_mode(self):
        self.assertEqual(readiness._selinux_posture("enforcing"), "PASS (enforcing)")
        self.assertEqual(readiness._selinux_posture("permissive"), "FAIL (permissive)")
        self.assertEqual(readiness._selinux_posture("disabled"), "FAIL (disabled)")
        self.assertEqual(readiness._selinux_posture("unknown"), "UNKNOWN (mode unavailable)")

    def test_listener_posture_omits_socket_details(self):
        self.assertEqual(readiness._listener_posture(ListenerExposure(True)), "PASS (none detected)")
        self.assertEqual(
            readiness._listener_posture(ListenerExposure(True, total=4, network_visible=2)),
            "REVIEW (2 network-visible; details omitted)",
        )

    def test_mac_privacy_requires_a_changed_active_address_on_wifi(self):
        self.assertEqual(
            readiness._mac_privacy_posture("randomized"),
            "PASS (active address differs from hardware address)",
        )
        self.assertEqual(readiness._mac_privacy_posture("hardware"), "REVIEW (active hardware address)")
        self.assertEqual(readiness._mac_privacy_posture("not-applicable"), "NOT APPLICABLE (no active Wi-Fi)")

    def test_gnome_auto_lock_is_strict_when_available(self):
        self.assertEqual(
            readiness._screen_lock_posture(ScreenLock(True, True, 300, 0)),
            "PASS (idle 300s; lock delay 0s)",
        )
        self.assertEqual(
            readiness._screen_lock_posture(ScreenLock(True, False, 300, 0)),
            "FAIL (screen lock disabled)",
        )
        self.assertEqual(
            readiness._screen_lock_posture(ScreenLock(True, True, 0, 0)),
            "FAIL (automatic idle lock disabled)",
        )
        self.assertEqual(
            readiness._screen_lock_posture(ScreenLock(False)),
            "NOT APPLICABLE (GNOME setting unavailable)",
        )

    def test_assessment_owns_overall_state_and_exit_code_policy(self):
        ready = self._assessment()
        self.assertEqual(ready.overall, "READY WITH REVIEW ITEMS")
        self.assertEqual(ready.exit_code, EXIT_OK)
        self.assertFalse(ready.requires_lockdown)

        failed = replace(ready, radio="FAIL")
        self.assertEqual(failed.overall, "NOT READY")
        self.assertEqual(failed.exit_code, EXIT_POLICY)
        self.assertTrue(failed.requires_lockdown)

        unknown = replace(ready, wireless_link="UNKNOWN (query failed)")
        self.assertEqual(unknown.overall, "STATE UNKNOWN")
        self.assertEqual(unknown.exit_code, EXIT_UNKNOWN)


if __name__ == "__main__":
    unittest.main()
