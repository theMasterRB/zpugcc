#!/usr/bin/env python3
"""Verify the packaged program images, adapter, and unchanged upstream files."""
import hashlib
import json

from run import ROOT, binary_to_hex, check_opcodes, read_manifest, source_hashes


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    manifest = read_manifest()
    reference = json.loads((ROOT / "reference.json").read_text())
    jar = ROOT / reference["bundled_jar_path"]
    require(sha(jar) == reference["jar_sha256"], "Simulator JAR checksum mismatch")
    bytecode = reference["adapter_bytecode"]
    require(sha(ROOT / reference["adapter"]) == bytecode["source_sha256"],
            "Adapter source changed without recompilation")
    for name, expected in bytecode["classes"].items():
        path = ROOT / bytecode["directory"] / name
        require(sha(path) == expected, f"Adapter class checksum mismatch: {name}")
        raw = path.read_bytes()
        require(raw[:4] == bytes.fromhex("cafebabe") and int.from_bytes(raw[6:8], "big") == 52,
                f"Adapter class is not Java 8 format: {name}")
    vendor = ROOT / "reference/zylin"
    upstream = json.loads((vendor / "UPSTREAM.json").read_text())
    for name, expected in upstream["files_sha256"].items():
        require(sha(vendor / name) == expected, f"Upstream file changed: {name}")
    require((vendor / "COPYING").is_file() and (vendor / "GPL-2.txt").is_file(),
            "Upstream license notice/text missing")
    for name in manifest["tests"]:
        image = ROOT / "build" / f"{name}.bin"
        raw = image.read_bytes()
        check_opcodes(raw)
        record = json.loads(image.with_suffix(".build.json").read_text())
        require(record["sources"] == source_hashes(name), f"Stale source record: {name}")
        require(record["image_sha256"] == sha(image), f"Image checksum mismatch: {name}")
        require(image.with_suffix(".hex").read_text() == binary_to_hex(raw),
                f"Hex packing mismatch: {name}")
        require(image.with_suffix(".elf").is_file(), f"ELF missing: {name}")
    checks = sum(len(cases) for cases in manifest["tests"].values())
    print(f"VERIFIED: {len(manifest['tests'])} programs / {checks} checks; "
          f"adapter and {len(upstream['files_sha256'])} unchanged upstream files.")
    archives = ROOT / "evidence/archives.json"
    if archives.is_file():
        for name, checksum in json.loads(archives.read_text()).items():
            require(sha(ROOT / "evidence" / name) == checksum, "Evidence archive checksum mismatch: " + name)
    # The native-only Tier 0 package remains usable independently. This extended
    # package also pins handler sources, expectations, images and Java bytecode.
    if (ROOT / "emulated_cases.json").exists():
        from run_emulated import load_image, spec
        definition = spec()
        require({case["opcode"] for case in definition["tests"].values()} ==
                {int(n) for n in definition["implemented"]}, "Missing implemented opcode coverage")
        expected = json.loads((ROOT / "emulated_manifest.json").read_text())
        for name in definition["tests"]:
            image, _ = load_image(name)
            require(image.with_suffix(".hex").read_text() == binary_to_hex(image.read_bytes()),
                    f"Emulated hex packing mismatch: {name}")
            require(image.with_suffix(".elf").is_file(), f"Emulated ELF missing: {name}")
            require(1 <= len(expected["tests"][name]) <= 60, "Invalid emulated result area")
        adapter = json.loads((ROOT / "emulated_reference.json").read_text())
        require(sha(ROOT / "tools/EmulationRunner.java") == adapter["source_sha256"],
                "Emulation adapter source changed without recompilation")
        for name, checksum in adapter["classes"].items():
            path = ROOT / adapter["directory"] / name
            require(sha(path) == checksum and path.read_bytes()[:8] == bytes.fromhex("cafebabe00000034"),
                    "Emulation adapter bytecode checksum/Java 8 format mismatch")
        count = sum(len(cases) for cases in expected["tests"].values())
        print(f"VERIFIED: {len(definition['tests'])} emulated programs / {count} checks; "
              f"{len(definition['implemented'])} implemented opcode families.")


if __name__ == "__main__":
    main()
