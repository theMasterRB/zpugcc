#!/bin/sh
# Run from any current directory; test and simulator paths are package-relative.
set -eu
ZPU_TEST_ROOT=$(CDPATH= cd "$(dirname "$0")" && pwd)
exec python3 "$ZPU_TEST_ROOT/tools/run.py" reference "$@"
