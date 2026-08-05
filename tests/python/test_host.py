import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control import host
from fedora_radio_control.system import Result


class HostExposureTests(unittest.TestCase):
    def test_inspector_accepts_injected_read_only_command_boundary(self):
        inspector = host.HostInspector(
            command_exists=lambda name: name == "getenforce",
            command_run=lambda *_args, **_kwargs: Result(0, "Enforcing\n", ""),
        )

        self.assertEqual(inspector.selinux_state(), "enforcing")
        self.assertFalse(inspector.listening_sockets().known)

    def test_listener_collection_counts_only_non_loopback_bindings(self):
        output = (
            "udp UNCONN 0 0 127.0.0.1:323 0.0.0.0:*\n"
            "udp UNCONN 0 0 [::1]:323 [::]:*\n"
            "udp UNCONN 0 0 *:5353 *:*\n"
            "tcp LISTEN 0 4096 0.0.0.0:22 0.0.0.0:*\n"
        )
        with patch.object(host, "exists", return_value=True), patch.object(host, "run", return_value=Result(0, output, "")):
            exposure = host.listening_sockets()

        self.assertEqual(exposure.total, 4)
        self.assertEqual(exposure.network_visible, 2)

    def test_malformed_listener_output_is_unknown_not_safe(self):
        with patch.object(host, "exists", return_value=True), patch.object(host, "run", return_value=Result(0, "bad\n", "")):
            self.assertFalse(host.listening_sockets().known)

    def test_selinux_state_is_strictly_parsed(self):
        with patch.object(host, "exists", return_value=True), patch.object(host, "run", return_value=Result(0, "Enforcing\n", "")):
            self.assertEqual(host.selinux_state(), "enforcing")
        with patch.object(host, "exists", return_value=True), patch.object(host, "run", return_value=Result(0, "unexpected\n", "")):
            self.assertEqual(host.selinux_state(), "unknown")

    def test_gnome_screen_lock_uses_only_lock_related_settings(self):
        results = iter((
            Result(0, "true\n", ""),
            Result(0, "uint32 300\n", ""),
            Result(0, "uint32 0\n", ""),
        ))
        with patch.object(host, "exists", return_value=True), patch.object(host, "run", side_effect=lambda *_args, **_kwargs: next(results)):
            lock = host.screen_lock()

        self.assertEqual(lock, host.ScreenLock(True, True, 300, 0))

    def test_unavailable_gnome_settings_are_not_misreported_as_disabled(self):
        with patch.object(host, "exists", return_value=True), patch.object(host, "run", return_value=Result(1, "", "")):
            self.assertFalse(host.screen_lock().known)
