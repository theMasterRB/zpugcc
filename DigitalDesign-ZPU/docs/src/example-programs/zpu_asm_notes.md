# ZPU Assembly Notes

How to read the assembly that `zpu-elf-gcc -S` (GCC 3.4.2) produces. The notes are built from small test programs compiled at `-O0`. They cover the boilerplate every function has, then locals, function calls, and doubles.

The more complex behavior (the random `nop`s, frame sizes, how calls and doubles work) was figured out by investigating the zylin zpu-gcc repo with the help of AI to parse the compiler and runtime code. The function call and double traces were also checked by running the assembly through a small stack simulator, with the soft-float helper functions faked.

## What the ZPU is

The ZPU has no general purpose registers. It has a stack pointer (SP) and a program counter (PC). Every instruction pops its inputs off the stack and pushes its result back.

There is one stack. Return addresses, saved values, locals, function arguments, and temporary results all live on it. The stack grows down, so pushing makes SP smaller.

Memory is big-endian: the most significant byte of a word is at the lowest address.

## Fake registers

GCC needs registers, so it fakes them in two ways.

**Memory registers (r0 to r7).** A fixed block of memory called `_memreg`. Each 4 byte slot is one register: `_memreg+0` is r0, `_memreg+4` is r1, `_memreg+12` is r3. Reading one is `im _memreg+N` then `load`. Writing one is `im _memreg+N` then `store`.

| Slot | Register | Job |
|---|---|---|
| `_memreg+0` | r0 | Return value |
| `_memreg+12` | r3 | Frame pointer (FP) |

**Stack registers.** Extra registers that live inside the function's stack frame, one word each. At `-O0` almost every function uses at least one as a temporary.

## Instructions

| Instruction | What it does |
|---|---|
| `im x` | Push the number `x`. Has a catch, see the next section. |
| `load` | Pop an address, push the value at that address. |
| `store` | Pop an address, pop a value, write the value to the address. |
| `pushsp` | Push the current SP. |
| `popsp` | Pop a value into SP. |
| `pushspadd` | Pop N, push `SP + N*4` (SP from before the pop). |
| `loadsp n` | Push a copy of the value at `SP + n`. `n` is in **bytes**. `loadsp 0` is a dup. |
| `storesp n` | Write the top value to `SP + n`, then pop it. `n` is in **bytes**, measured from SP before the pop. |
| `addsp n` | Add the value at `SP + n` to the top value, in place. No pop. |
| `add` | Pop two, push the sum. |
| `mult` | Pop two, push the product. |
| `div` | Pop `a` (top), pop `b`, push `a / b`. **The top is the dividend.** |
| `nop` | Do nothing. Separates two `im`s. |
| `impcrel (f)` | Push the address of function `f` as a PC-relative offset. Always paired with `callpcrel`. |
| `callpcrel` | Pop the offset, push the return address, jump to the function. |
| `poppc` | Pop an address and jump to it. Used to return. |

## The `im` instruction and the random `nop`

One IM opcode only holds 7 bits. To build bigger numbers, the CPU chains them: if the previous instruction was also an IM, the new IM shifts the top of stack left by 7 and ORs its bits in instead of pushing.

So `im x` in the `.s` file becomes 1 to 5 IM bytes once assembled. Small numbers take 1 byte. Symbols like `_memreg+12` always take 5 because the address isn't known until link time.

The catch: two `im` lines in a row would merge into one number. The compiler prevents this by putting a `nop` between them:

```
im 2              ; value to store
nop               ; break the chain
im _memreg+12     ; start of the address calculation
```

If you hand-write two `im`s back to back, the assembler refuses with `Two consequtive IM instructions is illegal`. **Rule: any two `im` lines that would touch get a `nop` between them.**

## Function boilerplate

Every function starts and ends the same way.

**Prologue.** Save the caller's FP, set the new one:

```
im _memreg+12
load              ; push caller's FP
pushsp
im _memreg+12
store             ; r3 = SP (points at the saved caller FP)
```

**Reserve the frame:**

```
im N
pushspadd
popsp             ; SP moves down by (1 - N) words
```

`im N` itself pushes a word, and `pushspadd` measures from that already-moved SP. That's why the number looks off by one. **Frame size in words = 1 - N.**

**Epilogue.** Free the frame, restore FP, return:

```
im M
pushspadd
popsp             ; free the frame: (M - 1) words
im _memreg+12
store             ; r3 = caller's FP (now on top of stack)
poppc             ; pop return address, jump
```

**Frame size in words = M - 1.** Entry and exit always pair up: `im 0` with `im 2`, `im -1` with `im 3`, `im -19` with `im 21`.

### What's in the frame

From FP going down:

```
FP+4    return address          (pushed by the caller's callpcrel)
FP+0    caller's saved FP        (pushed by the prologue)
FP-4    locals                   first local at FP-4, next at FP-8, ...
 ...    stack registers
 ...    outgoing argument area   (only if the function calls something)
SP      bottom of frame
```

Frame sizes from the test programs:

| Function | Entry / exit | Words | Breakdown |
|---|---|---|---|
| `return 1` | `im 0` / `im 2` | 1 | 1 stack reg |
| `a = 2; return a+5` | `im -1` / `im 3` | 2 | 1 local, 1 stack reg |
| `add` | `im 0` / `im 2` | 1 | 1 stack reg |
| `mul`, `div` | `im -2` / `im 4` | 3 | 1 stack reg, 2 unused arg words (see "mult and div") |
| `ddiv` | `im -10` / `im 12` | 11 | 2 local temp, 4 stack regs, 5 arg words |
| `main` (functions.c) | `im -19` / `im 21` | 20 | 12 locals, 3 stack regs, 5 arg words |

### Stack trace of `return 1`

Top of stack on the left. `sr` is the stack register slot.

| After | Stack | Notes |
|---|---|---|
| entry | `ret` | |
| `im _memreg+12; load` | `oldFP, ret` | |
| `pushsp` | `&oldFP, oldFP, ret` | |
| `im _memreg+12; store` | `oldFP, ret` | r3 = `&oldFP` |
| `im 0; pushspadd; popsp` | `sr, oldFP, ret` | 1 word reserved |
| `im 1; loadsp 0` | `1, 1, sr, oldFP, ret` | |
| `im _memreg+0; store` | `1, sr, oldFP, ret` | r0 = 1 |
| `storesp 4` | `sr=1, oldFP, ret` | copy parked in `sr` |
| `im 2; pushspadd; popsp` | `oldFP, ret` | frame freed |
| `im _memreg+12; store` | `ret` | r3 restored |
| `poppc` | (empty) | return |

## Local variables

A local is just a slot at a fixed offset below FP. Getting its address always looks like this:

```
im _memreg+12
load              ; push FP
im -4
add               ; push FP - 4 (address of the first local)
```

Then `store` to write it, or `load` to read it. At `-O0` the address is recomputed every single time the variable is used, even twice in one line.

## Return values

An `int` result ends up in r0. The usual ending of a function body:

```
loadsp 0          ; dup the result
im _memreg+0
store             ; r0 = result
storesp 4         ; other copy goes into a stack register
```

The second copy is leftover from unoptimized code and is never read. Sometimes the `storesp` into the stack register doesn't happen right away (see main in functions.c, where it's delayed until after the next call's arguments are set up).

## Function calls

### Caller side

The caller doesn't push arguments for each call. The outgoing argument area is already reserved at the bottom of its frame, sized for the biggest call it makes. Arguments go in by pushing the value, then using `storesp` to drop it into its slot. arg0 goes at SP+0, arg1 at SP+4, and so on:

```
; add(num1, num2), arguments evaluated right to left
... push num2 ...
storesp 8         ; arg1 slot (SP+4 once this value is popped)
... push num1 ...
storesp 4         ; arg0 slot (SP+0)
impcrel (add)
callpcrel         ; call add
im _memreg+0
load              ; push the result from r0
```

At the moment of the call, arg0 sits exactly at the caller's SP. `callpcrel` pushes the return address right below it.

### Callee side

After the prologue, the callee's view is:

```
FP+12   arg1  (y)
FP+8    arg0  (x)
FP+4    return address
FP+0    caller's saved FP
```

So parameters are read at positive offsets from FP, while locals are at negative offsets:

```
im _memreg+12
load
im 8
add
load              ; push x (FP+8)
```

The callee never removes the arguments. They're part of the caller's frame, and the caller reuses that area for the next call.

## mult and div

```
; mul: return x * y
push x (FP+8)
push y (FP+12)
mult

; div: return x / y
push y (FP+12)    ; y first
push x (FP+8)     ; x on top
div               ; top / next = x / y
```

`div` divides the top of stack by the value under it. That's why the compiler pushes `y` first. Keep this in mind for instruction tests: the operand order is the opposite of what you'd guess from `a b div`.

Other things these two functions show:

- **`.globl __mulsi3` / `.globl __divsi3`.** These are the library helper functions for multiply and divide. `mul` and `div` declare them and reserve 2 words of argument space in their frames, but never call them or touch that space.
- **They may not be real hardware instructions.** On the small ZPU core, `mult`, `div`, `callpcrel`, and `pushspadd` are "emulated": the CPU jumps to handler code that does the work in software. The `div` handler calls `__divsi3`, so a program using `div` still needs that helper linked in. Which opcodes are emulated depends on the core, so check with the hardware subteam.

## Doubles

The ZPU has no floating point hardware. Every `double` operation is a call to a soft-float helper function.

| C | Helper | Does |
|---|---|---|
| `x / y` (doubles) | `__divdf3` | double divide |
| `(double) n` | `__floatsidf` | int to double |
| `(int) d` | `__fixdfsi` | double to int (truncates) |

The `.globl __divdf3` style lines before a function list the helpers it uses.

### Layout

A double is 2 words. Big-endian, so the high word (sign, exponent, top of the mantissa) is at the lower address:

```
5.0 = 0x40140000 00000000
      FP-28: 0x40140000   (high)
      FP-24: 0x00000000   (low)
```

A double argument takes 2 argument slots, high word first.

### Returning a double

A double doesn't fit in r0. Instead the caller passes a **hidden pointer as arg0** that says where to put the result, and every real argument shifts over by one slot:

```
C:      ddiv(x, y)
Really: ddiv(&result, x_high, x_low, y_high, y_low)

Inside ddiv:
FP+8    hidden result pointer
FP+12   x high      FP+16   x low
FP+20   y high      FP+24   y low
```

The callee writes the 2 result words through that pointer, and also puts the pointer itself in r0. The helpers work the same way: `__divdf3` and `__floatsidf` both return doubles, so both take a hidden pointer first. `__fixdfsi` returns an int, so it has no hidden pointer and its arguments are just `[high, low]`.

`ddiv` itself doesn't write straight into the caller's slot. It passes the address of its own local temp to `__divdf3`, then copies the 2 words out:

```
loadsp 20         ; push result high (from a stack register)
loadsp 36         ; push the hidden result pointer
store             ; *ptr = high
loadsp 24         ; push result low
im 4
addsp 40          ; top = 4 + hidden pointer
store             ; *(ptr + 4) = low
loadsp 32
im _memreg+0
store             ; r0 = hidden pointer
```

### Casts in main

```
d_div = ddiv(num1, num2);
```

The ints have to become doubles first, so this one line turns into 3 calls:

1. `__floatsidf(&tmp, num2)`, then copy `tmp` into arg3/arg4 (y)
2. `__floatsidf(&tmp, num1)`, then copy `tmp` into arg1/arg2 (x)
3. `ddiv(&d_div, ...)`: ddiv writes straight into `d_div`

Step 2 only overwrites arg0 and arg1, so y sitting in arg3/arg4 survives. Arguments are handled right to left, which is why num2 is converted first.

`dcast = (double) num1` is one `__floatsidf` call into a temp, then a 2-word copy into `dcast`. `icast = (int) d_div` pushes d_div's 2 words as the arguments to `__fixdfsi` and stores r0.

### Stack slot reuse

In `main`, `FP-36` is first used as the scratch double for the int to double conversions, and later becomes `dcast`. So one address doesn't always mean one variable for the whole function.

Frame map for `main`:

| Offset | Holds |
|---|---|
| FP-4 | num1 |
| FP-8 | num2 |
| FP-12 | sum |
| FP-16 | prod |
| FP-20 | idiv |
| FP-28, FP-24 | d_div (high, low) |
| FP-36, FP-32 | scratch double, later dcast |
| FP-44, FP-40 | scratch double for the dcast line |
| FP-48 | icast |
| FP-60 to FP-52 | 3 stack registers |
| FP-80 to FP-64 | argument area, arg0 at FP-80 (= SP) |

## Reading `loadsp` / `storesp` offsets

The offset is from the **current** SP, and SP moves with every push and pop. So the same slot shows up with different numbers depending on how much is on the stack at that moment. In `ddiv`, both of these write to different slots:

```
storesp 36        ; 2 values pushed: writes FP-16
storesp 36        ; 1 value pushed:  writes FP-12
```

To work out which slot a `loadsp`/`storesp` touches, count how many values are sitting above the frame bottom at that point. A small stack table like the one for `return 1` is the easiest way.

## Things to watch for in tests

- **`div` is top / next.** The operand order is backwards from what you'd guess.
- **Always `return` from main.** `main` in functions.c has no return statement, so r0 ends up holding whatever was in a stack register (here, `icast`, which is 0 by coincidence). Return a known value if your test checks r0.
- **Locals die on return.** After the epilogue frees the frame, its own pushes (like `im _memreg+12`) land on top of old locals. `num1`'s slot got overwritten that way. Only check a function's locals while it's still running.
- **Emulated opcodes.** On a small core, `div` quietly depends on `__divsi3`. An instruction test for `mult`/`div`/`callpcrel`/`pushspadd` may really be testing the emulation handler.
- **Unused frame space.** `mul`/`div` reserve 2 words that are never touched. Don't treat frame size as a count of real locals.

## Quick reference

| You see | It means |
|---|---|
| `im _memreg+0` ... `store` | writing the return value (r0) |
| `im _memreg+0; load` right after `callpcrel` | reading a call's result |
| `im _memreg+12; load; im -K; add` | address of a local at `FP - K` |
| `im _memreg+12; load; im K; add` (K = 8, 12, ...) | address of a parameter |
| `im N; pushspadd; popsp` at the top | frame of `1 - N` words |
| `im M; pushspadd; popsp` at the bottom | frame of `M - 1` words |
| `nop` between two `im`s | breaking the IM chain |
| `loadsp 0; im _memreg+0; store; storesp 4` | result to r0, copy to a stack register |
| `push ...; storesp K` before a call | placing an argument in the outgoing area |
| `impcrel (f); callpcrel` | call `f` |
| `.globl __xxx` before a function | library helper the function uses (or might) |
| hidden pointer at FP+8 | function returns a double |

## Glossary

| Term | Meaning |
|---|---|
| **SP** | Stack pointer. Holds the address of the top of the stack. |
| **PC** | Program counter. Holds the address of the next instruction to run. |
| **FP** | Frame pointer. Points at the current function's frame. On the ZPU it's the fake register r3 (`_memreg+12`). |
| **TOS** | Top of stack. The value SP points at. |
| **NOS** | Next on stack. The value right under TOS. |
| **Word** | 4 bytes (32 bits). The size of an `int`, an address, and one stack slot. |
| **Stack frame** | The block of stack a function reserves for itself: locals, stack registers, and argument space. |
| **Prologue** | The code at the start of every function that saves the caller's FP and reserves the frame. |
| **Epilogue** | The code at the end of every function that frees the frame, restores FP, and returns. |
| **Boilerplate** | Code that shows up the same way in every function no matter what the function does. |
| **Local variable** | A variable declared inside a function. Lives in that function's frame. |
| **Parameter / argument** | A value passed into a function. Arguments are what the caller passes; parameters are what the callee receives. |
| **Caller / callee** | The function making a call / the function being called. |
| **Return address** | Where to jump back to when a function finishes. Pushed by `callpcrel`, used by `poppc`. |
| **Outgoing argument area** | Space at the bottom of a caller's frame where it writes arguments before a call. |
| **Hidden pointer** | An extra first argument the compiler adds when a function returns something too big for r0, like a double. Points at where the result goes. |
| **Immediate** | A constant number written directly in an instruction, like the `5` in `im 5`. |
| **Offset** | A distance from some base address, like the `-4` in `FP - 4`. |
| **Dup** | Duplicate. Push a second copy of the top value (`loadsp 0`). |
| **Pseudo-register** | A fake register the compiler uses when the CPU has no real one. On the ZPU: the `_memreg` slots and the stack registers. |
| **Stack register** | A pseudo-register that lives in a word of the function's frame. |
| **`_memreg`** | The fixed block of memory holding r0 to r7. |
| **r0** | The fake register holding a function's return value (`_memreg+0`). |
| **r3** | The fake register holding the frame pointer (`_memreg+12`). |
| **Big-endian** | Byte order where the most significant byte is stored at the lowest address. For a double, the high word comes first. |
| **High word / low word** | The top 32 bits / bottom 32 bits of a 64-bit value like a double. |
| **Double** | 64-bit floating point number. Takes 2 words on the ZPU. |
| **Soft-float** | Doing floating point math with regular integer code (helper functions) because the CPU has no floating point hardware. |
| **Helper function / libcall** | A small library function the compiler calls for operations the CPU can't do in one instruction, like `__divdf3`. |
| **libgcc** | The library that holds GCC's helper functions. |
| **Emulated opcode** | An instruction that isn't built into a small ZPU core. The CPU jumps to handler code that does the work in software instead. |
| **Opcode** | The numeric code for one machine instruction. On the ZPU, each opcode is 1 byte. |
| **Opcode chaining (IM)** | Back-to-back IM opcodes combine into one bigger number instead of pushing separately. Why `nop`s get inserted. |
| **PC-relative** | An address stored as a distance from the current instruction instead of as a fixed location. Used by `impcrel`. |
| **Directive** | A line starting with `.` (like `.globl`, `.size`). Tells the assembler something; not a CPU instruction. |
| **`.globl`** | Directive that makes a name visible to other files, or declares a function from another file. |
| **Symbol** | A name that stands for an address, like `main` or `_memreg`. |
| **Link time** | When the linker combines compiled files into one program and fills in the real addresses of symbols. |
| **`-S`** | GCC flag to stop after generating assembly (`.s` file) instead of building a program. |
| **`-O0`** | GCC flag for no optimization. The default. Produces the most literal, repetitive code. |
| **Cast** | Converting a value from one type to another, like `(double) num1`. |
| **Truncate** | Drop the fractional part. `(int) 0.83` is `0`. |
