#!/usr/bin/env python3
"""Package software-handler tests with all their runtime dependencies included."""
import argparse
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from run_emulated import ROOT, digest
from verify_emulated_bundle import main as verify

README = """# Independent ZPU software-handler tests

This is a self-contained software test suite. It does not require the original
hardware/Tier 0 test suite, its manifest, an add-on installer, or another test
folder. It includes its own checker, macros, prebuilt images, Java 8 adapter,
and the original Zylin Java reference simulator with source and notices.

## Put it on your software/emulated-opcode branch

Copy this entire zpu-emulated-tests folder into your repository's software/
folder. Keep your branch's existing software/crt0Stuff/crt0.S in place.

```text
YourRepo/
  software/
    crt0Stuff/crt0.S       your branch's software handlers
    zpu-emulated-tests/    this independent suite
  simulator/
    zpu_core.cpp           only needed for the C++ backend
    zpu_core.h
```

The test images include the handlers. Their build records check the actual
branch's crt0.S before execution, so different handlers cannot silently be
tested using an old binary. The source is an input being tested, not a dependency
on another test suite. If your handler source differs, rebuild as described below. LF/CRLF line endings
are normalized for this source check; changes to code still require rebuilding.

## Run on Mac or Linux

Requires Python 3.7+ and Java 8+ (Java 17 also works). From your repo root:

```sh
cd software/zpu-emulated-tests
python3 tools/verify_emulated_bundle.py
sh run_emulated_tests.sh reference eq
sh run_emulated_tests.sh reference
```

The small run prints PASS eq: 48 checks. The full run has 26 programs and 1,019
externally checked result words. Eight empty handlers are explicitly reported
as NOT IMPLEMENTED, never as passing. No original hardware tests are launched.
Included bytecode/images avoid a JDK or ZPU compiler requirement for normal runs.

The main command is run_emulated_tests.sh (or tools/run_emulated.py). tools/run.py
is an included local support module used by the checker and Java launcher;
it does not need another test directory. common/tier0.inc contains copied macro
definitions, not hardware test programs.

With the team's simulator source present and a C++11 compiler available:

```sh
sh run_emulated_tests.sh cpp
```

On macOS the g++ command can be Apple's Clang C++ driver. If it is missing,
install the Xcode Command Line Tools. The Java backend does not need C++ tools.

Each run creates a fresh runs/ folder with a summary and per-program RAM dumps,
status, instruction trace and provenance. Both backends must actually dispatch
the opcode to its handler; matching values from native execution are rejected.

## Handler changes and builds

After changing crt0.S or test sources, rebuild with ZPU GCC/binutils:

```sh
python3 tools/run_emulated.py build --tool-prefix /path/to/bin/zpu-elf-
sh run_emulated_tests.sh reference
```

Use the actual installed ZPU toolchain prefix. A normal Mac C compiler cannot
build ZPU assembly. If the toolchain is on PATH, omit --tool-prefix.

Changing generated cases uses tools/generate_emulated.py, followed by rebuilding.
Adapter edits require tools/build_emulated_adapter.py with a Java 11+ build JDK.
Normal execution needs only the included Java 8 bytecode.

## Coverage and checking tools

The 22 implemented families are LOADH, STOREH, LESSTHAN, LESSTHANOREQUAL,
ULESSTHAN, ULESSTHANOREQUAL, MULT, LSHIFTRIGHT, ASHIFTLEFT, CALL, EQ, NEQ,
NEG, SUB, XOR, LOADB, STOREB, EQBRANCH, NEQBRANCH, POPPCREL, PUSHSPADD and
CALLPCREL. Checks include operation results, stack effects and guards, all legal
byte/halfword lanes, branch directions, nested calls and exact return addresses.

SWAP, ASHIFTRIGHT, DIV, MOD, CONFIG, PUSHPC, SYSCALL and HALFMULT are empty in the
supplied source. Counts >=32, unaligned halfwords, interrupts, reset/bootloading,
UART, libraries, timing, automatic hardware fallback and RTL are outside coverage.

```sh
python3 -m unittest discover -s checks -v
python3 tools/check_negative_emulated.py
```

Expect eleven host-side checker/independence tests. The negative execution command also
requires g++ and the team C++ source. It rejects five cases: a broken handler,
timeout, skipped zero-result write, wrong vector stride and native Java bypass.
Two cases use temporary mutant CPU sources; your branch's code is not changed.

Recorded software-handler evidence is under evidence/. Full dumps/traces are
in executions.zip files; compare_emulated.py accepts those directories directly.

```sh
python3 tools/compare_emulated.py evidence/emulated-java8 evidence/emulated-cpp
```

## Merge with the hardware-test branch later

Keep this whole folder together. The hardware suite can remain in
software/zpu-tests, and this suite in software/zpu-emulated-tests. Either can
be removed without breaking the other. Each has its own helpers, configuration,
simulator copy, command and results. The Java simulator bytes may be duplicated;
this deliberately avoids a runtime dependency between branches or test folders.
Keep the upstream simulator source and license notices with either copy.
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    verify()
    direct = ["common/tier0.inc", "common/emulated.inc", "common/emulated.ld",
              "emulated_cases.json", "emulated_manifest.json", "emulated_reference.json",
              "reference.json", "run_emulated_tests.sh", "checks/test_emulated_runner.py",
              "tools/run.py", "tools/run_emulated.py", "tools/generate_emulated.py",
              "tools/EmulationRunner.java", "tools/ReferenceRunner.java", "tools/CppRunner.cpp",
              "tools/compare_emulated.py", "tools/check_negative_emulated.py",
              "tools/build_emulated_adapter.py", "tools/CompileAdapter.java",
              "tools/verify_emulated_bundle.py", "tools/package_emulated_standalone.py",
              "evidence/emulated-trace-comparison.json"]
    files = {name: ROOT / name for name in direct}
    if not (ROOT / "manifest.json").exists() and (ROOT / "VALIDATION.md").is_file():
        files["VALIDATION.md"] = ROOT / "VALIDATION.md"
    if (ROOT / "evidence/independence-validation.json").is_file():
        files["evidence/independence-validation.json"] = ROOT / "evidence/independence-validation.json"
    for directory in ("emulated", "build/emulated", "tools/java8", "tools/emulated-java8",
                      "reference", "evidence/emulated-java8", "evidence/emulated-cpp",
                      "evidence/negative-emulated"):
        for path in sorted((ROOT / directory).rglob("*")):
            if not path.is_file() or path.suffix in (".o", ".map", ".dis", ".pyc"):
                continue
            if "__pycache__" in path.parts or "rebuilt" in path.parts:
                continue
            files[path.relative_to(ROOT).as_posix()] = path
    archives = json.loads((ROOT / "evidence/archives.json").read_text())
    archives = {name: sha for name, sha in archives.items()
                if name.split("/")[0] in ("emulated-java8", "emulated-cpp", "negative-emulated")}
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    prefix = "zpu-emulated-tests/"
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for name, path in sorted(files.items()):
            archive.write(path, prefix + name)
        archive.writestr(prefix + "README.md", README)
        archive.writestr(prefix + "evidence/archives.json", json.dumps(archives, indent=2) + "\n")
        archive.writestr(prefix + ".gitignore", "runs/\n__pycache__/\n*.pyc\n*.o\n*.map\n*.dis\n"
                          "!build/\n!build/emulated/\n!build/emulated/*.bin\n"
                          "!build/emulated/*.elf\n!build/emulated/*.hex\n!build/emulated/*.build.json\n"
                          "!tools/\n!tools/java8/\n!tools/java8/**\n!tools/emulated-java8/\n"
                          "!tools/emulated-java8/**\n!reference/\n!reference/**\n")
        archive.writestr(prefix + ".gitattributes", "common/** -text\nemulated/** -text\n"
                          "emulated_cases.json -text\nemulated_manifest.json -text\n"
                          "emulated_reference.json -text\nreference.json -text\n"
                          "tools/** -text\nreference/** -text -whitespace\nbuild/** -text\n"
                          "build/emulated/*.hex -diff\nevidence/** -text\n"
                          "run_emulated_tests.sh text eol=lf\n")
    output.with_suffix(output.suffix + ".sha256").write_text(digest(output) + "  " + output.name + "\n")
    print(f"PACKAGED INDEPENDENT SUITE: {output} ({output.stat().st_size} bytes)")
    print("Contains no native Tier 0 programs or manifest and needs no add-on installer.")


if __name__ == "__main__":
    main()
