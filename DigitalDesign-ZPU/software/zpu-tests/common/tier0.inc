/* Byte addresses. Keep these synchronized with manifest.json. */
.equ COMPLETION, 0x1000
.equ RESULTS,    0x1010
.equ SCRATCH,    0x1200
.equ STACK_TOP,  0x7ff8
.equ DONE,       0x5a505530

/* Fixed five-byte immediate, avoiding the assembler's optional IM+FLIP
 * optimization. NOP also separates this value from a preceding IM chain.
 * These are five separate hardware instructions, not one opcode.
 */
.macro PUSH32 value
    nop
    .byte 0x80 | (((\value) >> 28) & 0x7f)
    .byte 0x80 | (((\value) >> 21) & 0x7f)
    .byte 0x80 | (((\value) >> 14) & 0x7f)
    .byte 0x80 | (((\value) >>  7) & 0x7f)
    .byte 0x80 | ((\value) & 0x7f)
.endm

.macro BEGIN_TEST
    .section .text,"ax"
    .global _start
_start:
    PUSH32 STACK_TOP
    popsp
    PUSH32 0
    PUSH32 COMPLETION
    store
.endm

/* Store TOS at the externally checked result slot; consumes that value. */
.macro SAVE slot
    PUSH32 (RESULTS + 4 * (\slot))
    store
.endm

/* Reaching a breakpoint is not sufficient: checker requires this marker. */
.macro END_TEST
    PUSH32 DONE
    PUSH32 COMPLETION
    store
    breakpoint
.endm
