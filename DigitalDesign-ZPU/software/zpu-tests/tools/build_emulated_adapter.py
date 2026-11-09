#!/usr/bin/env python3
"""Rebuild Java 8 emulation adapter; ordinary runs use included bytecode."""
import argparse
import json
import os
import subprocess

from run_emulated import ROOT, digest, write_json
from run import reference_command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java", default="java", help="Java 11+ JDK for compilation")
    parser.add_argument("--java8-rt-jar", help="Verified Java 8 rt.jar if --release 8 is unavailable")
    args = parser.parse_args()
    jar = ROOT / "reference/zylin/simulator/zpusim.jar"
    reference_command(jar, args.java)  # Verify original dependencies before use.
    source = ROOT / "tools/EmulationRunner.java"
    directory = ROOT / "tools/emulated-java8"
    directory.mkdir(exist_ok=True)
    classpath = os.pathsep.join([str(jar), str(ROOT / "tools/java8")])
    command = [args.java, str(ROOT / "tools/CompileAdapter.java"),
               classpath, str(source), str(directory)]
    if args.java8_rt_jar:
        command.append(args.java8_rt_jar)
    subprocess.run(command, check=True)
    classes = {}
    for name in ("EmulationRunner.class", "EmulationRunner$Cpu.class"):
        raw = (directory / name).read_bytes()
        if raw[:8] != bytes.fromhex("cafebabe00000034"):
            raise ValueError(name + " is not Java 8 bytecode")
        classes[name] = digest(directory / name)
    write_json(ROOT / "emulated_reference.json", {
        "directory": "tools/emulated-java8", "source_sha256": digest(source), "classes": classes})
    print("Built and pinned forced-emulation Java 8 adapter")


if __name__ == "__main__":
    main()
