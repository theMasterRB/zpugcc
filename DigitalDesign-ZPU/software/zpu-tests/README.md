# ZPU instruction tests and bundled reference simulator

A self-contained correctness baseline for the required ZPU hardware instructions:
**19 assembly programs and 500 externally checked result words**, plus the
original Zylin Java simulator and its source. The expanded package also adds
**26 software-handler programs / 1,019 result checks** covering all 22 handlers
currently implemented in the team's `crt0.S`. Together: 45 programs / 1,519
checks. See [`EMULATED.md`](EMULATED.md) for coverage, limits and the team C++
backend. No separate simulator download,
Java compiler, ZPU compiler, UART, bootloader, or C library is needed for the
initial run.

## Quick start on Linux / SSH

Requires **Python 3.7+ and Java 8+ JRE** on PATH. All paths are relative; no home
folder layout is assumed. Check versions with `python3 --version` and
`java -version` (one dash works on Java 8).

After extracting this folder or cloning the repository that contains it:

```sh
cd software/zpu-tests
python3 tools/verify_bundle.py
./run_tests.sh immediates
./run_tests.sh
```

The first test prints `PASS immediates: 9 checks`. The full run should produce
19 PASS lines, totaling 500 result checks. If execution permission was lost when
copying files, use `sh run_tests.sh` instead of `./run_tests.sh`.

The `cd` above assumes the extracted combined kit or `DigitalDesign-ZPU` project
root. Once inside this directory, the new software-handler tests run with:

```sh
sh run_emulated_tests.sh reference
```

With g++ available, run both groups on the team's unchanged C++ core:

```sh
sh run_emulated_tests.sh cpp-tier0
sh run_emulated_tests.sh cpp
```

No wrapper script is required if you prefer Python directly:

```sh
python3 tools/run.py reference immediates
python3 tools/run.py reference
```

The bundled simulator is selected automatically. Optional overrides:

```sh
./run_tests.sh poppc --java /path/to/bin/java
./run_tests.sh --max-instructions 20000
```

## How the tests work

Each program sets up known inputs, executes instructions, stores results in
reserved RAM, writes a completion marker, and executes BREAKPOINT. Python reads
that run's exported memory and compares it against `manifest.json`. Tests do not
use EQ/NEQ or software-emulated instructions to judge themselves.

HALT alone is not a pass: both completion and every expected result must match.
These tests exercise required instruction families, not all possible CPU behavior.
See `COVERAGE.md` for the exact cases, dependencies and exclusions.

## Files

| Path | Purpose |
| --- | --- |
| `tier0/*.S` | Assembly test sources |
| `common/` | Shared macros and standalone linker layout |
| `manifest.json` | Expected values and descriptions, one entry per result slot |
| `build/` | Included ELF/binary/hex images and source/image freshness records |
| `tools/run.py` | Build, launch reference, or judge another backend's output |
| `tools/ReferenceRunner.java` | Our adapter around the original simulator |
| `tools/java8/*.class` | Included adapter bytecode, checked against source/hash records |
| `reference/zylin/simulator/zpusim.jar` | Unmodified original Zylin simulator |
| `reference/zylin/simulator/com/` | Upstream Java source from the pinned commit |
| `reference/zylin/COPYING` | Original upstream licensing notice |
| `reference/zylin/UPSTREAM.json` | Provenance and hashes of all copied simulator files |
| `checks/` | Host tests of the checking tools; these are not CPU tests |
| `evidence/` | Recorded baseline executions |
| `runs/` | Fresh local executions; ignored by Git |
| `emulated/*.S`, `emulated_manifest.json` | New handler test programs and external expectations |
| `tools/run_emulated.py` | Build/run/check handler tests; also run Tier 0 on the team C++ core |
| `EMULATED.md` | Handler coverage, forced dispatch, platform and rebuilding instructions |

## Where the simulator came from

Upstream: https://github.com/zylin/zpu

Pinned revision: `e29aef5f7aa741557d0eb16ecf13e974d55789ff`

Original directory: `zpu/sw/simulator/`

The original JAR and the entire simulator source directory were copied unchanged.
The JAR SHA-256 is pinned in `reference.json`; the adapter rejects substitutions.
`REFERENCE_SOURCE.md` links the exact upstream files and explains provenance and
license notices. This is the historical Java implementation, not the team's C++
simulator or RTL. Our adapter changes the test platform configuration and exports
results; it does not implement the instruction semantics.

## Results and troubleshooting

Each invocation creates a fresh `runs/java-ref-*/` folder and prints its location.
At its top level, `summary.json` records outcomes, runtime version and provenance.
Each test has `status.txt`, `dump.hex`, `trace.txt`, backend stdout/stderr and image,
manifest/adapter hashes. Trace rows are PRE-execution PC, opcode, SP, TOS, NOS;
profiler reads are excluded from the instruction count.

* PASS: completion and every result matched.
* FAIL: a result differed; the message identifies its slot/address.
* ERROR: execution, image freshness, checksum, trace or file-format problem.
* TIMEOUT/IO_ACCESS/FAULT: execution was unsuccessful, even if memory looks right.

The architectural instruction budget and host timeout are separate limits. The
host timeout is 30 seconds per program. Keep a failing run folder when reporting
issues; do not edit expected values just to make a disagreement pass.

Host safeguards and deliberately bad reference executions:

```sh
python3 -m unittest discover -s checks -v
python3 tools/check_negative_runs.py
```

Expect 24 host tests to pass and three `REJECTED AS EXPECTED` messages. The latter
uses corrupted PROGRAMS / incomplete execution, not mutant CPU cores.

## Standalone test platform

| Setting | Value |
| --- | --- |
| Writable RAM | 0x0000..0x7fff, 32 KiB, zero initialized |
| Entry PC | 0x00000000 |
| Initial/baseline SP | 0x00007ff8; pushes decrease SP |
| Code | Below 0x1000 |
| Completion | Word at 0x1000 must equal 0x5a505530 |
| Result slots | 0x1010 + 4*n, at most 60 slots per program |
| Scratch | 0x1200..0x15ff |
| Stack | 0x7000..0x7fff; tests also select SP=0x7800 and 0x7400 |
| Byte order | Big-endian |
| Interrupts / devices | Disabled / unexpected I/O rejected |

There are no emulation vectors or application startup in these Tier 0 images.
Confirm this standalone layout before integrating another backend. Changing the
layout requires coordinated changes to common files, manifest and adapter.

## Using the future C++ simulator / RTL

Load `build/<name>.bin` at zero and use the platform contract above. Export a
fresh `status.txt` starting with HALT only on normal breakpoint termination, and
`dump.hex` containing exactly 8192 known eight-digit hex words starting at RAM
address zero. Line 1 is address zero, line 2 address four. No headers or X/Z.

Then judge those files without Java:

```sh
python3 tools/run.py check immediates runs/cpp-001/immediates
```

The included team C++ adapter can now launch these Tier 0 images with
`sh run_emulated_tests.sh cpp-tier0`. For a different simulator or RTL,
the external `check` command cannot establish freshness/provenance of manually
selected result files. Handler images use a different entry PC; see EMULATED.md.

## Editing and rebuilding

For assembly changes, install/select the ZPU toolchain, then:

```sh
python3 tools/run.py build --tool-prefix /actual/path/to/bin/zpu-elf-
./run_tests.sh
```

The original four tests are hand-written; additional table-driven cases are
regenerated by deliberately running `tools/expand_cases.py`. That command
replaces its named source files and manifest entries. Rebuild afterwards.

Adapter source edits require regeneration of its bytecode/hash records via
`python3 tools/build_adapter.py`. This BUILD operation requires a Java 11+ JDK;
normal test execution still needs only Java 8. For stripped build JDKs, supply
`--java8-rt-jar /path/to/verified/java8/lib/rt.jar`.

## Adding this folder to another repository

Keep this complete folder at `software/zpu-tests`, alongside the team's
`software/crt0Stuff/crt0.S` and `simulator/zpu_core.cpp` / `zpu_core.h`. The
combined downloadable kit includes all three locations and the software-level
Git attributes that preserve handler bytes. There is no nested Git repository
or Git submodule. The bundled simulator notice/source must stay with it.

The local `.gitignore` deliberately retains prebuilt images, build records,
adapter class files and the simulator JAR, while excluding new run outputs and
Python caches. Check your repository's ignore rules and staged files before
committing: a clean clone needs those prebuilt assets. `.gitattributes` preserves
bytes used in checksum/freshness checks. `PR_DESCRIPTION.md` is a suggested PR
body; review and adapt it to your repository.

Both test groups have been executed on the original Java simulator and the
team's C++ core from the `opcodes` branch. RTL is not validated by these runs.
Reference disagreements should be investigated against the agreed ISA rather
than treating any implementation as infallible.
