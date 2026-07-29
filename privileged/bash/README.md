# Privileged Bash Runtime

This directory contains the temporary Bash implementation of the verified,
root-owned mutation helper. It is not part of the normal Python application
and must not be launched directly from a checkout.

`install.sh` copies an explicit allowlist from this directory to
`/usr/local/libexec/fedora-radio-control/`, with root ownership and restrictive
permissions. The Python frontend invokes only that installed helper for radio
changes.

New normal-user features belong under `src/fedora_radio_control/`. New
privileged features must preserve this installed-runtime boundary and include
mocked verification before they replace the remaining Bash helper code.
