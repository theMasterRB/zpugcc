.include "tier0.inc"
.equ EMU_SP, 0x7800
.equ GUARD, 0x6a09e667

.macro BEGIN_EMULATED
    .section .text.test,"ax"
    .global main
main:
    PUSH32 EMU_SP
    popsp
    PUSH32 0
    PUSH32 COMPLETION
    store
.endm

.macro END_EMULATED
    PUSH32 DONE
    PUSH32 COMPLETION
    store
    .global _test_break
_test_break:
    breakpoint
.endm
