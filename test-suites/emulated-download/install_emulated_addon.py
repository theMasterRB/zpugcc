#!/usr/bin/env python3
"""Install only new handler-test files into an existing compatible Tier 0 suite."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import shutil
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def append_rules(path, rules):
    marker = b"# Emulated opcode test add-on\n"
    previous = path.read_bytes() if path.exists() else b""
    if marker.strip() in previous:
        return
    separator = b"\n" if previous and not previous.endswith(b"\n") else b""
    path.write_bytes(previous + separator + b"\n" + marker + rules.encode("utf-8"))


def install(addon, target):
    metadata = json.loads((addon / "addon.json").read_text())
    payload = addon / "payload"
    # Check dependencies and every collision BEFORE making changes.
    for relative, expected in metadata["required_sha256"].items():
        path = target / relative
        if not path.is_file() or sha(path) != expected:
            raise ValueError("Missing/incompatible shared Tier 0 file: " + str(path)
                             + ". Use the original combined Java-8-compatible Tier 0 kit.")
    for relative in ("manifest.json", "reference.json", "tools/run.py"):
        if not (target / relative).is_file():
            raise ValueError("Existing Tier 0 suite required: missing " + relative)
    functions = {n.name for n in ast.parse((target / "tools/run.py").read_text()).body
                 if isinstance(n, ast.FunctionDef)}
    required = {"judge", "read_manifest", "reference_command", "source_hashes", "check_opcodes",
                "binary_to_hex", "find_tool", "validate_trace"}
    if not required <= functions:
        raise ValueError("The existing Tier 0 runner needs the Java 8 compatibility update")
    handler = target.parent / "crt0Stuff/crt0.S"
    if not handler.is_file():
        raise ValueError("Handler source must be at " + str(handler)
                         + ". Keep the project's software/zpu-tests layout.")
    for relative, expected in metadata["files_sha256"].items():
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError("Invalid add-on path")
        source, destination = payload / path, target / path
        if not source.is_file() or sha(source) != expected:
            raise ValueError("Add-on file checksum mismatch: " + relative)
        if destination.exists() and (not destination.is_file() or sha(destination) != expected):
            raise ValueError("Existing file differs; nothing installed: " + str(destination))
    count = 0
    for relative in metadata["files_sha256"]:
        source, destination = payload / relative, target / relative
        if not destination.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            count += 1
    append_rules(target / ".gitignore", metadata["gitignore_rules"])
    append_rules(target / ".gitattributes", metadata["gitattributes_rules"])
    append_rules(target.parent / ".gitattributes", "crt0Stuff/crt0.S -text\n")
    print(f"Installed {count} new files into {target}")
    print("Existing Tier 0 tests, checker, handlers and simulator source were retained.")
    print("Git ignore/attribute rules were appended for the new prebuilt assets.")
    if sha(handler) != metadata["handler_sha256"]:
        print("Your handler source differs from the prebuilt images. Before running, rebuild:")
        print("  python3 tools/run_emulated.py build --tool-prefix /path/to/bin/zpu-elf-")
    print("From the test folder, run: sh run_emulated_tests.sh reference")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("test_folder", type=Path, help="existing project/software/zpu-tests folder")
    args = parser.parse_args()
    try:
        install(Path(__file__).resolve().parent, args.test_folder.resolve())
        return 0
    except (OSError, ValueError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
