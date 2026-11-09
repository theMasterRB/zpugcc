# Tier 0 coverage and interpretation

This file describes the unchanged native-only Tier 0 group. The added
software-handler group and C++ launcher are documented in `EMULATED.md`.

All checks compare externally stored 32-bit words; there are no in-program EQ,
NEQ or conditional-branch checks that could hide a broken comparison instruction.
Slots are zero-based and local to each program. Exact values and descriptions
live in manifest.json. The suite has 19 programs and 500 result checks.

| Program | Checks | What it exercises |
| --- | ---: | --- |
| immediates | 9 | IM zero, -1, +63, -64, +64, -65; three-byte chaining; NOP makes 1 and 2 distinct stack entries |
| addition | 6 | Ordinary ADD, zero, unsigned wrap, signed-bit boundary, discarded carry and mixed bit patterns |
| bitwise | 12 | Mixed AND/OR/NOT and zero/all-one identities; FLIP endpoints and mixed-bit reversal |
| memory | 5 | Aligned STORE/LOAD, overwrite, zero/all-one words and unchanged neighbors |
| im_patterns | 16 | Five-byte IM chains building narrow/wide values, sign boundaries and mixed full-word patterns |
| add_carries | 32 | (2^n - 1) + 1 for n=1..32; carry propagation at every bit boundary, including final wrap |
| flip_bits | 32 | Each one-hot bit maps to bit 31-n; distinguishes bit reversal from byte swapping |
| and_bits | 32 | Each one-hot input ANDed with 0xaaaaaaaa; alternating permitted/cleared lanes |
| or_bits | 32 | Each one-hot input ORed with 0xaaaaaaaa; existing/new set bits in every lane |
| not_bits | 32 | NOT of every one-hot input; all output bits except the selected bit must be one |
| stack_pointer | 10 | PUSHSP is pre-push address; pushes decrement by four; preserved TOS; consecutive PUSHSP; POPSP relocations; no stack leak |
| loadsp_low | 48 | All 16 offsets 0..60 bytes, every four bytes: copied value, source preservation and final SP |
| loadsp_high | 48 | All 16 offsets 64..124 bytes; same checks, covering the encoding's inverted offset bit |
| storesp_low | 48 | All offsets 0..60 bytes: target/drop behavior, upper neighbor preservation and one-word pop |
| storesp_high | 48 | All offsets 64..124 bytes: same checks across the offset-encoding boundary |
| addsp_offsets | 48 | Every ADDSP offset 0..60 bytes: arithmetic result, stack effect and source/guard preservation |
| poppc | 6 | Forward jump skips a poison store; backward jump; target consumed; underlying value preserved; no stack leak |
| memory_patterns | 32 | Sixteen adjacent patterned words across address 0x1300; alternate-word overwrite with untouched neighbors |
| nop | 4 | Preserves TOS and stack depth; resets IM chaining between +63 and -64 |

## Stack-relative cases

LOADSP and STORESP each have 32 encoded word offsets; assembly operands here are
BYTE offsets (0, 4, ... 124). ADDSP has 16 offsets (0, 4, ... 60). The assembler
performs the special LOADSP/STORESP encoding. Tests cover every encoding.

Each LOADSP case selects SP=0x7800, places a unique value at SP+offset, then
copies it using LOADSP. SAVE removes the copy. The source is reloaded through
ordinary LOAD and SP is checked after observation.

Each STORESP case selects SP=0x7800, seeds the target and a higher neighbor, then
pushes a value. Just before STORESP, SP=0x77fc, so the target is 0x77fc+offset.
STORESP pops one word. Offset zero is special: it writes the value back into its
own just-popped slot, so its meaningful checks are that NOS and its neighbor
survive and SP advances correctly. Later instrumentation is allowed to reuse the
popped slot; we do not incorrectly demand it remain unchanged.

ADDSP replaces TOS with TOS+mem[SP+offset] and does not consume the source word.
Offset zero doubles TOS. The external SAVE then consumes the result, so the
expected observed SP is 0x7804. Other offsets must preserve the selected source;
offset zero instead checks a separate guard because its source was TOS itself.

The POPPC test uses poison side effects on skipped paths. Simply writing the
expected value at the target would not prove a forward jump worked, because
falling through could eventually write that value too.

## Dependencies and limits

Every test needs working IM, NOP, POPSP, STORE and BREAKPOINT to initialize and
report. Memory/stack/control tests additionally need their other foundational
operations. Failures in those dependencies can affect several programs. Start
with the simple tests and inspect the first divergent trace/state.

The suite exercises every required NON-EMULATE instruction family, but it is not
exhaustive verification. BREAKPOINT is primarily checked as the stop mechanism;
it does not prove all debugger behavior or register preservation. Required
EMULATE dispatch and vector return are deliberately reserved for Tier 1.

Not covered yet: interrupts/IDIM interrupt suppression, invalid or unaligned
access policy, I/O, MMIO side effects, native-vs-emulated equivalence, instruction
fetch faults, timing, reset variants, bootloading, heap, C ABI or C libraries.
Word STORE/LOAD round trips alone do not prove byte-lane endianness. Image packing
is checked independently; byte/halfword instruction tests belong in later tiers.

The expanded package has separate native Tier 0 results from Java and the team's
C++ core; see VALIDATION.md. Neither establishes results for Questa or RTL.
