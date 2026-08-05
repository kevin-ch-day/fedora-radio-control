import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control import vpn
from fedora_radio_control.system import Result


class NordVPNPostureTests(unittest.TestCase):
    def test_inspector_accepts_injected_read_only_command_boundary(self):
        responses = iter((
            Result(0, "Status: Connected\nServer: omitted\n", ""),
            Result(0, "Technology: NORDLYNX\nKill Switch: enabled\nAuto-connect: enabled\nRouting: enabled\nLAN Discovery: disabled\nMeshnet: disabled\n", ""),
        ))
        inspector = vpn.NordVPNInspector(
            command_exists=lambda name: name == "nordvpn",
            command_run=lambda *_args, **_kwargs: next(responses),
        )

        posture = inspector.collect()

        self.assertEqual(posture.status, "connected")
        self.assertEqual(posture.technology, "nordlynx")
        self.assertNotIn("omitted", repr(posture))

    def test_collects_only_nonsensitive_nordvpn_posture_fields(self):
        status = "Status: Connected\nServer: United States #9999\nIP: 203.0.113.9\n"
        settings = "Technology: NORDLYNX\nKill Switch: enabled\nAuto-connect: enabled\nRouting: enabled\nLAN Discovery: disabled\nMeshnet: disabled\nDNS: disabled\n"
        with (
            patch.object(vpn, "exists", return_value=True),
            patch.object(vpn, "run", side_effect=(Result(0, status, ""), Result(0, settings, ""))),
        ):
            posture = vpn.nordvpn_posture()

        self.assertEqual(posture.status, "connected")
        self.assertEqual(posture.technology, "nordlynx")
        self.assertEqual(posture.kill_switch, "enabled")
        self.assertEqual(posture.auto_connect, "enabled")
        self.assertEqual(posture.routing, "enabled")
        self.assertEqual(posture.lan_discovery, "disabled")
        self.assertEqual(posture.meshnet, "disabled")
        self.assertNotIn("203.0.113.9", repr(posture))
        self.assertNotIn("United States", repr(posture))

    def test_connected_client_with_disabled_safety_settings_is_review(self):
        posture = vpn.NordVPNPosture(
            available=True,
            status="connected",
            kill_switch="disabled",
            auto_connect="disabled",
            routing="enabled",
            lan_discovery="disabled",
            meshnet="disabled",
        )
        self.assertEqual(
            vpn.nordvpn_readiness(posture),
            "REVIEW (connected; kill switch disabled; auto-connect disabled)",
        )

    def test_connected_client_with_observed_safety_settings_passes(self):
        posture = vpn.NordVPNPosture(
            available=True,
            status="connected",
            technology="nordlynx",
            kill_switch="enabled",
            auto_connect="enabled",
            routing="enabled",
            lan_discovery="disabled",
            meshnet="disabled",
        )
        self.assertEqual(vpn.nordvpn_readiness(posture), "PASS (connected; safety settings observed)")
        self.assertEqual(vpn.nordvpn_technology(posture), "NORDLYNX (WireGuard-based)")

    def test_unknown_settings_are_not_misreported_as_disabled(self):
        posture = vpn.NordVPNPosture(available=True, status="connected")
        self.assertEqual(
            vpn.nordvpn_readiness(posture),
            "REVIEW (connected; kill switch not verified; auto-connect not verified; routing not verified; LAN discovery not verified)",
        )

    def test_meshnet_enabled_is_a_review_item(self):
        posture = vpn.NordVPNPosture(
            available=True,
            status="connected",
            kill_switch="enabled",
            auto_connect="enabled",
            routing="enabled",
            lan_discovery="disabled",
            meshnet="enabled",
        )
        self.assertEqual(vpn.nordvpn_readiness(posture), "REVIEW (connected; Meshnet enabled)")

    def test_setting_renderer_keeps_unknown_distinct_from_disabled(self):
        self.assertEqual(vpn.nordvpn_setting("enabled", "enabled"), "PASS (enabled)")
        self.assertEqual(vpn.nordvpn_setting("disabled", "enabled"), "REVIEW (disabled)")
        self.assertEqual(vpn.nordvpn_setting("unknown", "enabled"), "UNKNOWN (not verified)")


if __name__ == "__main__":
    unittest.main()
