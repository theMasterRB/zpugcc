# ZPU crt0 Guide: Startup, Vectors and Opcode Emulation

Nov 8, 2026 · @Romir Gade

## Memory layout at a glance

22 of the 26 opcodes in the team's spec have handlers, and both vector slots have skeletons. The table is the whole `0x000` to `0x3FF` region, one row per 32-byte slot.

Opcodes 32 to 63 are `EMULATE` instructions. The core pushes the return address and jumps to the slot address:

```latex
\text{slot address} = (\text{opcode} - 32) \times 32
```

So NEG (opcode 48) lives at `0x200`.

| Address | Opcode | Name | Status |
| --- | --- | --- | --- |
| `0x000` | n/a | Reset (`_start`) | Skeleton |
| `0x020` | n/a | Interrupt vector | Skeleton |
| `0x040` | 34 | LOADH | Written |
| `0x060` | 35 | STOREH | Written |
| `0x080` | 36 | LESSTHAN | Written |
| `0x0A0` | 37 | LESSTHANOREQUAL | Written |
| `0x0C0` | 38 | ULESSTHAN | Written |
| `0x0E0` | 39 | ULESSTHANOREQUAL | Written |
| `0x100` | 40 | SWAP | **Blocked**: not in the team's spec |
| `0x120` | 41 | MULT | Written |
| `0x140` | 42 | LSHIFTRIGHT | Written |
| `0x160` | 43 | ASHIFTLEFT | Written |
| `0x180` | 44 | ASHIFTRIGHT | **Blocked**: spec note "error for opcode" |
| `0x1A0` | 45 | CALL | Written |
| `0x1C0` | 46 | EQ | Written |
| `0x1E0` | 47 | NEQ | Written |
| `0x200` | 48 | NEG | Written |
| `0x220` | 49 | SUB | Written |
| `0x240` | 50 | XOR | Written |
| `0x260` | 51 | LOADB | Written |
| `0x280` | 52 | STOREB | Written |
| `0x2A0` | 53 | DIV | **Blocked**: needs memory map and libgcc check |
| `0x2C0` | 54 | MOD | **Blocked**: needs memory map and libgcc check |
| `0x2E0` | 55 | EQBRANCH | Written |
| `0x300` | 56 | NEQBRANCH | Written |
| `0x320` | 57 | POPPCREL | Written |
| `0x340` | 58 | CONFIG | **Blocked**: not in the team's spec |
| `0x360` | 59 | PUSHPC | **Blocked**: spec entry is blank |
| `0x380` | 60 | SYSCALL | **Blocked**: no OS, design decision needed |
| `0x3A0` | 61 | PUSHSPADD | Written |
| `0x3C0` | 62 | HALFMULT | **Blocked**: not in the team's spec |
| `0x3E0` | 63 | CALLPCREL | Written |


### Why some slots are not written yet

**Blocked** means the handler cannot be written correctly until something outside this file is settled. Every opcode that could be written was implemented, these examples require communication with other teams to hammer down the spec..

| Opcode | Why it is blocked | What it needs to be implemented |
| --- | --- | --- |
| DIV, MOD | They need a 32-step shift-and-subtract loop, which is easy. The open question is whether compiled code ever reaches them: GCC may call libgcc routines instead. The team notes say div is top / next. | The memory map, and a check of what libgcc provides, so we don't write something the toolchain never calls. |
| ASHIFTRIGHT | The spec entry says "(error for opcode)", so the intended behaviour is unclear. The arithmetic version must copy the sign bit into the vacated bits. | The core team to say what the entry means. |
| PUSHPC | The spec entry is blank, and Zylin's version looks wrong. | The core team to define it: what value is pushed, and relative to which address. |
| SYSCALL | The compiled stdio code calls it, but there is no OS. Whether it should print, halt, or talk to a memory-mapped UART is a hardware and software design decision. | A decision with the core team, plus the IO base address. Until then the slot stays a `breakpoint`. |
| SWAP, CONFIG, HALFMULT | Not defined in the team's spec. | Confirm whether the core implements them. If it does, define their behaviour first. |

An unwritten slot is zero, which decodes as `BREAKPOINT`, so using one by mistake stops the core instead of corrupting data.

## Reading the stack inside a handler

Every handler starts from the same picture. **A** is the top operand and **B** is the one under it. The core team confirmed that A is always the top of the stack.

| Offset from SP | Holds |
| --- | --- |
| `SP+0` | return address (pushed by EMULATE) |
| `SP+4` | operand A (top) |
| `SP+8` | operand B |
| `SP+12` | the rest of the caller's stack |

Two instructions do most of the work, and both use **byte** offsets:

- `loadsp n` pushes a copy of the word at `SP+n`.
- `storesp n` pops the top and writes it to `SP+n`, where `n` is counted from SP **before** the pop.

**The counting rule.** Every push moves SP down 4 bytes, so a value you want to reach keeps moving further away. Every consuming op (`add`, `and`, `or`, `store`) pops two values and pushes one, so offsets shift back by 4. When tracing, write the stack out after every instruction. Most bugs in this file were an offset that was off by one slot.

**The standard ending.** A two-operand handler has to leave one result in place of A and B, then return:

```
storesp 12   // result over B's slot
storesp 4    // return address over A's slot
poppc        // jump back
```

After the first `storesp 12`, the stack is `[ret, A, result, rest]`. After `storesp 4` it is `[result, rest]` plus the return address, which `poppc` consumes.

**Operand order.** Only SUB breaks ordinary maths convention: it computes B − A, so `5 3 sub` leaves 2. Comparisons are A < B and A <= B. Shifts move B by the count A.

## A tour of crt0.S

The file has two sections: `.fixed_vectors` for the 32-byte slots and `.text` for everything that doesn't fit in one.

**`.section ".fixed_vectors","ax"`** declares an allocatable, executable section. The linker script puts it at address 0. Each handler starts with `.org 0xNNN`, which moves the write position to that exact byte so the slot lands where EMULATE will jump. Two rules follow from this:

- A handler must fit before the next `.org`. If it doesn't, the next `.org` would go backwards and the assembler stops with an error. That error is a useful size check.
- The gap between the end of a handler and the next `.org` is filled with zeros, and zero is `BREAKPOINT`. A slot you haven't written fails loudly instead of running garbage.

We use `.org` rather than `.balign` because `.org` names the address directly. The slot address is the opcode arithmetic: (opcode − 32) × 32.

**`.text`** holds everything that doesn't fit in 32 bytes: `_premain`, `_interrupt_body`, and the shift ladder. Handlers reach it with `im label` followed by `poppc`.

**Immediates.** `im` loads a number 7 bits at a time, so small numbers take one byte and large ones take up to five. A symbolic `im` (a label whose value isn't known yet) is always reserved as five bytes. The linker may shrink it and pad with `nop`s, which is why the dump shows `nop`s before some `im`s.

## Handler catalog

Each handler has 32 bytes. Sizes are measured from the assembled image with every label-based `im` counted at its full 5 bytes, so the real size after linking can only be smaller.

| Handler | Address | Bytes used | How it works |
| --- | --- | --- | --- |
| LOADH | `0x040` | 22 | Load the aligned word, shift the wanted halfword down, mask to 16 bits |
| STOREH | `0x060` | 7 (+ body in `.text`) | Jump to `_storeh_body`: read-modify-write of the aligned word |
| LESSTHAN | `0x080` | 16 | Add the sign bias to both operands, jump to ULESSTHAN |
| LESSTHANOREQUAL | `0x0A0` | 16 | Same bias, jump to ULESSTHANOREQUAL |
| ULESSTHAN | `0x0C0` | 22 | Borrow formula, take the top bit |
| ULESSTHANOREQUAL | `0x0E0` | 24 | ULESSTHAN's formula with the inputs swapped, then inverted |
| MULT | `0x120` | 7 (+ body in `.text`) | Jump to `_mult_body`: shift-and-add loop that ends when A has no bits left |
| LSHIFTRIGHT | `0x140` | 8 | Bit-reverse, shift left, bit-reverse |
| ASHIFTLEFT | `0x160` | 14 | Jump into the ladder in `.text` at the right rung |
| CALL | `0x1A0` | 5 | Swap the target and the return address, then `poppc` |
| EQ | `0x1C0` | 18 | Zero test on A − B |
| NEQ | `0x1E0` | 8 | EQ, then compare with 0 |
| NEG | `0x200` | 6 | `negate` macro |
| SUB | `0x220` | 9 | B + (−A) |
| XOR | `0x240` | 11 | (A or B) and not (A and B) |
| LOADB | `0x260` | 21 | Like LOADH with a byte shift and an 8-bit mask |
| STOREB | `0x280` | 7 (+ body in `.text`) | Jump to `_storeb_body`: same macro as STOREH with byte constants |
| EQBRANCH | `0x2E0` | 25 | Zero test makes a mask, mask selects the offset, then `popsp` |
| NEQBRANCH | `0x300` | 24 | Same with the zero test inverted |
| POPPCREL | `0x320` | 4 | ret − 1 + offset, `poppc` |
| PUSHSPADD | `0x3A0` | 9 | (address of N) + 4N |
| CALLPCREL | `0x3E0` | 9 | Same target as POPPCREL, then CALL's swap |

The tightest in-slot handlers are EQBRANCH at 25 bytes and ULESSTHANOREQUAL at 24. STOREH, STOREB and MULT do not fit in 32 bytes, so their slots only jump to bodies in `.text`; STOREH and STOREB share one macro (`storepart`).

## Reset, interrupts and \_premain

**Reset (`0x00`).** When the core powers up, the PC is 0, so the first instruction it runs is `_start`. Thirty-two bytes is too small for C runtime setup, so `_start` is only `jmp _premain`.

**`_premain` (in `.text`).** It does `im main; call; breakpoint`. `call` is the ZPU instruction that swaps the top of the stack with the PC, so this runs `main`. If `main` returns, the `breakpoint` stops the core instead of running into whatever follows. Three jobs are still marked TODO and depend on the memory map:

1. Copy initialised `.data` from where it was loaded.
2. Zero `.bss`.
3. Point the memory registers at `_memreg`.

**Interrupt vector (`0x20`).** When an interrupt arrives, the core pushes the interrupted PC and jumps to `0x20`, so the handler is entered like an EMULATE handler. The slot is a `jmp _interrupt_body`.

**`_interrupt_body`.** C code may overwrite the memory registers (`_memreg+0`, `+4`, `+8`) that the interrupted code was using. The body:

1. Pushes the three registers onto the stack with `load`s.
2. Calls the C function `_zpu_interrupt`.
3. Stores the registers back in reverse order.
4. Ends with `poppc`, which returns to the interrupted instruction.

Zylin's original saves absolute addresses 0, 4 and 8 instead of `_memreg`. Which one our toolchain really uses is an open question (see Assumptions).

## The linker script (crt0.ld)

The assembler produces a `.o` file with sections but no addresses. The linker script decides where each section goes in memory. Ours is a skeleton and **has not yet been run through `zpu-elf-ld`**.

| Piece | What it does |
| --- | --- |
| `ENTRY(_start)` | Names the first instruction. |
| `MEMORY { RAM ... }` | One region for code and data, since the ZPU has a single address space. Origin 0, length `0x8000` are placeholders. |
| `_io_base` | Placeholder for the start of memory-mapped IO. |
| `.fixed_vectors 0x0` | Pinned at address 0 with `KEEP`, so the linker never drops it. It must be first because EMULATE jumps to fixed addresses. |
| `.text`, `.rodata` | Code and constants, right after the vectors. |
| `.data`, `.bss` | Initialised and zero-initialised variables, with `_data_start`, `_data_end`, `_bss_start`, `_bss_end` symbols for `_premain` to use. |
| `_memreg` | 32 bytes, 16-byte aligned, for the compiler's memory registers. |
| `_heap_start` | Where `malloc` would begin, if used. |

**Placeholders that need the core team:**

- RAM base and size.
- IO base address (the core's address bus has an extra bit that selects IO).
- Whether the hardware sets the initial SP, and to what.
- How the toolchain's default script defines `_memreg`. Check with `zpu-elf-ld --verbose | grep -i memreg` and match it.

**Using it:** `zpu-elf-gcc -nostartfiles -T crt0.ld crt0.o prog.o -o prog.elf`. The `.elf` is the linked program, the `.o` files are unlinked pieces, and the `.ld` is this script.

## Assumptions and questions for the core team

The handlers rest on these assumptions. The first is confirmed, the rest are not.

| Assumption or question | Status |
| --- | --- |
| Operand A is always the top of the stack | Confirmed by the core team |
| SUB is B − A; comparisons are A < B and A <= B; shifts move B by A | Matches compiler output; confirm with the core team |
| ASHIFTRIGHT: the spec says "(error for opcode)" | Blocked: what should it do? |
| PUSHPC: the spec entry is blank, and Zylin's version looks wrong | Blocked: what is the intended behaviour? |
| Does `load` fault on an unaligned address, or ignore the low 2 bits as assumed? | Open |
| Where do the memory registers live: `_memreg`, or absolute 0, 4, 8 as in Zylin? | Open |
| Is Zylin's `pushsp; popsp` "flush" in CALL needed on this core? | Open |
| RAM base and size, IO base, initial SP | Needed for `crt0.ld` |
| stdio and SYSCALL: how does a program print without an OS? | Open. Slot `0x380` stays a `breakpoint` for now |
| Do `x << y` and `x >> y` compile to the operand order the handlers expect? | Check with a small C test |

Also unconfirmed: STOREB and STOREH take A as the address and B as the value (as in Zylin's handlers), and neither checks for unaligned access.

## Roadmap and cheat sheet

**Roadmap**

1. Get answers on the blocked opcodes: ASHIFTRIGHT, PUSHPC, SYSCALL, and which of SWAP, CONFIG, HALFMULT the core implements.
2. DIV and MOD, after the memory map and libgcc are settled.
3. Fill in the `crt0.ld` placeholders and run the script through `zpu-elf-ld`.
4. Finish `_premain`: copy `.data`, zero `.bss`, set up the memory registers.
5. Assemble with `zpu-elf-gcc` to check that `MULT`'s label-difference `im` is accepted.
6. Run the handlers on the SystemVerilog core.

**Commands**

| Task | Command |
| --- | --- |
| Assemble crt0 | `zpu-elf-gcc -c crt0.S -o crt0.o` |
| Disassemble the vectors | `zpu-elf-objdump -dr -j .fixed_vectors crt0.o` |
| List symbols and addresses | `zpu-elf-objdump -t crt0.o` |
| C to assembly | `zpu-elf-gcc -S -O0 file.c` |
| Do all of the above | `./build.sh` (C tests in `asm_tests/`) |

**File types:** `.o` is assembled but not linked, `.elf` is linked and runnable, `.ld` is a linker script, `.S` is assembly that goes through the C preprocessor (so macros and comments work as in C).
