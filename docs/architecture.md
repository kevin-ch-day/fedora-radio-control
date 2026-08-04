# Architecture

`fedora-radio-control` has two deliberately separate trust domains.

```text
./run.sh
  └── src/fedora_radio_control/       normal-user Python application
        ├── cli.py                    argparse command boundary
        ├── menus.py                  interactive flow
        ├── reports.py                detailed terminal reports
        ├── readiness.py              read-only conference posture checks
        ├── state.py                  radio and connection collection
        ├── system.py                 fixed-vector subprocess calls and helper validation
        └── ui.py                     terminal interaction

sudo /usr/local/libexec/fedora-radio-control/radio-control-privileged
  └── installed copies of privileged/bash/    root-owned Bash mutation runtime
```

## Python frontend

The Python package is dependency-free at runtime and uses a `src/` layout.
The package performs read-only collection and delegates approved changes to a
single, fixed installed helper path. It never constructs a shell command from
user input and does not run Wi-Fi scans, packet capture, or active network
probing.

The public launcher refuses root before importing Python from the checkout.
This prevents accidental `sudo ./run.sh` use from turning normal-user source
code into the privileged frontend; approved changes elevate only at the fixed
installed helper path.

## Privileged runtime

`privileged/bash/` is not a second public application. It is an installation
source tree for the small root-owned mutation runtime. `install.sh` copies an
explicit allowlist to `/usr/local/libexec/fedora-radio-control/`, validates
syntax, and verifies root ownership and non-writable modes before the Python
frontend will delegate a mutation.

The repository `VERSION` and the helper's `PROTOCOL_VERSION` must match. This
protocol advances whenever the runtime or installation contract changes, so a
normal-user dashboard can require an updated installation.

The frontend independently verifies the installed directory and every runtime
file is root-owned, not writable by group or others, and has the exact mode
installed by `install.sh`. A dashboard status of `INSTALLED AND VERIFIED`
therefore reflects both the protocol and the expected deployment permissions.

Keeping this runtime separate prevents a normal-user-owned Python checkout
from becoming the code that executes after privilege elevation.

## Verification

Run the full non-destructive check suite from the repository root:

```bash
./tests/test-static.sh
```

The suite validates the source layout, Python unit tests, Bash helper tests,
entry-point behavior, and the rule that Python frontend modules contain no
direct radio mutation commands or shell execution.
