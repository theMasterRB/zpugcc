* What is this?  
  * the file that defines emulated instructions in terms of ones that are defined in hardware  
* format/layout  
  * 1\. License header  
    * 2\. .section ".fixed\_vectors","a"    ; everything until .text lands at address 0+  
    * 3\. Macros                           ; fixedim, jsr, jmp, fast\_neg, cimpl, mult1bit  
    * 4\. 0x000  \_start                    ; reset: write CPU ID to \_cpu\_config, jmp \_premain  
    * 5\. 0x020  \_zpu\_interrupt\_vector     ; jsr \_zpu\_interrupt; poppc  
    * 6\. 0x040–0x3E0  one slot per opcode 34–63  
    * 7\. .text                            ; overflow code: \_ashiftleftBegin, \_storebtail,  
    *                                     ;   \_slowmultImpl, \_syscall  
    * 8\. .data                            ; \_mask table (for storeb), \_hardware, \_cpu\_config  
  * 1\. license header  
    * no functional content  
  * 2\. section directive  
    * everything after ‘.section “.fixed\_vectors”,”a”’ up to .text (section 7\) goes into the fixed\_vectors section  
      * linker places this section at address 0, which makes the table’s addresses absolute  
    * the “a” flag means allocatable, leaving out “x” for executable  
      * this is because ZPU linker only relaxes ‘im’ sequences in executable sections  
        * here, relaxing would shrink code and shift handlers off their 32-byte boundaries. without the “x”, every symbolic ‘im’ stays at a fixed 5 bytes and every slot stays where hardware expects it  
    * EXPLANATION OF LINKER RELAXATION  
      * At assembly time, addresses may not be known.  
      * program built in two stages:  
        * each source file (crt0.s, each .c file, and the C library) is assembled SEPARATELY into an object file  
        * the linker then combines the object files into one binary and decides where everything goes in memory  
      * when the assembler processes crt0s, it only sees that one file so it can’t know final addresses  
        * operands, symbols defined outside of crt0.s  
        * so the assembler doesn’t know the size of said operands, symbols unknown   
        * thus, the assembler writes a placeholder and a relocation entry  
          * this is a note to tell the linker “fill in this symbol’s address here later”  
      * The placeholder is worst case size  
        * on ZPU, address is build from ‘im’ bytes carrying 7 bits each  
          * since value is unknown, the assembler has to reserve enough bytes for any 32-bit address.  
            * 5 ‘im’ bytes gives 35 bits.  
      * what does relaxation do?  
        * at link time, addresses are made final (we now know where they are, what they are)  
          * if the real address fits in fewer 7-bit chunks, the linker shrinks the sequence by dropping the leading zero chunks  
          * ex: 0x500 only needs 2 bytes instead of 5  
          * \- Why 0x500 needs only 2 im bytes:  
          *   \- 0x500 \= 1280 \= 10·128 \+ 0 → two 7-bit chunks: 10 | 0  
          *   \- First chunk's bit 6 \= 0 → sign extension keeps it positive  
          *   \- 0x8A: push 10 → 10  
          *   \- 0x80: (10 \<\< 7\) | 0 → 0x500  
          *   \- Unrelaxed 5-byte form (0x80 0x80 0x80 0x8A 0x80) gives the same value; leading zero chunks build 0, and 0 shifted stays 0, so the linker drops them  
          *   \- Rule: n im bytes cover a 7n-bit signed range; 2 bytes span −8192 to 8191  
  * 3\. Macros  
    * These are assembler-time text substitutions, expanded inline with no runtime call overhead

| Macro | Expands to | Purpose |
| ----- | ----- | ----- |
| `fixedim v` | `im v` | Marker for "must not be relaxed." Fixed length really comes from the section flags. |
| `jmp addr` | `im addr; poppc` | Unconditional jump. The core has no jump instruction. |
| `fast_neg` | `not; im 1; add` | Two's-complement negate using only core ops, avoiding a trap into emulated `neg`. |
| `jsr addr` | save R0–R2, `call addr`, restore R0–R2 | Call a subroutine without clobbering GCC's pseudo-registers at 0x0/0x4/0x8. R3 (0xC) is not saved. |
| `cimpl fn` | save regs, copy 2 operands, `call fn`, read result from R0, fix up stack, `poppc` | Implement an emulated op with a C function (`div` → `__divsi3`, `mod` → `__modsi3`). |
| `mult1bit` | one shift-and-add step on \[C, B, A\] | Loop body for software multiply. |

* 4\. reset vector, \_start at 0x000  
  * the ZPU begins executing here after reset, with stack pointer already set to the top of RAM by hardware  
  * the code:  
    * stores the CPU ID into \_cpu\_config  
    * executes config (opcode 58, likely an emulated instruction)  
    * does ‘jmp \_premain”  
* 5\. interrupt vector \_zpu\_interrupt\_vector at 0x020  
  * On interrupt:  
    * an external device asserts the interrupt line. ex: a timer or UART saying “data arrived”  
    * the ZPU finishes its current instruction, pushes the current PC onto the stack (where to resume later), and jumps to 0x020  
    * the code at 0x020 runs jsr \_zpu\_interrupt, which saves R0-R2, calls the C ISR, then restores the R0-R2  
    * ‘poppc’ pops the saved PC, and the interrupted program continues as if nothing happened  
  * C ISR  
    * ISR stands for Interrupt Service Routine:   
      * the function that handles the interrupt ex: reading the received UART byte or clearing the timer flag  
    * C ISR means the handler is written in C rather than assembly.  
    * In crt0.s it’s the function \_zpu\_interrupt (zpu\_interrupt on C side, the compiler adds the leading underscore)  
      * the application programmer supplies this ISR, crt0.S only provides the entry and exit wrapper  
  * R0-R2  
    * the zpu has no general purpose registers, but GCC’s ZPU backend needs a few register-like scratch locations for some operations.   
      * the most important one: a C function’s return value is passed back in R0  
    * these “registers” are just fixed memory words  
      * so they are pseudo-registers  
      * they must be saved because an interrupt can land between any two instructions. suppose th emain program has just called a function and its return is sitting in R0, but it hasn’t read it yet.   
      * an interrupt fires.   
        * the ISR is ordinary compiled C, so it may write R0. when the program resumes the original R0 value is gone.  
        * saving R0-R2 before ISR and restoring them after makes the interrupt invisible to the interrupted code. R3 isn’t saved, presumably on the assumption that GCC rarely uses it.  
  * interrupt masking  
    * masking means to temporarily block interrupts.  
    * the ZPU core has no instruction to disable interrupts.  
      * if software needs to (ex: around a critical section)  
        * it writes to a control register in an external interrupt controller, a memory mapped peripheral  
        * that’s a hardware software interface contract we must define  
    * Built in exception to this  
      * ‘IDIM’  
        * this flag is set during consecutive ‘im’ instructions. while IDIM is set, interrupts are held off.  
        * otherwise an interrupt could land between two halves of a multi-byte constant, corrupting it.  
* 6\. Emulation slots, opcodes 34-63 at 0x040-0x3E0  
  * an unimplemented EMULATE opcode (001x\_xxxx) pushes PC+1 and jumps to (opcode & 0x1F) x 32  
    * each slot is:  
      * .balign 32,0 ; pad to slot boundary with 0x00 (= breakpoint)  
      * \_name: ; entry stack: \[ret, a, b\] a \= orig TOS, b \= orig NOS  
      * …core ops… //hardware implemented operations to do the function of this nonimplemented opcode  
      * storesp  12; storesp 4; poppc ; binary-op ending  
      * ; or : storesp 8; poppc ; unary-op ending  
  * each slot/handler comes in four shapes  
    * inline. fits in 32 bytes. examples sub, eq, neg, xor  
    * trampoline. just ‘jmp’ to .text (longer binaries that are stored in .text, doesn’t fit in 32 bytes)  
    * inline head \+ tail elsewhere; storeh, store, \_storehtail is packed into the unused bytes of \_call’s slot

      * ex: storeb (opcode 52\)  
        * write one byte, ‘val’, to address ‘addr’. the core can only read and write whole 32-bit words, so the handler has to read-modify-write  
          * read the word containing the byte  
          * clear the target byte  
          * shift val into position  
          * OR it in  
          * write the word back  
        * this is more than 32 bytes of code, so its split  
          * head is in the slot 0x20. clears target byte  
            * does the first ‘half’, then   
              * ‘im \_storebtail’ \#push the address of \_storebtail .text instructions  
              * poppc; \#j pops the TOS into PC (PC \= next instruction)  
          * tail \_storebtail in .text: inserts the byte and writes back  
    * C call via cimpl: div, mod  
      * example: div (opcode 53\)  
        * slot at 0x2A0. the whole slot is one macro line  
          * \_div:  
          *         cimpl \_\_divsi3  
        * expanded, its 27 bytes so it fits in the slot with no trampoline  
      * LOOK INTO THIS MORE LATER, SORTA CONFUSED  
  * Opcodes 32 and 33 aren’t usable because their slots collide with reset and interrupt.   
* 7\. .text, overflow code  
  * this is ordinary code with no fixed address; it is only reached by label.  
    * in the final binary, everything in .text sits at one definite address. It means the hardware doesn’t dictate that address; the linker chooses it

|  | Who decides the address | How the PC gets there |
| ----- | ----- | ----- |
| Vector slots | The hardware: `opcode × 32`, `0x000`, `0x020` | The CPU computes it itself, with no label involved |
| `.text` code | The linker, at link time | Software jumps there using a label |

* asdf  
  * How does the program counter find .text code?  
    * every entry into .text is a jump or call from code whose location is known, using the label’s address  
    * the linker takes the actual known address of the .text code and puts it in place of the name of the .text code, like \_storebtail  
* 8 .data, variables  
  * the section for initialized variables  
    * memory locations that start with a known value and can be read/written at runtime  
  * unlike .text, it holds data rather than code  
    * must live in writable RAM  
  * like .text, its address is chosen by the linker and its reached only by label

**Directives used.**

	.data              ; switch to the data section  
	.balign 4,0        ; word-align (4 bytes), pad with 0x00  
\_mask:  
	.long 0x00ffffff   ; .long \= emit one 32-bit word  
	...  
	.globl \_hardware   ; export so C code can access it  
\_hardware:  
	.long 0            ; initial value 0

* asdf  
  * word alignment matters because load and store ignore address bits 1:0. a misaligned table would read the wrong words

#### **`_mask`: byte-clearing table for `storeb`**

| Index k (`addr & 3`) | Value | Clears bits | Which byte |
| ----- | ----- | ----- | ----- |
| 0 | `0x00FFFFFF` | 31:24 | lowest address \= MSB (big-endian) |
| 1 | `0xFF00FFFF` | 23:16 |  |
| 2 | `0xFFFF00FF` | 15:8 |  |
| 3 | `0xFFFFFF00` | 7:0 | highest address \= LSB |

How `storeb` uses it:

im \_mask           ; table base address  
(k \= addr & 3\)  
addsp 0  
addsp 0            ; 4k: byte offset of entry k  
add  
load               ; fetch the mask  
and                ; clear the target byte in the word

The point of the table is speed. Computing the mask directly would need a variable shift, which is an emulated op, so it would trap into another handler. The lookup costs about 5 core instructions and 16 bytes of data. It is not `.globl`, so it's private to crt0.S.

#### **`_hardware`: flag set by emulated `config`**

Initially 0\. The `config` handler (opcode 58\) sets it to 1\. Entry stack is `[ret, id]`:

im 1  
nop                ; separate the two constants  
im \_hardware       ; \[&\_hardware, 1, ret, id\]  
store              ; mem\[&\_hardware\] \= 1 → \[ret, id\]  
storesp 4          ; \[ret\]  (config consumes the ID)  
poppc

So `_hardware` \= 1 means `config` was handled by emulation; if the core implements `config` itself, the handler never runs and `_hardware` stays 0\. My best guess at the intent is distinguishing real cores (which trap) from the Java simulator (which implements every opcode), but I haven't confirmed that. Grep the repo for its uses before relying on it.

#### **`_cpu_config`: CPU ID**

Initially 0\. `_start` writes `ZPU_ID` (a build-time constant identifying the core variant) here at reset, before calling `config`. It's `.globl`, so C code can read it to check which core it's running on.

a note on section flags (“a”, “ax”, “x”, “w”, etc)  
Section flags are metadata that tell the assembler and linker what kind of bytes a section holds:

| Flag | ELF name | Meaning |
| ----- | ----- | ----- |
| `a` | allocatable (`SHF_ALLOC`) | This section occupies memory when the program runs, so give it an address and put it in the final image. |
| `x` | executable (`SHF_EXECINSTR`) | This section contains instructions. |
| `w` | writable (`SHF_WRITE`) | This section is modified at runtime. |

**Why `"a"` must be there.** Without it, the section is *non-allocated*. Debug info and comment sections work like that: they exist in the object file but are never loaded into memory. If `.fixed_vectors` lacked `"a"`, the vector table wouldn't end up in the program image at all. Address 0 would be empty and every trap would jump into nothing. So `"a"` is the bare minimum for the code to exist at runtime.

**Why not `"ax"`.** It originally was `"ax"`; the commented-out line right above it in crt0.S is `.section ".fixed_vectors","ax"`. That's the "correct" description, since the section is code. The authors dropped the `x` only because the ZPU linker uses that flag to decide where to relax `im` sequences. `"a"` alone keeps the section loaded while hiding it from relaxation. That's why the comment calls it a KLUDGE.

**Why it still runs without `"x"`.** The flags only matter to the tools. The ZPU has no MMU and no execute permissions, so the CPU fetches and executes bytes from any address regardless of what the ELF file said about them. Labelling code as "not executable" has no effect at runtime on this core.

No `"w"` either, for the same reason. Nothing enforces it on the ZPU, so it's irrelevant, even though address 0 does get overwritten at runtime by the pseudo-registers.

