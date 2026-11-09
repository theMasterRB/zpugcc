# Independent software-handler suite validation

The suite was copied into an isolated project containing only this test folder,
the branch's crt0.S input and optional C++ core sources. There was no original
hardware test folder, hardware test manifest or hardware test program.

* All 26 software test programs rebuilt using their own included macros/linker.
* All 1,019 result checks passed on Temurin Java 8 and the team C++ core.
* All 26 complete instruction traces matched between backends.
* All 11 host checker/independence tests passed.
* All five negative executions were rejected, including two mutant C++ cores.
* The standalone release ZIP was regenerated without any hardware test suite.
* Separately, the original hardware suite passed all 19 programs / 500 checks
  with the software test folder removed from its project software directory.
* Both folders then ran successfully side by side: hardware immediates (9 checks)
  and software EQ (48 checks), using each folder's own runtime files.

Fresh execution records are in evidence/emulated-java8, emulated-cpp and
negative-emulated. Each retains a readable summary and compressed full run.
Archive hashes and an independence report are included. These executions took
place in the Linux cloud workspace, not on the user's Mac or RTL.

The target handler source is the opcodes branch version at
bf29e0177e061cb72f69cf8e8ab5a079c91138a4. Different source requires rebuilding
before execution. Eight empty handler slots remain unimplemented. This does
not establish interrupt, device, boot/runtime, timing or hardware fallback behavior.
