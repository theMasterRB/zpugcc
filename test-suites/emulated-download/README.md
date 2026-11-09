# Downloadable ZPU software test kit

[Download the complete ZIP](https://github.com/theMasterRB/zpugcc/blob/test-suite/emulated-opcodes/test-suites/emulated-download/zpu-software-tests.zip?raw=true)

The ZIP contains the original Tier 0 suite, the new software-handler tests,
prebuilt images, the original Java reference simulator and source, and the
unchanged handler/C++ core sources from the `opcodes` branch.

Extract it, then from `zpu-software-tests`:

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

Tier 0: 19 programs / 500 result checks. Software handlers: 26 programs / 1,019
checks over 22 implemented opcode families. Both groups pass on both backends;
all complete software-handler traces match. Eight handler slots remain empty
and are explicitly reported as not implemented. These results do not validate RTL.

The files under `DigitalDesign-ZPU/software/zpu-tests` are the reviewable source
of this package. Read `EMULATED.md` for exact coverage and `VALIDATION.md` for
recorded evidence. A suggested PR description is included. Keep the extracted
`software/` and `simulator/` layout when copying to another repository; there is
no nested Git repository. Include simulator source and notices when distributing.

To regenerate this ZIP after validated changes, run from `software/zpu-tests`:

```sh
python3 tools/package_emulated.py ../../../test-suites/emulated-download/zpu-software-tests.zip
```
