# Privileged Bash Runtime

This directory contains the minimal Bash implementation of the verified,
root-owned mutation helper. Read-only collection, reporting, and menus live in
the normal Python application; this tree exists only for narrowly scoped radio
mutations, their concise terminal feedback, and must not be launched from a
checkout.

`lib/display.sh` provides the shared terminal theme used by this helper and
the installer. It never colors logs or non-terminal output.

`install.sh` copies an explicit allowlist from this directory to
`/usr/local/libexec/fedora-radio-control/`, with root ownership and restrictive
permissions. The Python frontend invokes only that installed helper for radio
changes.

New normal-user features belong under `src/fedora_radio_control/`. New
privileged features must preserve this installed-runtime boundary and include
mocked verification.
