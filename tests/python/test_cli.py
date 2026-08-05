import contextlib
import io
import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from fedora_radio_control import cli
from fedora_radio_control.operations import PrivilegedOperation
from fedora_radio_control.system import EXIT_OK, EXIT_USAGE


class CommandDispatchTests(unittest.TestCase):
    def _normal_user(self):
        return patch.object(cli.os, "geteuid", return_value=1000)

    def test_status_uses_read_only_reporter(self):
        with self._normal_user(), patch.object(cli, "require_fedora", return_value=True), patch.object(
            cli.reports, "status", return_value=EXIT_OK
        ) as status:
            result = cli.main(["status"])

        self.assertEqual(result, EXIT_OK)
        status.assert_called_once()

    def test_vpn_uses_the_privacy_safe_read_only_reporter(self):
        with self._normal_user(), patch.object(cli, "require_fedora", return_value=True), patch.object(
            cli.reports, "nordvpn_detail", return_value=EXIT_OK
        ) as detail:
            result = cli.main(["vpn"])

        self.assertEqual(result, EXIT_OK)
        detail.assert_called_once()

    def test_control_commands_delegate_only_the_reviewed_operation(self):
        delegated_commands = (
            (["activity"], PrivilegedOperation.RECENT_ACTIVITY),
            (["lockdown"], PrivilegedOperation.LOCKDOWN),
            (["lockdown", "--non-interactive"], PrivilegedOperation.LOCKDOWN_NON_INTERACTIVE),
            (["wifi", "disable"], PrivilegedOperation.WIFI_DISABLE),
            (["wifi", "enable"], PrivilegedOperation.WIFI_ENABLE),
            (["bluetooth", "disable"], PrivilegedOperation.BLUETOOTH_DISABLE),
            (["bluetooth", "enable"], PrivilegedOperation.BLUETOOTH_ENABLE),
            (["bluetooth", "power", "off"], PrivilegedOperation.BLUETOOTH_POWER_OFF),
            (["bluetooth", "power", "on"], PrivilegedOperation.BLUETOOTH_POWER_ON),
        )
        with self._normal_user(), patch.object(cli, "delegate", return_value=EXIT_OK) as delegate:
            for arguments, operation in delegated_commands:
                with self.subTest(arguments=arguments):
                    self.assertEqual(cli.main(arguments), EXIT_OK)
                    delegate.assert_called_once_with(cli.REPOSITORY, operation)
                    delegate.reset_mock()

    def test_root_is_rejected_before_argument_parsing_or_command_execution(self):
        with (
            patch.object(cli.os, "geteuid", return_value=0),
            patch.object(cli, "build_parser") as parser,
            contextlib.redirect_stderr(io.StringIO()) as error,
        ):
            result = cli.main(["wifi", "disable"])

        self.assertEqual(result, EXIT_USAGE)
        self.assertIn("Do not run Fedora Radio Control as root", error.getvalue())
        parser.assert_not_called()

    def test_ctrl_c_exits_cleanly_without_a_traceback(self):
        with (
            self._normal_user(),
            patch.object(cli, "delegate", side_effect=KeyboardInterrupt) as delegate,
            contextlib.redirect_stderr(io.StringIO()) as error,
        ):
            result = cli.main(["wifi", "disable"])

        self.assertEqual(result, cli.EXIT_INTERRUPTED)
        self.assertIn("Interrupted. Exiting Fedora Radio Control", error.getvalue())
        delegate.assert_called_once_with(cli.REPOSITORY, PrivilegedOperation.WIFI_DISABLE)

    def test_missing_subcommand_is_a_usage_error(self):
        with self._normal_user(), contextlib.redirect_stderr(io.StringIO()):
            for arguments in (["wifi"], ["bluetooth"], ["bluetooth", "power"]):
                with self.subTest(arguments=arguments), self.assertRaises(SystemExit) as raised:
                    cli.main(arguments)

                self.assertEqual(raised.exception.code, EXIT_USAGE)


if __name__ == "__main__":
    unittest.main()
