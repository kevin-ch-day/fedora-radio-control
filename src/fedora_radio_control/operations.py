"""Reviewed privileged operation identifiers used by the Python application."""

from enum import Enum


class PrivilegedOperation(str, Enum):
    LOCKDOWN = "lockdown"
    LOCKDOWN_NON_INTERACTIVE = "lockdown-non-interactive"
    WIFI_DISABLE = "wifi-disable"
    WIFI_ENABLE = "wifi-enable"
    BLUETOOTH_DISABLE = "bluetooth-disable"
    BLUETOOTH_ENABLE = "bluetooth-enable"
    BLUETOOTH_POWER_OFF = "bluetooth-power-off"
    BLUETOOTH_POWER_ON = "bluetooth-power-on"
    RECENT_ACTIVITY = "recent-activity"
