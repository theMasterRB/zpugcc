#!/bin/sh
set -eu
suite_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$suite_dir/tools/run_emulated.py" "$@"
