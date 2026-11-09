#!/usr/bin/env bash
# Builds and smoke-tests the simulator. Together with scripts/lint.sh this reproduces CI locally.
set -euo pipefail

echo "Starting ZPU CI..."

mkdir -p build

echo "Building simulator..."
make sim 2>&1 | tee build/sim-build.log

echo "Running simulator smoke test..."
./build/zpu_sim 2>&1 | tee build/sim-smoke.log

echo "Checking simulator result..."
grep -Fxq "Result: 7" build/sim-smoke.log

echo "ZPU CI finished successfully."
