#!/usr/bin/env python3
"""Build a portable ZIP containing tests, original CRT handlers and C++ core."""
import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from run_emulated import ROOT, CORE, digest
from verify_bundle import main as verify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    verify()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    prefix = "zpu-software-tests/"
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(ROOT.rglob("*")):
            rel = path.relative_to(ROOT)
            if not path.is_file() or path.resolve() == output:
                continue
            if any(part in ("runs", "__pycache__", ".git") for part in rel.parts):
                continue
            if path.suffix in (".pyc", ".o", ".map", ".dis") or path.name in ("mutant-cpp", "cpp-runner"):
                continue
            archive.write(path, prefix + "software/zpu-tests/" + rel.as_posix())
        for source, target in (
                (ROOT.parent / "crt0Stuff/crt0.S", "software/crt0Stuff/crt0.S"),
                (ROOT.parent / ".gitattributes", "software/.gitattributes"),
                (CORE / "zpu_core.cpp", "simulator/zpu_core.cpp"),
                (CORE / "zpu_core.h", "simulator/zpu_core.h")):
            archive.write(source, prefix + target)
        archive.writestr(prefix + "README.md", """# ZPU software test kit

From this extracted folder:

```sh
cd software/zpu-tests
python3 tools/verify_bundle.py
sh run_tests.sh
sh run_emulated_tests.sh reference
```

Requires Python 3.7+ and Java 8+. With g++ installed, also run:

```sh
sh run_emulated_tests.sh cpp-tier0
sh run_emulated_tests.sh cpp
```

The original Tier 0 tests have 19 programs / 500 checks. The software-handler
group adds 26 programs / 1,019 checks across 22 implemented opcode families.
Eight empty handler slots are explicitly not implemented. See
`software/zpu-tests/EMULATED.md`, `VALIDATION.md` and `PR_DESCRIPTION.md`.

The original CRT handler and C++ core sources from the opcodes branch are
included unchanged. Keep the software/ and simulator/ layout intact. There
is no nested Git repository. Bundled upstream Java simulator source and notices
are under software/zpu-tests/reference/ and must accompany it.
""")
    checksum = digest(output)
    output.with_suffix(output.suffix + ".sha256").write_text(checksum + "  " + output.name + "\n")
    print("PACKAGED:", output, "SHA256:", checksum)


if __name__ == "__main__":
    main()
