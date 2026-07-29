#!/usr/bin/env bash
# Python frontend unit tests; no host radio commands are invoked.
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${REPO_DIR}"
PYTHONPATH="${REPO_DIR}/src${PYTHONPATH:+:${PYTHONPATH}}" python3 -m unittest discover -s tests/python -v
