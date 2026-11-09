#!/usr/bin/env python3
"""Actual negative executions; no normal inputs or CPU sources are changed."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

import run_emulated as runner
import run as tier0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java", default="java")
    args = parser.parse_args()
    definition = runner.spec()
    manifest = json.loads((runner.ROOT / "emulated_manifest.json").read_text())
    image, record = runner.load_image("eq")
    original = image.read_bytes()
    command, metadata = runner.compile_cpp("g++")
    session = Path(tempfile.mkdtemp(prefix="negative-emulated-", dir=runner.ROOT / "runs"))
    cases = []

    # Replace the first handler instruction, not the application's EQ opcode.
    broken = bytearray(original)
    broken[(46 - 32) * 32] = 0
    cases.append(("broken_eq_handler", bytes(broken), 200000, "Incomplete execution"))

    cases.append(("instruction_budget", original, 1, "did not halt normally"))
    outcomes = []
    for name, raw, budget, expected_error in cases:
        directory = session / name
        directory.mkdir()
        test_image = directory / "negative.bin"
        test_image.write_bytes(raw)
        runner.execute(command, "cpp", "eq", test_image, directory, budget, definition)
        try:
            failures = tier0.judge("eq", directory, manifest)
            error = "\n".join(failures)
        except ValueError as problem:
            error = str(problem)
        if expected_error not in error:
            raise AssertionError(f"{name}: expected {expected_error!r}, got {error!r}")
        outcomes.append({"name": name, "outcome": "REJECTED_AS_EXPECTED", "reason": error,
                         "image_sha256": runner.digest(test_image)})
        print("REJECTED AS EXPECTED:", name)
    # Real mutant CPU cores. The skipped zero write must fail even though the
    # stack effects, completion marker and all other result writes are correct.
    core_source = (runner.CORE / "zpu_core.cpp").read_text()
    assert core_source.count("cpu.pc = x * 32;") == 1
    assert manifest["tests"]["eq"][6][0] == "0x00000000"
    signature = "void write32(Cpu &cpu, uint32_t addr, uint32_t value) {"
    assert core_source.count(signature) == 1
    mutants = [
        ("missing_zero_result_write", core_source.replace(
            signature, signature + "\n    if (addr == 0x1028 && value == 0) return;")),
        ("wrong_vector_stride", core_source.replace("cpu.pc = x * 32;", "cpu.pc = x * 16;")),
    ]
    for name, source in mutants:
        directory = session / name
        directory.mkdir()
        mutant = directory / "zpu_core.cpp"
        mutant.write_text(source)
        executable = directory / "mutant-cpp"
        subprocess.run(["g++", "-std=c++11", "-O2", "-I", str(runner.CORE), str(mutant),
                        str(runner.ROOT / "tools/CppRunner.cpp"), "-o", str(executable)], check=True)
        runner.execute([str(executable)], "cpp", "eq", image, directory, 200000, definition)
        try:
            failures = tier0.judge("eq", directory, manifest)
            runner.validate_trace(original, directory, record, {int(n) for n in definition["implemented"]})
        except ValueError as problem:
            failures = [str(problem)]
        if not failures:
            raise AssertionError(name + ": mutant CPU unexpectedly passed")
        if name == "missing_zero_result_write" and not (len(failures) == 1 and "slot 6" in failures[0]):
            raise AssertionError("Expected only the skipped zero result to fail: " + repr(failures))
        outcomes.append({"name": name, "outcome": "REJECTED_AS_EXPECTED",
                         "reason": failures, "mutant_source_sha256": runner.digest(mutant)})
        print("REJECTED AS EXPECTED:", name, "(mutant CPU)")
    # Actually run the Java simulator's native EQ implementation. It produces
    # matching result words, but must not qualify as testing the EQ software.
    directory = session / "native_bypass"
    directory.mkdir()
    java, java_metadata = runner.java_command(args.java)
    native_definition = dict(definition)
    native_definition["implemented"] = {"34": "loadh"} # EQ stays native.
    runner.execute(java, "reference", "eq", image, directory, 200000, native_definition)
    if tier0.judge("eq", directory, manifest):
        raise AssertionError("Native bypass fixture must have correct result words")
    try:
        runner.validate_trace(original, directory, record, {int(n) for n in definition["implemented"]})
    except ValueError as problem:
        error = str(problem)
    else:
        raise AssertionError("Native execution was accepted as software emulation")
    if "Missing software dispatch" not in error:
        raise AssertionError(error)
    outcomes.append({"name": "native_bypass", "outcome": "REJECTED_AS_EXPECTED", "reason": error,
                     "backend": java_metadata})
    print("REJECTED AS EXPECTED: native_bypass (correct values, software not executed)")
    runner.write_json(session / "summary.json", {"backend": metadata, "negative_cases": outcomes})
    print("Negative execution evidence:", session)


if __name__ == "__main__":
    main()
