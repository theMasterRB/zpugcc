#!/usr/bin/env python3
"""Build native Tier 0 images, launch the pinned Java reference, or judge RAM dumps.

This tool does not implement a CPU. Its reference command creates fresh Java
execution folders; check judges files exported by another backend.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def read_manifest():
    manifest = json.loads((ROOT / "manifest.json").read_text())
    for name, cases in manifest["tests"].items():
        if not cases or len(cases) > 60:
            raise ValueError(f"{name}: need 1..60 checks within reserved result area")
    return manifest


def number(value):
    return int(value, 0) if isinstance(value, str) else value


def find_tool(prefix, name):
    executable = shutil.which(prefix + name)
    if executable is None:
        raise ValueError(f"Cannot find {prefix + name}; activate the toolchain "
                         "or pass --tool-prefix /path/to/bin/zpu-elf-")
    return executable


def binary_to_hex(raw):
    padded = raw + b"\0" * (-len(raw) % 4)
    return "".join(padded[i:i + 4].hex() + "\n"
                   for i in range(0, len(padded), 4))


def source_hashes(name):
    paths = [f"tier0/{name}.S", "common/tier0.inc", "common/test.ld", "manifest.json"]
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in paths}


def check_opcodes(raw):
    # These images contain code only: inspect EVERY byte, not disassembly text.
    # No opcode in the software emulation range 32..63 may be emitted.
    if len(raw) > 0x1000:
        raise ValueError("Code overlaps the reserved result area at 0x1000")
    singles = {0, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13}
    for pc, opcode in enumerate(raw):
        if opcode not in singles and not (16 <= opcode <= 31 or opcode >= 64):
            raise ValueError(f"Non-Tier-0 opcode 0x{opcode:02x} at 0x{pc:x}")
    if not raw or raw[-1] != 0 or raw.count(0) != 1:
        raise ValueError("Expected exactly one BREAKPOINT, at the end of code")


def build(name, prefix):
    output = ROOT / "build"
    output.mkdir(exist_ok=True)
    stem = output / name
    assembler = find_tool(prefix, "as")
    linker = find_tool(prefix, "ld")
    objcopy = find_tool(prefix, "objcopy")
    objdump = find_tool(prefix, "objdump")
    subprocess.run([assembler, "-I", str(ROOT / "common"),
                    "-o", str(stem.with_suffix(".o")),
                    str(ROOT / "tier0" / f"{name}.S")], check=True)
    subprocess.run([linker, "-T", str(ROOT / "common/test.ld"),
                    "-Map=" + str(stem.with_suffix(".map")),
                    "-o", str(stem.with_suffix(".elf")),
                    str(stem.with_suffix(".o"))], check=True)
    subprocess.run([objcopy, "-O", "binary", str(stem.with_suffix(".elf")),
                    str(stem.with_suffix(".bin"))], check=True)
    raw = stem.with_suffix(".bin").read_bytes()
    check_opcodes(raw)
    stem.with_suffix(".hex").write_text(binary_to_hex(raw))
    disassembly = subprocess.run(
        [objdump, "-h", "-d", str(stem.with_suffix(".elf"))],
        check=True, capture_output=True, text=True).stdout
    stem.with_suffix(".dis").write_text(disassembly)
    stem.with_suffix(".build.json").write_text(json.dumps({
        "sources": source_hashes(name),
        "image_sha256": hashlib.sha256(raw).hexdigest(),
        "assembler": assembler, "linker": linker}, indent=2) + "\n")
    print(f"BUILT {name}: {len(raw)} code bytes; required opcodes only")


def judge(name, run_dir, manifest):
    status_file = run_dir / "status.txt"
    dump_file = run_dir / "dump.hex"
    status = status_file.read_text().strip()
    if not re.match(r"^HALT\b", status):
        raise ValueError(f"Execution did not halt normally: {status!r}")
    lines = dump_file.read_text().splitlines()
    expected_words = number(manifest["layout"]["ram_bytes"]) // 4
    if len(lines) != expected_words:
        raise ValueError(f"Expected full RAM dump ({expected_words} words), "
                         f"got {len(lines)}")
    for line_num, line in enumerate(lines, 1):
        if re.fullmatch(r"[0-9a-fA-F]{8}", line.strip()) is None:
            raise ValueError(f"Malformed/unknown memory word at dump line {line_num}")
    words = [int(line.strip(), 16) for line in lines]
    layout = manifest["layout"]
    completion = words[number(layout["completion_address"]) // 4]
    if completion != number(layout["completion_value"]):
        raise ValueError(f"Incomplete execution: completion marker is "
                         f"0x{completion:08x}, not {layout['completion_value']}")
    base = number(layout["result_address"])
    failures = []
    for slot, (expected, description) in enumerate(manifest["tests"][name]):
        address = base + 4 * slot
        actual = words[address // 4]
        if actual != number(expected):
            failures.append(f"slot {slot} @ 0x{address:04x}: {description}; "
                            f"expected {expected}, got 0x{actual:08x}")
    return failures


def validate_trace(raw, run_dir):
    rows = [line.split() for line in (run_dir / "trace.txt").read_text().splitlines()
            if line.strip() and not line.startswith("#")]
    if not rows or any(len(row) != 5 for row in rows):
        raise ValueError("Expected five fields per instruction trace row")
    parsed = [[int(field, 16) for field in row] for row in rows]
    for pc, opcode, sp, _, _ in parsed:
        if pc >= len(raw) or opcode != raw[pc] or sp % 4 or not 0 <= sp <= 32764:
            raise ValueError("Trace disagrees with image or has invalid stack state")
    if parsed[0][0] != 0 or parsed[-1][:2] != [len(raw) - 1, 0]:
        raise ValueError("Trace must start at entry and finish at final BREAKPOINT")
    if 4 not in raw:  # no POPPC: all these programs are straight-line code
        if [row[0] for row in parsed] != list(range(len(raw))):
            raise ValueError("Straight-line trace must have one row per code byte")
    count = re.search(r"\binstructions=(\d+)", (run_dir / "status.txt").read_text())
    if count is None or int(count[1]) != len(rows):
        raise ValueError("Instruction budget/count does not match trace rows")


def reference_command(jar, java_name="java"):
    reference = json.loads((ROOT / "reference.json").read_text())
    jar = jar.resolve()
    if hashlib.sha256(jar.read_bytes()).hexdigest() != reference["jar_sha256"]:
        raise ValueError("Reference JAR does not match the pinned upstream checksum")
    bytecode = reference["adapter_bytecode"]
    source = ROOT / reference["adapter"]
    if hashlib.sha256(source.read_bytes()).hexdigest() != bytecode["source_sha256"]:
        raise ValueError("Adapter source changed; rebuild with tools/build_adapter.py")
    directory = ROOT / bytecode["directory"]
    for name, expected in bytecode["classes"].items():
        raw = (directory / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError(f"Adapter class {name} does not match its pinned checksum")
        if raw[:4] != bytes.fromhex("cafebabe") or int.from_bytes(raw[6:8], "big") != 52:
            raise ValueError(f"Adapter class {name} is not in Java 8 format")
    java = shutil.which(java_name)
    if java is None:
        raise ValueError("Java 8+ runtime is required; put java on PATH or pass --java")
    return [java, "-cp", os.pathsep.join([str(directory), str(jar)]), "ReferenceRunner"]


def run_reference(names, jar, budget, manifest, java_name="java"):
    reference = json.loads((ROOT / "reference.json").read_text())
    command_prefix = reference_command(jar, java_name)
    if manifest["layout"] != {"ram_bytes": 32768, "completion_address": "0x1000",
                              "completion_value": "0x5a505530", "result_address": "0x1010"}:
        raise ValueError("Java adapter requires the documented 32 KiB test layout")
    output = ROOT / "runs"
    output.mkdir(exist_ok=True)
    session = Path(tempfile.mkdtemp(prefix="java-ref-", dir=output))
    version = subprocess.run([command_prefix[0], "-version"],
                             capture_output=True, text=True, timeout=10)
    if version.returncode:
        raise ValueError("Unable to run java -version: " + version.stderr.strip())
    summary = {"reference": reference, "java_version": version.stderr.strip() or version.stdout.strip(),
               "results": []}
    failed = False
    for name in names:
        image = ROOT / "build" / f"{name}.bin"
        raw = image.read_bytes()
        check_opcodes(raw)
        build_record = json.loads(image.with_suffix(".build.json").read_text())
        if (build_record["sources"] != source_hashes(name) or
                build_record["image_sha256"] != hashlib.sha256(raw).hexdigest()):
            raise ValueError(f"{name}: image or sources changed; rebuild before execution")
        directory = session / name
        directory.mkdir()
        command = command_prefix + [str(image), str(directory), str(budget)]
        metadata = {"name": name, "image_sha256": hashlib.sha256(raw).hexdigest(),
                    "manifest_sha256": hashlib.sha256((ROOT / "manifest.json").read_bytes()).hexdigest(),
                    "adapter_sha256": hashlib.sha256((ROOT / "tools/ReferenceRunner.java").read_bytes()).hexdigest(),
                    "adapter_classes": reference["adapter_bytecode"]["classes"],
                    "max_instructions": budget, "command": command}
        (directory / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
        try:
            process = subprocess.run(command, capture_output=True, text=True, timeout=30)
            (directory / "backend.stdout").write_text(process.stdout)
            (directory / "backend.stderr").write_text(process.stderr)
            if process.returncode:
                raise ValueError(f"Java adapter exited {process.returncode}: {process.stderr.strip()}")
            failures = judge(name, directory, manifest)
            validate_trace(raw, directory)
            result = {**metadata, "checks": len(manifest["tests"][name]),
                      "outcome": "FAIL" if failures else "PASS", "failures": failures}
        except (ValueError, OSError, subprocess.TimeoutExpired) as error:
            result = {**metadata, "outcome": "ERROR", "error": str(error)}
        failed |= result["outcome"] != "PASS"
        summary["results"].append(result)
        print(f"{result['outcome']} {name}: " +
              (str(result["checks"]) + " checks" if "checks" in result else result["error"]))
        for failure in result.get("failures", []):
            print("  " + failure)
    (session / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Fresh execution evidence: {session}")
    return 1 if failed else 0


def main():
    manifest = read_manifest()
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("name", nargs="?", default="all",
                              choices=["all", *manifest["tests"]])
    build_parser.add_argument("--tool-prefix", default="zpu-elf-")
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("name", choices=list(manifest["tests"]))
    check_parser.add_argument("run_dir", type=Path,
                              help="directory with fresh status.txt and full dump.hex")
    ref_parser = subparsers.add_parser("reference", help="execute on pinned original Java simulator")
    ref_parser.add_argument("name", nargs="?", default="all", choices=["all", *manifest["tests"]])
    ref_parser.add_argument("--jar", type=Path, default=ROOT / "reference/zylin/simulator/zpusim.jar")
    ref_parser.add_argument("--java", default="java", help="Java 8+ executable name or path")
    ref_parser.add_argument("--max-instructions", type=int, default=20000)
    args = parser.parse_args()
    try:
        if args.command == "build":
            names = manifest["tests"] if args.name == "all" else [args.name]
            for name in names:
                build(name, args.tool_prefix)
        elif args.command == "reference":
            if args.max_instructions <= 0:
                raise ValueError("Instruction budget must be positive")
            names = list(manifest["tests"]) if args.name == "all" else [args.name]
            return run_reference(names, args.jar, args.max_instructions, manifest, args.java)
        else:
            failures = judge(args.name, args.run_dir, manifest)
            if failures:
                for failure in failures:
                    print(f"FAIL {args.name}: {failure}", file=sys.stderr)
                return 1
            print(f"PASS {args.name}: {len(manifest['tests'][args.name])} checks")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
