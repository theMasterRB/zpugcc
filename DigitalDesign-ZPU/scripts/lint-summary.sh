#!/usr/bin/env bash
# Prints a markdown summary of per-block lint results left in <lint-dir> by `make lint`.
# Usage: bash scripts/lint-summary.sh <lint-dir> <block>...

set -uo pipefail

lint_dir=$1
shift

echo "## RTL lint"
echo
echo "| Block | Result | Warnings | Errors |"
echo "|---|---|---|---|"

failed=()
for block in "$@"; do
    status_file="$lint_dir/$block.status"
    log="$lint_dir/$block.log"

    if [ ! -f "$status_file" ]; then
        echo "| $block | not run | - | - |"
        continue
    fi

    status=$(cat "$status_file")
    if [ "$status" = skipped ]; then
        echo "| $block | skipped (no RTL on this branch) | - | - |"
        continue
    fi

    warnings=$(grep -c '^%Warning' "$log")
    # Verilator ends every failing run with "%Error: Exiting due to N warning(s)", which isn't a real error
    errors=$(grep '^%Error' "$log" | grep -vc '^%Error: Exiting due to')

    if [ "$status" = 0 ]; then
        echo "| $block | pass | $warnings | $errors |"
    else
        echo "| $block | **fail** | $warnings | $errors |"
        failed+=("$block")
    fi
done

for block in "${failed[@]-}"; do
    [ -z "$block" ] && continue

    echo
    echo "<details><summary>$block lint output</summary>"
    echo
    echo '```'
    cat "$lint_dir/$block.log"
    echo '```'
    echo
    echo "</details>"
done
