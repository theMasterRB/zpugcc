Add tests that execute the software-emulated opcode handlers in
`software/crt0Stuff/crt0.S`, alongside the existing native-only Tier 0 suite.
The 26 new programs provide 1,019 external result checks across all 22 implemented
handler families. Eight empty handler slots are explicitly reported as not
implemented. Original Tier 0 remains 19 programs / 500 checks.

The Java adapter forces the original simulator's existing software-dispatch
path. A C++ adapter executes the team's unchanged `zpu_core.cpp`. The checker
requires actual vector entry, SP-4 and PC+1 on the stack; correct results from
native opcode execution cannot masquerade as software-handler coverage. Tests
also check stack guards, expected-zero result writes, byte/halfword lanes,
relative branch directions and nested calls.

From `software/zpu-tests`, run `sh run_tests.sh`,
`sh run_emulated_tests.sh reference`, `sh run_emulated_tests.sh cpp-tier0`,
and `sh run_emulated_tests.sh cpp`. Included images/Java 8 bytecode avoid a ZPU
compiler or JDK requirement for normal runs; C++ execution requires g++.

Validation: all 1,519 checks pass on both backends; all 26 complete handler
execution traces match. All 27 host safeguard checks pass. Five negative
executions are rejected, including two mutant C++ cores and native Java bypass.
Original Tier 0's three negative executions are also rejected. No CRT handler
or C++ instruction semantics are changed. Boot/reset, interrupts, devices,
unimplemented handlers, shift counts >=32 and RTL are outside this validation.
