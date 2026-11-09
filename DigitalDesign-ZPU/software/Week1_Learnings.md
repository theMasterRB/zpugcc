# ZPU Toolchain Notes

Notes for the Software Tests&Libraries team to understand how the ZPU works at a glance, also a submittable for week 1 sprint.

---

## 1. What the ZPU is

- The ZPU is a 32-bit CPU designed to use minimal FPGA logic resources; speed is sacrificed for size.
- It is a **stack machine**: no registers included with the processor, this means all values are stored on the stack.
- Opcodes fixed at 8 bits.
- Pretty Simple

## 2. GCC Support Notes

- GCC provides code **generation**: it translates C into a sequence of ZPU instructions, assuming the CPU executes them exactly as specified.
- GCC has no knowledge of whether a specific hardware implementation (the SystemVerilog core another subteam is writing) actually behaves correctly.
- Compiler correctness and hardware correctness are separate concerns. The existence of a working compiler does not verify the hardware; verifying the hardware is the subteam's job.

## 3. Possible issues with ZPU-GCC

- Hard to pinpoint hardware instruction bugs using a compiled C program.
- GCC only generates a narrow, typical subset of possible instruction sequences. It is unlikely to naturally produce many of the sequences that actually expose hardware bugs, for example:
  - Division or modulo operations at overflow boundaries (e.g., `INT_MIN / -1`)
  - Multiple consecutive `IM` instructions, to exercise the IDIM flag under different sequence lengths
  - Byte- or halfword-sized loads/stores adjacent to word-alignment boundaries
  - Interrupts occurring mid-instruction-sequence
- **Per-instruction tests** are going to be our best bet in finding out if any bugs are associated to the underlying hardware causing the ISA contract between the hardware and the compiler to be broken.

## 4. Hardware-implemented vs. emulated instructions

- Only a base subset of ZPU instructions must be implemented directly in hardware (RTL).
- A larger set of instructions (multiply, divide, modulo, shifts, function calls, byte/halfword load-store, etc.) may be implemented either as real hardware or as **emulated instructions**: when the CPU encounters one of these opcodes, it automatically jumps to a software handler (in `crt0.s`) that computes an equivalent result using simpler instructions.
- Which instructions are hardware-implemented versus emulated is a per-core-design decision a smaller core will emulate more instructions to save logic; a larger core will implement more of them directly for speed.
- GCC provides compiler flags (`-mno-mult`, `-mno-div`, `-mno-mod`, `-mno-call`, etc.) to avoid generating a given instruction entirely, for cores that don't support it directly.
- This means the per-instruction test suite has two responsibilities:
  1. Confirm each instruction produces the spec-correct result, whether implemented in hardware or emulated in software.
  2. Confirm the hardware and emulated versions of an instruction (where both exist) produce identical results.


## 5. Glossary

- **Stack machine**  a CPU with no register file; operands and results are held on an in-memory stack.
- **Opcode**  the binary encoding of a single instruction (8 bits on the ZPU).
- **IDIM flag**  internal flag tracking whether a multi-instruction constant is currently being assembled via consecutive `IM` instructions.
- **Emulated instruction**  an instruction implemented as a software routine rather than as dedicated hardware logic.
- **`crt0.s`**  the first code executed at startup; sets up the stack and globals, and on the ZPU also contains emulated-instruction handlers and interrupt vector setup.

---

*Onboarding notes for the SoCET ZPU software/test subteam.*
