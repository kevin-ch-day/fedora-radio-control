import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control.reports import vpn_text
from fedora_radio_control.state import Connections


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


if __name__ == "__main__":
    unittest.main()
