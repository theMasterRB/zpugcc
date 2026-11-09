# Reference simulator provenance

The simulator is the original Java implementation in **Zylin's ZPU repository**:

https://github.com/zylin/zpu

Exact source tree used:

https://github.com/zylin/zpu/tree/e29aef5f7aa741557d0eb16ecf13e974d55789ff/zpu/sw/simulator

Exact original binary:

https://github.com/zylin/zpu/blob/e29aef5f7aa741557d0eb16ecf13e974d55789ff/zpu/sw/simulator/zpusim.jar

Upstream JAR SHA-256:

```text
a4ed991ec14bed109bfbd1bb7989860f166700cf11cd52fcfcbe80abe3cfe655
```

## Included upstream files

`reference/zylin/simulator/` is a byte-for-byte copy of the entire upstream
`zpu/sw/simulator/` directory at that commit, including original Java source,
JAR, build metadata and project files. We did not rebuild or modify that JAR.
Source is supplied from the same repository revision; a byte-identical rebuild
of the historical JAR has not been established.

`reference/zylin/UPSTREAM.json` records every copied simulator file's SHA-256.
`reference/zylin/UPSTREAM_README.md` is the repository README at that commit.
`reference/zylin/COPYING` preserves the original `zpu/COPYING` notice verbatim.
That notice identifies Zylin's tools as GPL and does not specify a version.
A complete GNU GPL version 2 text is also supplied as `reference/zylin/GPL-2.txt`.
Keep these notices and the upstream source when redistributing the simulator.
No replacement upstream license notice or additional upstream terms are asserted.

## Our integration files

`tools/ReferenceRunner.java`, `tools/java8/`, the Python scripts and the assembly
suite are integration/test files, not upstream simulator files. The adapter sets
RAM/SP bounds, disables I/O, exports traces/dumps, and invokes the pinned simulator's
instruction loop. Opcode execution remains in the unmodified original simulator.
Its private-loop integration is version-specific; checksums prevent silent
replacement with a different simulator build.

This is distinct from the team's in-development C++ simulator and RTL. Passing
this backend supplies a correctness baseline, not proof of another backend.

## Rebuilding upstream source

The original sources have no external Java imports beyond the JDK and their own
packages. A Java 8 JDK can compile the supplied source; the historical Eclipse/Ant
metadata is also preserved. From `reference/zylin/simulator/`, an example clean
source build to a separate directory is:

```sh
mkdir -p ../rebuilt/classes
find com -name '*.java' > ../rebuilt/sources.list
javac -source 8 -target 8 -d ../rebuilt/classes @../rebuilt/sources.list
jar cf ../rebuilt/zpusim.jar -C ../rebuilt/classes .
```

This does not replace the pinned reference artifact. The suite intentionally
rejects a different JAR until provenance and expected behavior are revalidated.
