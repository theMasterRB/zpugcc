.file "crt0.S"

/*
 * compile c to assembly cmd: zpu-elf-gcc -S -O0 file.c
 * compile .S file zpu-elf-gcc -c file.S
 * objdump .S file  zpu-elf-objdump -dr -j .section file.o
 *
 * Operand convention used below (A = top of stack, B = next on stack):
 *   SUB = B - A, LESSTHAN = A < B, LESSTHANOREQUAL = A <= B, shifts = B shifted by A
 */

// Macros
.macro fixedim value
im  \value
nop
.endm

.macro negate
not
im 1
add
.endm

.macro flipsignbit addr
loadsp \addr
im 1
flip
add
storesp \addr + 4
.endm

// jump to an absolute address: push it, then poppc
.macro jmp address
fixedim \address
poppc
.endm

// STORE a byte or halfword: read-modify-write of the aligned word that contains it.
// On entry the stack is [ret, A = address, B = value, rest]; on exit it is [rest].
//   lowbits: address bits that select the part (3 for a byte, 2 for a halfword)
//   base:    highest part index (3 for bytes, 2 for halfwords), big-endian so part 0 is the top
//   fmask:   mask of the part before shifting (255 or 65535)
.macro storepart lowbits, base, fmask
loadsp 4
im \lowbits
and
negate
im \base
add
addsp 0
addsp 0
addsp 0                 // [shift, ret, A, B]
im \fmask
loadsp 4
ashiftleft              // [mask, shift, ret, A, B]
loadsp 16
im \fmask
and
loadsp 8
ashiftleft              // [value << shift, mask, shift, ret, A, B]
loadsp 16
im -4
and
load                    // [word, newbits, mask, ...]
loadsp 8
not
and                     // word with the old part cleared
or                      // [merged, mask, shift, ret, A, B]
loadsp 16
im -4
and
store                   // [mask, shift, ret, A, B]
loadsp 8
storesp 20              // ret over B's slot
pushsp
im 16
add
popsp                   // SP now points at that slot
poppc
.endm


.section ".fixed_vectors","ax"

// RESET: slot 0x00, jump out to the C runtime setup in .text
.globl _start
.org 0x0
_start:
jmp _premain

// INTERRUPT: slot 0x20, hardware pushes the interrupted PC and jumps here
// The body does not fit in 32 bytes, so jump out to .text (poppc at the end returns to the interrupted PC)
.globl _zpu_interrupt_vector
.org 0x20
_zpu_interrupt_vector:
jmp _interrupt_body

// LOADH: opcode 34 = EMULATE 2, 2*32 = 0x040
.org 0x040
_loadh:
loadsp 4
im -4
and
load
loadsp 8
im 2
and
negate
im 2
add
addsp 0
addsp 0
addsp 0
lshiftright
im 65535
and
storesp 8
poppc

// STOREH: opcode 35 = EMULATE 3, 3*32 = 0x060
.org 0x060
_storeh:
jmp _storeh_body

// LESSTHAN: opcode 36 = EMULATE 4, 4*32 = 0x080
.org 0x080
_lessthan:
flipsignbit 4
flipsignbit 8
im _ulessthan
poppc

// LESSTHANOREQUAL: opcode 37 = EMULATE 5, 5*32 = 0x0A0
.org 0x0A0
_lessthanorequal:
flipsignbit 4
flipsignbit 8
im _ulessthanorequal
poppc

// ULESSTHAN: opcode 38 = EMULATE 6, 6*32 = 0x0C0
.org 0x0C0
_ulessthan:
loadsp 4
not
loadsp 12
or
loadsp 8
loadsp 16
negate
add
and
loadsp 8
not
loadsp 16
and
or
flip
im 1
and
storesp 12
storesp 4
poppc

// ULESSTHANOREQUAL: opcode 39 = EMULATE 7, 7*32 = 0x0E0
.org 0x0E0
_ulessthanorequal:
loadsp 8
not
loadsp 8
or
loadsp 12
loadsp 12
negate
add
and
loadsp 12
not
loadsp 12
and
or
flip
im 1
and
im 0
eq
storesp 12
storesp 4
poppc

// MULT: opcode 41 = EMULATE 9, 9*32 = 0x120
.org 0x120
_mult:
jmp _mult_body

// LSHIFTRIGHT: opcode 42 = EMULATE 10, 10*32 = 0x140
// reverse the bits, shift left, reverse back
.org 0x140
_lshiftright:
loadsp 8
flip
loadsp 8
ashiftleft
flip
storesp 12
storesp 4
poppc

// ASHIFTLEFT: opcode 43 = EMULATE 11, 11*32 = 0x160
// enter the ladder in .text (n bytes before the end) so the value is doubled n times
.org 0x160
_ashiftleft:
loadsp 8
loadsp 8
im 31
and
negate
im _ashiftleftEnd
add
poppc

// CALL: opcode 45 = EMULATE 13, 13*32 = 0x1A0
.org 0x1A0
_call:
loadsp 4
loadsp 4
storesp 12
storesp 4
poppc

// EQ: opcode 46 = EMULATE 14, 14*32 = 0x1C0
.org 0x1C0
_eq:
loadsp 4
loadsp 12
negate
add
loadsp 0
negate
or
not
flip
im 1
and
storesp 12
storesp 4
poppc


// NEQ: opcode 47 = EMULATE 15, 15*32 = 0x1E0
.org 0x1E0
_neq:
loadsp 4
loadsp 12
eq
im 0
eq
storesp 12
storesp 4
poppc

// NEG: opcode 48 = EMULATE 16, 16*32 = 0x200
.org 0x200
_neg:
loadsp 4
negate
storesp 8
poppc

// SUB: opcode 49 = EMULATE 17, 17*32 = 0x220
// NB: next minus top (B - A), the opposite of the A-first order used by the comparisons
.org 0x220
_sub:
loadsp 8
loadsp 8
negate
add
storesp 12
storesp 4
poppc

// XOR: opcode 50 = EMULATE 18, 18*32 = 0x240
.org 0x240
_xor:
loadsp 4
loadsp 12
or
loadsp 8
loadsp 16
and
not
and
storesp 12
storesp 4
poppc

// LOADB: opcode 51 = EMULATE 19, 19*32 = 0x260
// big-endian: byte 0 of a word is the most significant byte
.org 0x260
_loadb:
loadsp 4
im -4
and
load
loadsp 8
im 3
and
negate
im 3
add
addsp 0
addsp 0
addsp 0
lshiftright
im 255
and
storesp 8
poppc

// STOREB: opcode 52 = EMULATE 20, 20*32 = 0x280
.org 0x280
_storeb:
jmp _storeb_body

//EQBRANCH: opcode 55 = emulate 23, 23*32 = 0x2E0
.org 0x2E0
_eqbranch:
loadsp 8 // cond
loadsp 0 // dup
negate
or // cond != 0 -> top bit = 1
not // top bit = 1 iff cond == 0
flip // move top bit to bit 0
im 1 // isolate bit 0
and // 1 if cond == 0 else 0
negate // mask
loadsp 8 // offset
im -1
add
and // (offset - 1) & mask
loadsp 4
add
storesp 12
pushsp
im 8
add
popsp
poppc

//NEQBRANCH: opcode 56 = emulate 24, 24*32 = 0x300
.org 0x300
_neqbranch: // [ret, offset, cond, rest]
loadsp 8 // cond
loadsp 0 // dup
negate
or // cond != 0 -> top bit = 1
flip // move top bit to bit 0
im 1 // isolate bit 0
and // 1 if cond != 0 else 0
negate // mask
loadsp 8 // offset
im -1
add
and // (offset - 1) & mask
loadsp 4
add
storesp 12
pushsp
im 8
add
popsp
poppc

//POPPCREL: opcode 57 = emulate 25, 25*32 = 0x320
.org 0x320
_poppcrel:
add
im -1
add
poppc

// PUSHSPADD: opcode 61 = EMULATE 29, 29*32 = 0x3A0
// result = (address of the popped value N) + 4*N. The address of N is SP + 4 because EMULATE pushed ret.
.org 0x3A0
_pushspadd:
pushsp
im 4
add
loadsp 8
addsp 0
addsp 0
add
storesp 8
poppc

//CALLPCREL: opcode 63 = emulate 31, 31*32 = 0x3E0
.org 0x3E0
_callpcrel:
loadsp 4
loadsp 4
add
im -1
add
loadsp 4
storesp 12
storesp 4
poppc


/*
 * Slots not written yet (all still zero = breakpoint):
 *   0x100 SWAP (40)        0x180 ASHIFTRIGHT (44)  0x2A0 DIV (53)
 *   0x2C0 MOD (54)         0x340 CONFIG (58)       0x360 PUSHPC (59)
 *   0x380 SYSCALL (60)     0x3C0 HALFMULT (62)
 */


.text

// C runtime entry, reached from _start
// TODO(memory map): copy .data, zero .bss, point the memory registers at _memreg
.globl _premain
_premain:
im main
call
// main returned
breakpoint

// Interrupt body: save the memory registers the C handler may clobber, call it, restore them
// Zylin saves absolute addresses 0/4/8 here; this uses _memreg, check which one the toolchain really uses
_interrupt_body:
im _memreg+0
load
im _memreg+4
load
im _memreg+8
load
im _zpu_interrupt
call
im _memreg+8
store
im _memreg+4
store
im _memreg+0
store
poppc

// ASHIFTLEFT ladder: each addsp 0 doubles the top of the stack
_ashiftleftBegin:
.rept 31
addsp 0
.endr
_ashiftleftEnd:
storesp 12
storesp 4
poppc


// STOREB / STOREH bodies (too long for a 32-byte slot)
_storeb_body:
storepart 3, 3, 255
_storeh_body:
storepart 2, 2, 65535

// MULT body: shift-and-add, loops until A runs out of bits
// frame: [acc, ret, a, b, rest]
_mult_body:
im 0                    // acc = 0
_multLoop:
loadsp 8                // a
im 1
and
negate                  // mask = -(a & 1)
loadsp 16               // b
and
add                     // acc += b & mask
loadsp 8
flip
addsp 0
flip
storesp 12              // a >>= 1 (logical)
loadsp 12
addsp 0
storesp 16              // b <<= 1
loadsp 8
loadsp 0
negate
or
flip
im 1
and                     // 1 if a != 0
negate                  // all ones: loop again
im _multLoop - _multExit
and
im _multExit
add                     // target = exit + (loop - exit) & mask
poppc
_multExit:
storesp 12              // result over b's slot
storesp 4               // ret over a's slot
poppc
