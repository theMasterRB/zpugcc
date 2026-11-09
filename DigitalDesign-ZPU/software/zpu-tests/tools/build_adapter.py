#!/usr/bin/env python3
"""Rebuild/pin the distributed Java 8 adapter. Requires Java 11+ JDK at BUILD time.

Running the test suite uses the included class files and needs only a Java 8 JRE.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", type=Path, default=ROOT / "reference/zylin/simulator/zpusim.jar")
    parser.add_argument("--java8-rt-jar", type=Path,
                        help="Java 8 rt.jar for compilers missing --release 8 symbols")
    args = parser.parse_args()
    jar = args.jar.resolve()
    reference_file = ROOT / "reference.json"
    reference = json.loads(reference_file.read_text())
    if hashlib.sha256(jar.read_bytes()).hexdigest() != reference["jar_sha256"]:
        raise ValueError("Reference JAR does not match pinned checksum")
    output = ROOT / "tools/java8"
    output.mkdir(exist_ok=True)
    source = ROOT / "tools/ReferenceRunner.java"
    command = ["java", str(ROOT / "tools/CompileAdapter.java"),
               str(jar), str(source), str(output)]
    if args.java8_rt_jar is not None:
        command.append(str(args.java8_rt_jar.resolve()))
    subprocess.run(command, check=True)
    classes = {}
    for name in ["ReferenceRunner.class", "ReferenceRunner$Cpu.class"]:
        raw = (output / name).read_bytes()
        if raw[:4] != bytes.fromhex("cafebabe") or int.from_bytes(raw[6:8], "big") != 52:
            raise ValueError(f"{name}: compiler did not produce Java 8 class format")
        classes[name] = hashlib.sha256(raw).hexdigest()
    reference["adapter_bytecode"] = {
        "directory": "tools/java8",
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "classes": classes,
    }
    reference_file.write_text(json.dumps(reference, indent=2) + "\n")
    print("Built and pinned Java 8 adapter bytecode; runtime compiler is no longer needed.")


if __name__ == "__main__":
    main()
