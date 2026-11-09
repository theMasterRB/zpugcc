#!/usr/bin/env python3
"""Package new emulation tests separately; require shared files from Tier 0."""
import argparse
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from run_emulated import ROOT, digest, spec
from verify_bundle import main as verify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    verify()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    direct = ["common/emulated.inc", "common/emulated.ld", "emulated_cases.json",
              "emulated_manifest.json", "emulated_reference.json", "run_emulated_tests.sh",
              "EMULATED.md", "checks/test_emulated_runner.py", "tools/run_emulated.py",
              "tools/generate_emulated.py", "tools/EmulationRunner.java", "tools/CppRunner.cpp",
              "tools/compare_emulated.py", "tools/check_negative_emulated.py",
              "tools/build_emulated_adapter.py", "evidence/emulated-trace-comparison.json"]
    files = {name: ROOT / name for name in direct}
    for directory in ("emulated", "tools/emulated-java8", "build/emulated",
                      "evidence/emulated-java8", "evidence/emulated-cpp", "evidence/negative-emulated"):
        for path in sorted((ROOT / directory).rglob("*")):
            if not path.is_file() or path.suffix in (".o", ".map", ".dis"):
                continue
            files[path.relative_to(ROOT).as_posix()] = path
    required = ["common/tier0.inc", "tools/ReferenceRunner.java", "tools/java8/ReferenceRunner.class",
                "tools/java8/ReferenceRunner$Cpu.class", "reference/zylin/simulator/zpusim.jar"]
    metadata = {
        "description": "New handler tests only; requires the existing Java-8-compatible Tier 0 kit",
        "files_sha256": {name: digest(path) for name, path in sorted(files.items())},
        "required_sha256": {name: digest(ROOT / name) for name in required},
        "handler_sha256": digest(ROOT / spec()["handler_source"]),
        "gitignore_rules": "!build/emulated/\nbuild/emulated/*\n!build/emulated/*.bin\n"
                           "!build/emulated/*.elf\n!build/emulated/*.hex\n!build/emulated/*.build.json\n"
                           "!tools/emulated-java8/\n!tools/emulated-java8/**\n",
        "gitattributes_rules": "emulated/** -text\nemulated_cases.json -text\n"
                               "emulated_manifest.json -text\nemulated_reference.json -text\n"
                               "common/emulated.* -text\nbuild/emulated/** -text\n"
                               "build/emulated/*.hex -diff\ntools/emulated-java8/** -text\n"
                               "run_emulated_tests.sh text eol=lf\n",
    }
    installer = ROOT.parents[2] / "test-suites/emulated-download/install_emulated_addon.py"
    prefix = "emulated-opcode-addon/"
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        archive.write(installer, prefix + "install.py")
        archive.writestr(prefix + "addon.json", json.dumps(metadata, indent=2) + "\n")
        for name, path in sorted(files.items()):
            archive.write(path, prefix + "payload/" + name)
        archive.writestr(prefix + "README.md", """# Emulated opcode test add-on

This download adds only the new software-handler tests to your existing Tier 0
suite. It contains no original tier0/*.S programs, replacement shared checker,
CRT handler implementation, C++ core or separate Java simulator.

1. Switch your repository to its emulated-opcode branch (or a new branch based on it).
2. Extract this add-on outside your repository.
3. From this extracted folder, run the following, replacing the path with your
   existing test folder:

```sh
python3 install.py /path/to/your/repo/software/zpu-tests
```

The installer checks shared dependencies and file collisions before writing.
It adds new files, retains existing files, and appends the Git ignore/attribute
rules needed to commit the new prebuilt images and Java classes. A differing
existing add-on file stops installation; your edits are not overwritten.

Requires the original combined Tier 0 kit with its Java 8-compatible adapter,
shared tools/run.py, common/tier0.inc, manifest.json and bundled Zylin simulator.
Keep your existing software/crt0Stuff/crt0.S. If its contents differ from the
version used for these images, the runner requires a rebuild using zpu-elf-gcc
and binutils before execution.

Then from your software/zpu-tests folder:

```sh
sh run_tests.sh
sh run_emulated_tests.sh reference
```

With g++ and the team's simulator/zpu_core.cpp and zpu_core.h available:

```sh
sh run_emulated_tests.sh cpp
```

The new group has 26 programs / 1,019 result checks for 22 implemented handler
families. Eight empty slots remain explicitly unimplemented. See EMULATED.md
inside the installed test folder. Java 8+ and Python 3.7+ are required.

Review the new files and three Git configuration additions in GitHub Desktop,
commit on your test branch, then open a PR into your emulated-opcode branch.
The private repository itself was not accessed or changed by creating this kit.
""")
    output.with_suffix(output.suffix + ".sha256").write_text(digest(output) + "  " + output.name + "\n")
    print(f"PACKAGED ADD-ON: {len(files)} new files, {output.stat().st_size} bytes: {output}")


if __name__ == "__main__":
    main()
