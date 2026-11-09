#!/usr/bin/env python3
"""Build/run handler tests, requiring actual EMULATE vector dispatch in traces."""
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

import run as tier0

ROOT = tier0.ROOT
CORE = ROOT.parent.parent / "simulator"


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def spec():
    return json.loads((ROOT / "emulated_cases.json").read_text())


def sources(name):
    paths = ["emulated/" + name + ".S", "common/emulated.inc", "common/tier0.inc",
             "common/emulated.ld", "emulated_cases.json", spec()["handler_source"]]
    return {path: digest(ROOT / path) for path in paths}


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n")


def build(prefix):
    definition = spec()
    output = ROOT / "build/emulated"
    output.mkdir(parents=True, exist_ok=True)
    crt = output / "crt0.o"
    # .S needs the C preprocessor for // comments; use the real team's source.
    subprocess.run([tier0.find_tool(prefix, "gcc"), "-c",
                    str(ROOT / definition["handler_source"]), "-o", str(crt)], check=True)
    manifest = {"layout": definition["layout"], "tests": {}}
    records = {}
    for name, case in definition["tests"].items():
        stem = output / name
        subprocess.run([tier0.find_tool(prefix, "as"), "-I", str(ROOT / "common"),
                        "-o", str(stem.with_suffix(".o")),
                        str(ROOT / "emulated" / (name + ".S"))], check=True)
        subprocess.run([tier0.find_tool(prefix, "ld"), "-T", str(ROOT / "common/emulated.ld"),
                        "-o", str(stem.with_suffix(".elf")), str(crt),
                        str(stem.with_suffix(".o"))], check=True)
        subprocess.run([tier0.find_tool(prefix, "objcopy"), "-O", "binary",
                        str(stem.with_suffix(".elf")), str(stem.with_suffix(".bin"))], check=True)
        nm = subprocess.run([tier0.find_tool(prefix, "nm"), str(stem.with_suffix(".elf"))],
                            check=True, capture_output=True, text=True).stdout
        symbols = {}
        for line in nm.splitlines():
            fields = line.split()
            if len(fields) == 3 and fields[1].upper() != "U":
                symbols[fields[2]] = int(fields[0], 16)
        sections = subprocess.run([tier0.find_tool(prefix, "objdump"), "-h",
                                   str(stem.with_suffix(".elf"))], check=True,
                                  capture_output=True, text=True).stdout
        ranges = []
        for section in (".fixed_vectors", ".runtime", ".test"):
            match = re.search(r"\s" + re.escape(section) + r"\s+([0-9a-f]+)\s+([0-9a-f]+)", sections)
            if not match:
                raise ValueError("Missing executable section " + section)
            length, start = (int(v, 16) for v in match.groups())
            ranges.append([start, start + length])
        raw = stem.with_suffix(".bin").read_bytes()
        implemented = {int(n) for n in definition["implemented"]}
        for start, end in ranges:
            for pc in range(start, end):
                op = raw[pc]
                if op not in {0, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13} and not (
                        16 <= op <= 31 or op >= 64 or op in implemented):
                    raise ValueError(f"Unsupported opcode {op} in {name} at {pc:#x}")
        stem.with_suffix(".hex").write_text(tier0.binary_to_hex(raw))
        expected = []
        for value, description in case["expected"]:
            if value.startswith("symbol:"):
                value = f"0x{symbols[value.split(':', 1)[1]]:08x}"
            expected.append([value, description])
        manifest["tests"][name] = expected
        records[name] = {"sources": sources(name), "image_sha256": digest(stem.with_suffix(".bin")),
                         "entry_pc": symbols["main"], "final_pc": symbols["_test_break"],
                         "code_ranges": ranges, "opcode": case["opcode"]}
    write_json(ROOT / "emulated_manifest.json", manifest)
    for name, record in records.items():
        record["manifest_sha256"] = digest(ROOT / "emulated_manifest.json")
        write_json(output / (name + ".build.json"), record)
    print(f"BUILT {len(records)} emulated images against {definition['handler_source']}")


def compile_cpp(cxx):
    compiler = shutil.which(cxx)
    if compiler is None:
        raise ValueError("C++ compiler missing; install g++ or pass --cxx")
    directory = ROOT / "runs/tools"
    directory.mkdir(parents=True, exist_ok=True)
    binary = directory / "cpp-runner"
    command = [compiler, "-std=c++11", "-Wall", "-Wextra", "-O2", "-I", str(CORE),
               str(CORE / "zpu_core.cpp"), str(ROOT / "tools/CppRunner.cpp"), "-o", str(binary)]
    subprocess.run(command, check=True, capture_output=True, text=True)
    metadata = {"core_sources": {str(p.relative_to(ROOT.parent.parent)): digest(p)
                                for p in (CORE / "zpu_core.cpp", CORE / "zpu_core.h")},
                "adapter_sha256": digest(ROOT / "tools/CppRunner.cpp"),
                "executable_sha256": digest(binary), "compile_command": command}
    return [str(binary)], metadata


def java_command(java):
    jar = ROOT / "reference/zylin/simulator/zpusim.jar"
    command = tier0.reference_command(jar, java)
    record = json.loads((ROOT / "emulated_reference.json").read_text())
    directory = ROOT / record["directory"]
    if digest(ROOT / "tools/EmulationRunner.java") != record["source_sha256"]:
        raise ValueError("Emulation adapter source changed; rebuild Java bytecode")
    for name, expected in record["classes"].items():
        raw = (directory / name).read_bytes()
        if digest(directory / name) != expected or raw[:8] != bytes.fromhex("cafebabe00000034"):
            raise ValueError("Emulation adapter bytecode checksum/Java 8 format mismatch")
    command[2] = str(directory) + os.pathsep + command[2]
    command[-1] = "EmulationRunner"
    version = subprocess.run([command[0], "-version"], capture_output=True, text=True,
                             check=True, timeout=10)
    return command, {"runtime": version.stderr.strip() or version.stdout.strip(),
                     "adapter": record, "jar_sha256": digest(jar)}


def validate_trace(raw, directory, record, implemented):
    rows = []
    for line in (directory / "trace.txt").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 5 or any(not re.fullmatch(r"[0-9a-fA-F]+", f) for f in fields):
            raise ValueError("Malformed instruction trace")
        rows.append([int(f, 16) for f in fields])
    if not rows or rows[0][0] != record["entry_pc"] or rows[-1][:2] != [record["final_pc"], 0]:
        raise ValueError("Trace did not run from main through the expected final breakpoint")
    hits = set()
    for i, (pc, opcode, sp, _, _) in enumerate(rows):
        if (not any(start <= pc < end for start, end in record["code_ranges"])
                or pc >= len(raw) or raw[pc] != opcode or sp % 4 or not 0 <= sp <= 32764):
            raise ValueError(f"Trace disagrees with image or has invalid state at row {i + 1}")
        if 32 <= opcode <= 63:
            if opcode not in implemented or i + 1 == len(rows):
                raise ValueError(f"Unsupported/incomplete EMULATE opcode {opcode}")
            following = rows[i + 1]
            if following[0] != (opcode - 32) * 32 or following[2] != sp - 4 or following[3] != pc + 1:
                raise ValueError(f"Missing software dispatch for opcode {opcode} at {pc:#x}: "
                                 "expected vector PC, SP-4 and PC+1 return address")
            if pc >= 0x2000:
                hits.add(opcode)
    if record["opcode"] not in hits:
        raise ValueError("Opcode under test was not dispatched from the test program")
    match = re.search(r"\binstructions=(\d+)\b", (directory / "status.txt").read_text())
    if match is None or int(match[1]) != len(rows):
        raise ValueError("Instruction count disagrees with trace")
    return len(rows)


def load_image(name):
    stem = ROOT / "build/emulated" / name
    record = json.loads(stem.with_suffix(".build.json").read_text())
    if (record["sources"] != sources(name) or record["image_sha256"] != digest(stem.with_suffix(".bin"))
            or record["manifest_sha256"] != digest(ROOT / "emulated_manifest.json")):
        raise ValueError(name + ": stale source/image/expectations; rebuild emulated images")
    return stem.with_suffix(".bin"), record


def run_cpp_tier0(args):
    """Exercise the original native-only tests on the unchanged team core."""
    manifest = tier0.read_manifest()
    names = list(manifest["tests"]) if args.name == "all" else [args.name]
    images = {}
    for name in names:
        image = ROOT / "build" / (name + ".bin")
        raw = image.read_bytes()
        tier0.check_opcodes(raw)
        record = json.loads(image.with_suffix(".build.json").read_text())
        if record["sources"] != tier0.source_hashes(name) or record["image_sha256"] != digest(image):
            raise ValueError(name + ": stale Tier 0 image; rebuild with tools/run.py build")
        images[name] = (image, record)
    command, metadata = compile_cpp(args.cxx)
    session = Path(tempfile.mkdtemp(prefix="tier0-cpp-", dir=ROOT / "runs"))
    summary = {"backend": "cpp-tier0", "backend_metadata": metadata, "results": []}
    failed = False
    for name, (image, record) in images.items():
        directory = session / name
        directory.mkdir()
        write_json(directory / "provenance.json", {**record, "backend": metadata,
                                                   "max_instructions": args.max_instructions})
        try:
            execute(command, "cpp", name, image, directory, args.max_instructions, {"entry_pc": "0"})
            failures = tier0.judge(name, directory, manifest)
            tier0.validate_trace(image.read_bytes(), directory)
            result = {"name": name, "outcome": "FAIL" if failures else "PASS",
                      "checks": len(manifest["tests"][name]), "failures": failures}
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            result = {"name": name, "outcome": "ERROR", "error": str(error)}
        failed |= result["outcome"] != "PASS"
        summary["results"].append(result)
        print(result["outcome"] + " " + name, flush=True)
        for failure in result.get("failures", []):
            print("  " + failure, flush=True)
    write_json(session / "summary.json", summary)
    print("Fresh Tier 0 C++ evidence:", session)
    return int(failed)


def execute(command, backend, name, image, directory, budget, definition):
    args = [str(image), str(directory), str(budget)]
    args += [",".join(definition["implemented"])] if backend == "reference" else [definition["entry_pc"]]
    process = subprocess.run(command + args, capture_output=True, text=True, timeout=30)
    (directory / "backend.stdout").write_text(process.stdout)
    (directory / "backend.stderr").write_text(process.stderr)
    if process.returncode:
        raise ValueError(f"{backend} adapter exited {process.returncode}: {process.stderr.strip()}")


def run_tests(args, definition):
    manifest = json.loads((ROOT / "emulated_manifest.json").read_text())
    names = list(definition["tests"]) if args.name == "all" else [args.name]
    # Check all selected inputs before starting execution.
    images = {name: load_image(name) for name in names}
    command, backend_metadata = compile_cpp(args.cxx) if args.backend == "cpp" else java_command(args.java)
    runs = ROOT / "runs"
    runs.mkdir(exist_ok=True)
    session = Path(tempfile.mkdtemp(prefix="emulated-" + args.backend + "-", dir=runs))
    summary = {"backend": args.backend, "backend_metadata": backend_metadata,
               "handler_sha256": digest(ROOT / definition["handler_source"]),
               "manifest_sha256": digest(ROOT / "emulated_manifest.json"),
               "max_instructions": args.max_instructions,
               "not_implemented": definition["unimplemented"], "results": []}
    failed = False
    for name, (image, record) in images.items():
        directory = session / name
        directory.mkdir()
        write_json(directory / "provenance.json", {**record, "backend": backend_metadata,
                                                   "command": command, "budget": args.max_instructions})
        try:
            execute(command, args.backend, name, image, directory, args.max_instructions, definition)
            failures = tier0.judge(name, directory, manifest)
            count = validate_trace(image.read_bytes(), directory, record,
                                   {int(n) for n in definition["implemented"]})
            result = {"name": name, "outcome": "FAIL" if failures else "PASS",
                      "checks": len(manifest["tests"][name]), "failures": failures,
                      "instructions": count}
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            result = {"name": name, "outcome": "ERROR", "error": str(error)}
        failed |= result["outcome"] != "PASS"
        summary["results"].append(result)
        print(f"{result['outcome']} {name}: " +
              (str(result["checks"]) + " checks" if "checks" in result else result["error"]), flush=True)
        for failure in result.get("failures", []):
            print("  " + failure, flush=True)
    write_json(session / "summary.json", summary)
    print("NOT IMPLEMENTED (not passes): " + ", ".join(definition["unimplemented"].values()))
    print("Fresh execution evidence:", session)
    return 1 if failed else 0


def main():
    definition = spec()
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    build_parser = sub.add_parser("build")
    build_parser.add_argument("--tool-prefix", default="zpu-elf-")
    p = sub.add_parser("cpp-tier0", help="original 19 native-only tests on team C++ core")
    p.add_argument("name", nargs="?", default="all", choices=["all", *tier0.read_manifest()["tests"]])
    p.add_argument("--cxx", default="g++")
    p.add_argument("--max-instructions", type=int, default=200000)
    for backend in ("cpp", "reference"):
        p = sub.add_parser(backend)
        p.set_defaults(backend=backend)
        p.add_argument("name", nargs="?", default="all", choices=["all", *definition["tests"]])
        p.add_argument("--max-instructions", type=int, default=200000)
        p.add_argument("--java", default="java")
        p.add_argument("--cxx", default="g++")
    p = sub.add_parser("check")
    p.add_argument("name", choices=list(definition["tests"]))
    p.add_argument("run_dir", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "build":
            build(args.tool_prefix)
            return 0
        if args.command == "check":
            image, record = load_image(args.name)
            manifest = json.loads((ROOT / "emulated_manifest.json").read_text())
            failures = tier0.judge(args.name, args.run_dir, manifest)
            validate_trace(image.read_bytes(), args.run_dir, record, {int(n) for n in definition["implemented"]})
            for failure in failures:
                print("FAIL " + failure)
            print(("FAIL " if failures else "PASS ") + args.name)
            return int(bool(failures))
        if args.max_instructions <= 0:
            raise ValueError("Instruction budget must be positive")
        if args.command == "cpp-tier0":
            return run_cpp_tier0(args)
        return run_tests(args, definition)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
