# Software-emulated opcode tests

The extended suite retains the original Tier 0 tests and adds a separate handler
test group (Tier 1 and above). It runs the actual
[`../crt0Stuff/crt0.S`](../crt0Stuff/crt0.S) handlers from the `opcodes` branch,
not a replacement implementation written by the test suite.

**26 new programs, 1,019 externally checked result words, 22 implemented opcode
families.** Counts include stack and preservation checks; they are not counts of
independent programs. Together with Tier 0: 45 programs / 1,519 result checks.

## Run from this directory

With Python 3.7+ and Java 8+ (no ZPU compiler or Java compiler required):

```sh
python3 tools/verify_bundle.py
sh run_tests.sh
sh run_emulated_tests.sh reference
```

To use the team's current C++ core, install g++ with C++11 support, then:

```sh
sh run_emulated_tests.sh cpp-tier0
sh run_emulated_tests.sh cpp
```

`cpp-tier0` runs the original 19 programs / 500 checks. `cpp` runs the 26 handler
programs / 1,019 checks. The runner compiles `../../simulator/zpu_core.cpp` with
a small execution/export adapter; it does not use the hardcoded demo program in
`zpusim_main.cpp`. The instruction implementation and header remain unchanged.

Run just one group with `sh run_emulated_tests.sh cpp eq`, or
`sh run_emulated_tests.sh reference storeb`. Both accept `--max-instructions`;
the default is 200,000 executed opcode bytes per program, plus a 30-second host
timeout. For a specific runtime/compiler use `--java /path/to/java` or
`--cxx /path/to/g++`. Outputs go to a fresh `runs/` directory, which is printed.

To compare complete traces after full runs on both backends, substitute the two
printed run folders:

```sh
python3 tools/compare_emulated.py runs/emulated-reference-ABC runs/emulated-cpp-XYZ
```

This first rechecks results, dispatch and image provenance, then reports the
first differing pre-execution PC/opcode/SP/TOS/NOS row. It is intended for these
two interpreters; pipelined RTL needs an architectural retirement trace.
It also accepts the packaged `evidence/emulated-java8` and `evidence/emulated-cpp`
directories, temporarily extracting their `executions.zip` files automatically.

## What is checked

| Opcode group | Programs | Result checks | Cases |
| --- | ---: | ---: | --- |
| LESSTHAN, LESSTHANOREQUAL, ULESSTHAN, ULESSTHANOREQUAL | 4 | 192 | Equal and asymmetric operands, signed/unsigned boundaries, extremes |
| EQ, NEQ | 2 | 96 | Equal/unequal zero, positive, negative and mixed-pattern operands |
| SUB, XOR, MULT | 3 | 144 | Operand order, wraparound, zero, extremes and bit patterns |
| NEG | 1 | 36 | Zero, positive/negative values, INT_MIN wraparound |
| PUSHSPADD | 1 | 36 | SP before operand replacement plus four times operand, modulo 32 bits |
| ASHIFTLEFT, LSHIFTRIGHT | 6 | 264 | Every count 0..31; additional zero, one, sign-bit and all-one inputs |
| LOADB, LOADH | 2 | 90 | All valid lanes, big-endian selection, zero extension |
| STOREB, STOREH | 2 | 90 | All valid lanes, truncation, untouched lanes and both adjacent words |
| EQBRANCH, NEQBRANCH | 2 | 48 | Forward/backward, taken/not taken, zero and non-Boolean conditions |
| POPPCREL | 1 | 6 | Forward/backward relative targets and stack effects |
| CALL, CALLPCREL | 2 | 17 | Exact PC+1 return addresses, nested returns, SP and lower guards; backward relative call |

Every ordinary unary/binary case checks its result, remaining SP and a lower
stack guard. Branch/call tests use externally checked path markers and return
addresses. STOREB/H use ordinary word LOAD to inspect the modified word; LOADB/H
inputs are prepared with ordinary word STORE, rather than pairing the two new
instructions and allowing matching bugs to hide one another.

Each result slot is initialized to a value different from its expectation,
including expected zero. A missing result write therefore fails. HALT alone
also fails: completion at 0x1000 and all expected words must match.

The checker additionally requires a trace showing **every executed EMULATE
opcode** entering `(opcode - 32) * 32`, decreasing SP by four and placing PC+1
on top. It requires the instruction under test to dispatch from the application,
including nested emulation performed by handlers. Correct results produced by
a native simulator implementation do not qualify as testing these handlers.

The pinned Java simulator already has a software-dispatch path. Our adapter sets
its existing per-opcode `feeble` flags for all 22 handlers. It does not reimplement
their arithmetic. The original simulator JAR/source and Tier 0 adapter are
unchanged. The upstream dispatch routine rereads its opcode; the new adapter
excludes that lookup and profiler reads from executed-instruction trace counts.

## Platform contract

The same program image runs on both backends:

| Setting | Value |
| --- | --- |
| RAM used/exported | 0x0000..0x7fff, zero initialized, big-endian |
| Vectors | 32-byte slots in 0x0000..0x03ff |
| Out-of-slot handler bodies | Starting at 0x0400; must finish before 0x1000 |
| Completion / results / scratch | Original Tier 0 locations, 0x1000 / 0x1010 / 0x1200..0x15ff |
| Test entry PC | **0x2000**, symbol `main` |
| Initial SP | 0x7ff8; each test explicitly selects SP=0x7800 |
| Test code | 0x2000..0x3fff |
| Interrupts and devices | Disabled / unused |

The C++ core has 64 KiB RAM by default. Its adapter sets the standalone test SP
and exports the agreed lower 32 KiB, without changing the core's reset function.
This is an opcode/handler test platform, not a test of its full memory map.

Start at **main at 0x2000**, not the reset vector. The image includes the team's
complete CRT vectors/bodies, but application initialization, interrupt handling,
bootloading, C ABI and peripherals are outside this test group. This avoids
making every opcode test depend on the CRT's application startup and CALL.

For another backend, load `build/emulated/<name>.bin` at RAM address zero, apply
this contract, and export `status.txt`, the same 8,192-word `dump.hex` format as
Tier 0, and `trace.txt`. Trace fields are hexadecimal pre-execution PC, opcode,
SP, TOS, NOS; one row for every executed opcode byte. Status includes
`HALT instructions=<decimal-count>` only on normal breakpoint termination.

```sh
python3 tools/run_emulated.py check eq runs/your-backend/eq
```

`check` judges existing files; use a fresh output directory for each execution.
It cannot establish when manually supplied files were produced.

## Missing handlers and scope limits

These eight slots in the supplied source are still empty and are reported as
**NOT IMPLEMENTED**, never as passing tests:

| Opcode | Name |
| --- | --- |
| 40 | SWAP |
| 44 | ASHIFTRIGHT |
| 53 | DIV |
| 54 | MOD |
| 58 | CONFIG |
| 59 | PUSHPC |
| 60 | SYSCALL |
| 62 | HALFMULT |

Slots zero and one are reset and interrupt vectors, not additional arithmetic
handlers. Add tests when the remaining handlers and their contracts are ready.
Shift counts >=32 and unaligned halfword accesses are excluded until the team
agrees their required behavior. Interrupts, faults, timing, devices, libraries,
exhaustive/random verification and native-versus-emulated hardware fallback are
also outside this group. Passing handlers do not provide automatic recovery
when an implemented hardware opcode silently computes a wrong result.

## Editing and rebuilding

Keep this folder next to `../crt0Stuff/crt0.S` and two levels below
`../../simulator/zpu_core.cpp` / `zpu_core.h`. Those files are in this repository
and the downloadable combined kit. Changing a handler makes its prebuilt image
records stale; the runner refuses execution until images are rebuilt.

```sh
# If changing generated test cases or expected models:
python3 tools/generate_emulated.py

# After a handler/test change; requires the ZPU toolchain:
python3 tools/run_emulated.py build --tool-prefix /actual/path/to/bin/zpu-elf-

sh run_emulated_tests.sh reference
sh run_emulated_tests.sh cpp
```

The generator replaces its named `.S` sources and `emulated_cases.json`.
Building resolves expected label addresses into `emulated_manifest.json` and
records hashes of source, actual handler source, image and expectations.
Do not change expected results simply to match a simulator disagreement.

Changing `EmulationRunner.java` requires rebuilding the included Java 8 bytecode
with `python3 tools/build_emulated_adapter.py` using a Java 11+ JDK. A build JDK
without `--release 8` symbols can use `--java8-rt-jar /path/to/verified/rt.jar`.
Running the tests still requires only a Java 8+ runtime.

## Validate the checking tools

```sh
python3 -m unittest discover -s checks -v
python3 tools/check_negative_emulated.py
```

Expect 24 host checks and five deliberately unsuccessful executions rejected:
broken EQ handler, timeout, skipped zero-result STORE, wrong vector stride and
Java native execution that produces correct values without running the handler.
Two negative executions use temporary mutant C++ core sources. No normal source,
image or expected result is modified. These negative outcomes test the checker;
they are not extra successful CPU cases.
