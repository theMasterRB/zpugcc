#!/usr/bin/env python3
"""Verify the self-contained software-handler suite without native Tier 0 files."""
import json

from run_emulated import ROOT, digest, load_image, spec
from run import binary_to_hex


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_adapter(source, directory, classes, expected_source):
    require(digest(ROOT / source) == expected_source, "Adapter source changed: " + source)
    for name, expected in classes.items():
        path = ROOT / directory / name
        require(digest(path) == expected, "Adapter bytecode checksum mismatch: " + name)
        raw = path.read_bytes()
        require(raw[:4] == bytes.fromhex("cafebabe") and int.from_bytes(raw[6:8], "big") == 52,
                "Adapter is not Java 8 bytecode: " + name)


def main():
    definition = spec()
    manifest = json.loads((ROOT / "emulated_manifest.json").read_text())
    require(set(manifest["tests"]) == set(definition["tests"]), "Manifest test names differ")
    require({case["opcode"] for case in definition["tests"].values()} ==
            {int(n) for n in definition["implemented"]}, "Missing implemented opcode coverage")
    for name in definition["tests"]:
        image, _ = load_image(name)
        require(image.with_suffix(".hex").read_text() == binary_to_hex(image.read_bytes()),
                "Hex packing mismatch: " + name)
        require(image.with_suffix(".elf").is_file(), "ELF missing: " + name)
        require(1 <= len(manifest["tests"][name]) <= 60, "Invalid result area: " + name)
    reference = json.loads((ROOT / "reference.json").read_text())
    require(digest(ROOT / "reference/zylin/simulator/zpusim.jar") == reference["jar_sha256"],
            "Reference JAR checksum mismatch")
    base = reference["adapter_bytecode"]
    check_adapter(reference["adapter"], base["directory"], base["classes"], base["source_sha256"])
    adapter = json.loads((ROOT / "emulated_reference.json").read_text())
    check_adapter("tools/EmulationRunner.java", adapter["directory"], adapter["classes"],
                  adapter["source_sha256"])
    vendor = ROOT / "reference/zylin"
    upstream = json.loads((vendor / "UPSTREAM.json").read_text())
    for name, expected in upstream["files_sha256"].items():
        require(digest(vendor / name) == expected, "Bundled upstream source changed: " + name)
    require((vendor / "COPYING").is_file() and (vendor / "GPL-2.txt").is_file(),
            "Upstream licensing notices missing")
    if (ROOT / "evidence/archives.json").is_file():
        for name, expected in json.loads((ROOT / "evidence/archives.json").read_text()).items():
            require(digest(ROOT / "evidence" / name) == expected, "Evidence archive changed: " + name)
    count = sum(len(cases) for cases in manifest["tests"].values())
    print(f"VERIFIED: {len(definition['tests'])} programs / {count} checks; "
          f"{len(definition['implemented'])} implemented handler families.")
    print("No original Tier 0 test folder or manifest is required.")


if __name__ == "__main__":
    main()
