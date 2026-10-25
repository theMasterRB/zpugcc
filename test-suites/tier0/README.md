# Downloadable ZPU Tier 0 test suite

[Download zpu-tier0-suite.zip](zpu-tier0-suite.zip?raw=true).
If GitHub opens a file page, select **Download raw file**.

Extract the archive to get a standalone `zpu-tests/` directory. It contains:

- 19 assembly programs with 500 externally checked result words.
- Build scripts, expected results, a linker layout, and documentation.
- An adapter for the pinned original Zylin Java simulator.
- Built test images and recorded execution evidence.

All 19 programs and 500 result checks passed on the original Zylin Java
simulator. The suite also includes 12 host checks of the result reader and trace
handling, plus evidence that incorrect results, early halts, and execution-budget
exhaustion are rejected. These results do not validate the team's Questa backend,
C++ simulator, or RTL; those require separate runs.

Start with `zpu-tests/README.md`, `COVERAGE.md`, and `VALIDATION.md` after
extraction. The proposed standalone layout uses 32 KiB RAM and no application
startup, bootloader, UART, or emulation vectors. Confirm that layout with the
backend team before integration. The original simulator JAR is not bundled;
its source location, version, and checksum are recorded in `reference.json`.

Build with a ZPU toolchain on PATH:

```sh
cd zpu-tests
python3 tools/run.py build
```

Python 3.7+ is needed for the tools. The optional Java adapter requires Java 11+
with compiler support. Instructions for running and checking results are in the
archive README.

## Archive integrity

SHA-256 of `zpu-tier0-suite.zip`:

```text
e542f43a195bef1708dcbf7910dfa67c0c0806da95dfcbfbc6927a4de8577fd8
```
