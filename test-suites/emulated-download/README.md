# Downloadable ZPU software test kit

[Download the independent emulated-opcode suite](https://github.com/theMasterRB/zpugcc/blob/test-suite/emulated-opcodes/test-suites/emulated-download/zpu-emulated-tests-standalone.zip?raw=true)

**Use this independent suite when your branch does not contain the hardware
tests.** Extract and copy the whole `zpu-emulated-tests` folder into your
repository's `software/` folder, alongside `crt0Stuff/crt0.S`. It includes all
of its own runtime helpers and the Java reference simulator. No original Tier 0
suite, original manifest or add-on installer is required. From the repo root:

```sh
cd software/zpu-emulated-tests
sh run_emulated_tests.sh reference
```

The hardware tests can later coexist in `software/zpu-tests`; the two folders
run independently. The branch's handler source is still the input being tested.
If it differs from the prebuilt images, rebuild those images against your source.

The two older packages below remain available for existing installations.

[Already have Tier 0? Download only the emulated-opcode test add-on](https://github.com/theMasterRB/zpugcc/blob/test-suite/emulated-opcodes/test-suites/emulated-download/zpu-emulated-opcode-addon.zip?raw=true)

The add-on adds the new test sources, runner, prebuilt images and Java adapter
to an existing compatible Tier 0 suite. It retains the original tests, shared
checker, simulator and handlers. Extract it and use its `install.py` with your
existing `software/zpu-tests` path; see the included README. New test files are
kept in the separate `emulated/` group. Commit them on a branch based on your
emulated-opcode branch, then PR back into that branch.

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
