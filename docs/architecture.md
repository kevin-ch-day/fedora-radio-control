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

## Privileged runtime

`privileged/bash/` is not a second public application. It is an installation
source tree for the small root-owned mutation runtime. `install.sh` copies an
explicit allowlist to `/usr/local/libexec/fedora-radio-control/`, validates
syntax, and verifies root ownership and non-writable modes before the Python
frontend will delegate a mutation.

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
