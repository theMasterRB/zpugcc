# Validation record

Validated against the actual handler and C++ sources added on `opcodes` at
`bf29e0177e061cb72f69cf8e8ab5a079c91138a4`. The suite changes do not modify
`crt0.S`, `zpu_core.cpp` or `zpu_core.h`. These results describe those source
versions, not untested later changes, Questa or RTL.

| Check | Result |
| --- | --- |
| Original Tier 0 on Java 8 | 19 programs / 500 result checks PASS |
| Original Tier 0 on team C++ core | 19 programs / 500 result checks PASS |
| Forced software-handler execution on Java 8 | 26 programs / 1,019 result checks PASS |
| Actual software-handler execution on team C++ core | 26 programs / 1,019 result checks PASS |
| Complete Java/C++ handler traces | All 26 match, including PC, opcode, SP, TOS and NOS |
| Host checker tests | 24 PASS; these are not CPU executions |
| Broken EQ handler | REJECTED: missing completion |
| Exhausted instruction budget | REJECTED: TIMEOUT |
| Mutant C++ core skips an expected-zero result write | REJECTED: exactly slot 6 remains poisoned |
| Mutant C++ core uses 16-byte vector stride | REJECTED |
| Java computes correct EQ results natively | REJECTED: software handler was not dispatched |
| Original Tier 0 negative executions | All three REJECTED AS EXPECTED |
| Bundled upstream simulator source | All 43 files unchanged from pinned upstream |
| Included source/images/Java bytecode | Hashes checked; Java class format 52 (Java 8) |
| Eight empty handler slots | NOT IMPLEMENTED; never counted as passes |
| Team Questa / RTL | NOT RUN |

Java execution used Temurin 1.8.0_472, downloaded from Adoptium's official GitHub
release and checked against its published SHA-256. Normal execution also supports
newer Java runtimes; a software-handler EQ smoke run passed on the workspace's
Java 21 runtime. Java compilation is only needed to regenerate adapter bytecode.

The C++ runner compiles the actual branch's core, rather than a CPU implementation
inside the testing tools. It sets PC/SP for the standalone test contract and
exports pre-execution traces and lower-32-KiB RAM dumps. The original 64-KiB core
reset and instruction implementation remain unchanged.

## Evidence

* `evidence/java-reference/`: fresh native Tier 0 Java 8 execution.
* `evidence/tier0-cpp/`: native Tier 0 C++ execution.
* `evidence/emulated-java8/`: forced software handlers on original Java simulator.
* `evidence/emulated-cpp/`: software handlers on team C++ core.
* `evidence/negative-executions/`: original three Tier 0 negative executions.
* `evidence/negative-emulated/`: five new negative executions.

Each evidence directory includes a readable summary plus `executions.zip`,
which retains the full session with per-program status, RAM dump, trace and
provenance. Archive hashes are pinned in `evidence/archives.json`. The trace
comparison tool accepts these compressed evidence directories directly.
Negative evidence is validation of the checking tools,
not additional successful CPU cases. Two new negative runs use temporary mutant
CPU sources; the others change a handler image, execution budget or dispatch
configuration. Normal program images, source and expectations are unchanged.

These directed cases are not exhaustive verification. The original Tier 0 group
still has its documented dependencies and limitations. Handler tests add result
poisoning and explicit stack checks but do not establish boot/runtime, interrupt,
UART, fault-policy, timing, library or hardware fallback correctness. Shift counts
>=32 and unaligned halfwords await a project specification.
