# Downloadable ZPU Tier 0 test suite

[Download zpu-tier0-suite.zip](zpu-tier0-suite.zip?raw=true).
If GitHub opens a file page, select **Download raw file**.

Extract the archive to get a standalone `zpu-tests/` directory. It contains:

- 19 assembly programs with 500 externally checked result words.
- Build scripts, expected results, a linker layout, and documentation.
- An adapter for the pinned original Zylin Java simulator.
- Built test images and recorded execution evidence.

All 19 programs and 500 result checks passed on the original Zylin Java
simulator. The suite also includes 16 host checks of the result reader and trace
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

Python 3.7+ is needed for the tools. The Java adapter runs on Java 8 or newer; a
JRE is sufficient. The package includes its Java 8 class files, so no Java
compiler is required. All 500 result checks were rerun successfully on Java 8.
Instructions for running and checking results are in the archive README.

To run the included images without rebuilding them, use:

```sh
cd zpu-tests
python3 tools/run.py reference immediates --jar /path/to/zpusim.jar
```

## Archive integrity

SHA-256 of `zpu-tier0-suite.zip`:

```text
fa2b3689cbe5867c22f1b7d9f25e05993a7f6faf15d00c79959e8dd830a20bfd
```
