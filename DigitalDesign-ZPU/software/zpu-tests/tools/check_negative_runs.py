#!/usr/bin/env python3
"""Prove the external checker rejects actual bad/incomplete reference executions.

These deliberately corrupted PROGRAMS are not modified CPU implementations.
They are kept outside the normal test manifest and never count as passing CPU
tests. This command does not modify normal source or build artifacts.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from run import ROOT, judge, read_manifest, reference_command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", type=Path, default=ROOT / "reference/zylin/simulator/zpusim.jar")
    parser.add_argument("--java", default="java", help="Java 8+ executable name or path")
    args = parser.parse_args()
    jar = args.jar.resolve()
    reference = json.loads((ROOT / "reference.json").read_text())
    if hashlib.sha256(jar.read_bytes()).hexdigest() != reference["jar_sha256"]:
        raise ValueError("Reference JAR checksum mismatch")
    command_prefix = reference_command(jar, args.java)
    raw = (ROOT / "build/addition.bin").read_bytes()
    first_add = raw.index(bytes([5]))
    wrong_result = raw[:first_add] + bytes([6]) + raw[first_add + 1:]
    early_halt = raw[:first_add] + bytes([0]) + raw[first_add + 1:]
    cases = [("wrong_result_add_changed_to_and", wrong_result, 20000, "mismatch"),
             ("early_breakpoint", early_halt, 20000, "Incomplete execution"),
             ("instruction_budget", raw, 1, "did not halt normally")]
    (ROOT / "runs").mkdir(exist_ok=True)
    session = Path(tempfile.mkdtemp(prefix="negative-", dir=ROOT / "runs"))
    evidence = {"reference": reference, "negative_cases": []}
    for name, image, budget, reason in cases:
        directory = session / name
        directory.mkdir()
        image_path = directory / "negative.bin"
        image_path.write_bytes(image)
        command = command_prefix + [str(image_path), str(directory), str(budget)]
        process = subprocess.run(command, capture_output=True, text=True, timeout=30)
        (directory / "backend.stdout").write_text(process.stdout)
        (directory / "backend.stderr").write_text(process.stderr)
        if process.returncode:
            raise RuntimeError(process.stderr)
        error_message = None
        try:
            failures = judge("addition", directory, read_manifest())
        except ValueError as error:
            error_message = str(error)
            failures = []
        if reason == "mismatch":
            assert len(failures) == 1 and "slot 0" in failures[0], failures
        else:
            assert error_message is not None and reason in error_message, error_message
        evidence["negative_cases"].append({
            "name": name, "outcome": "REJECTED_AS_EXPECTED", "budget": budget,
            "image_sha256": hashlib.sha256(image).hexdigest(),
            "failures": failures, "execution_error": error_message})
        print(f"REJECTED AS EXPECTED: {name}")
    (session / "summary.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"Negative execution evidence: {session}")


if __name__ == "__main__":
    main()
