# ZPU Tier 0 test packages

## Self-contained kit (recommended)

[Download zpu-tier0-kit.zip](zpu-tier0-kit.zip?raw=true).
If GitHub opens the file page, select **Download raw file**.

The ZIP extracts to one `zpu-tier0/` folder containing:

- 19 assembly programs, 500 external result checks, and prebuilt test images.
- The unmodified original Zylin Java simulator JAR and all its source files.
- Upstream licensing notice, GPL text, pinned revision and file checksums.
- A Java 8-compatible adapter, Python checker, execution evidence and documentation.
- A launcher and a suggested PR description for importing into another repository.

Requires Python 3.7+ and Java 8+ JRE. No separate simulator clone, Java compiler,
ZPU compiler, UART, or bootloader is needed to run the included images:

```sh
unzip zpu-tier0-kit.zip
cd zpu-tier0
python3 tools/verify_bundle.py
./run_tests.sh immediates
./run_tests.sh
```

All 19 programs / 500 result checks passed on the bundled simulator under Java 8.
The 16 host safeguards passed and three deliberately wrong/incomplete executions
were rejected. A clean Git import/checkout and ZIP extraction were also verified.
These results do not validate the team's C++ simulator or RTL.

To submit elsewhere, copy the complete extracted folder into your branch, keeping
its internal layout and upstream source/notices. The included `.gitignore`
retains required prebuilt assets while excluding new runs; `.gitattributes`
preserves pinned file bytes. See the package README and `PR_DESCRIPTION.md`.

Simulator source: https://github.com/zylin/zpu/tree/e29aef5f7aa741557d0eb16ecf13e974d55789ff/zpu/sw/simulator

The JAR and source are copied unchanged from that commit. Provenance, original
license notice and per-file hashes are included in the kit.

## Earlier standalone suite

[zpu-tier0-suite.zip](zpu-tier0-suite.zip?raw=true) is retained for existing users.
That earlier package requires obtaining the simulator separately. For a fresh
setup or PR handoff, use the self-contained kit above.

## SHA-256

```text
fc72d1a6c347a515997aec5b2b9068349906267e720b484cfd2b20159d2266b8  zpu-tier0-kit.zip
fa2b3689cbe5867c22f1b7d9f25e05993a7f6faf15d00c79959e8dd830a20bfd  zpu-tier0-suite.zip
```
