import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control import reports
from fedora_radio_control.reports import vpn_text
from fedora_radio_control.state import Connections
from fedora_radio_control.system import EXIT_POLICY
from fedora_radio_control.vpn import NordVPNPosture


class CaptureUI:
    def __init__(self):
        self.labels: list[tuple[str, str]] = []
        self.notes: list[str] = []

    def heading(self, _value: str) -> None:
        pass

    def section(self, _value: str) -> None:
        pass

    def label(self, name: str, value: object) -> None:
        self.labels.append((name, str(value)))

    def note(self, value: str) -> None:
        self.notes.append(value)

    def result(self, value: str) -> str:
        return value


class ReportFormattingTests(unittest.TestCase):
    def test_vpn_summary_is_sanitized_for_each_connection_state(self):
        self.assertEqual(
            vpn_text(Connections("not connected", "active", 2, "1h 01m")),
            "INFORMATIONAL (2 active; approx. 1h 01m)",
        )
        self.assertEqual(
            vpn_text(Connections("not connected", "inactive", 0, "not connected")),
            "INFORMATIONAL (none detected)",
        )
        self.assertEqual(
            vpn_text(Connections("not connected", "unknown", 0, "unknown (query failed)")),
            "UNKNOWN (unknown (query failed))",
        )

    def test_nordvpn_detail_contains_only_safe_posture_fields(self):
        posture = NordVPNPosture(
            available=True,
            status="connected",
            technology="nordlynx",
            kill_switch="disabled",
            auto_connect="disabled",
            routing="enabled",
            lan_discovery="disabled",
            meshnet="disabled",
        )
        ui = CaptureUI()
        with patch.object(reports, "nordvpn_posture", return_value=posture):
            result = reports.nordvpn_detail(ui)

        self.assertEqual(result, EXIT_POLICY)
        fields = dict(ui.labels)
        self.assertEqual(fields["Client:"], "PASS (connected)")
        self.assertEqual(fields["Technology:"], "NORDLYNX (WireGuard-based)")
        self.assertEqual(fields["Kill Switch:"], "REVIEW (disabled)")
        self.assertNotIn("Server:", fields)
        self.assertNotIn("IP:", fields)
        self.assertNotIn("DNS:", fields)
        self.assertNotIn("Account:", fields)


if __name__ == "__main__":
    unittest.main()
