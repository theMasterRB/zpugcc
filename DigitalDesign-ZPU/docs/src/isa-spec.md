# ISA Specification

## Instruction Set

All operations are 32 bits wide.

### Info
- Emulated vs hardware - source: zpu/hdl/zpu4/core/zpu_core.vhd
- Assembly column - (instruction format in assembly) source: zpu/sw/startup/crt0.S

### Required Instruction Set
| Name | Opcode | Description | Assembly | Defintion |
|---|---|---|---|---|
| BREAKPOINT | 0000 0000 | Halt the CPU and/or jump to the debugger. | breakpoint
| IM | 1xxx xxxx | Pushes 7 bit sign extended integer and sets the IDIM flag. IDIM -> instruction decode interrupt mask | IM imm |
| STORESP | 010x xxxx | Pop value off stack and store in SP+xxxxx*4 (aka SP + offset * 4) | storesp offset |
| LOADSP | 011x xxxx | Pushes value (located at SP+xxxxx*4) onto stack | loadsp offset |
| ADDSP | 0001 xxxx | Add value (located at SP+xxxx*4) to top of stack | addsp offset |
| EMULATE | 001x xxxx | Push PC to stack and set PC to 0x0+xxxxx*32. | - | 
| POPPC | 0000 0100 | Pops address off stack and sets PC | poppc
| LOAD | 0000 1000 | Pops address stored on stack and loads the value of that address onto stack. | load
| STORE | 0000 1100 | Pops address, then value from stack and stores the value into the memory location of the address. | store
| PUSHSP | 0000 0010 | Pushes stack pointer. | pushsp
| POPSP | 0000 1101 | Pops value off top of stack and sets SP to that value. | popsp
| ADD | 0000 0101 | Pops 2 values off stack, adds them, and pushes them back onto stack | add
| AND | 0000 0110 | Pops 2 values off the stack, applies a bitwise &, then pushes result to stack | and
| OR | 0000 0111 | Pops 2 values off stack, applies a bitwise or (\|) ,  and pushes result to stack. | or
| NOT | 0000 1001 | Provides the bitwise inverse of value on the stack | not
| FLIP | 0000 1010 | Reverses the bit order of the value on the stack, i.e. abc->cba, 100->001, 110->011, etc. | flip
| NOP | 0000 1011 | No operation | nop
### 

### Recommended Hardware Set
| Name | Opcode | Description | Assembly | Justification |
|---|---|---|---|---|
| PUSHSPADD | 61 | Add stack pointer and popped value, then push result | | |
| POPPCREL | 57 | Set PC to (popped value + current PC) | | |
| SUB | 49 | Pop two values, push the subtracted result | sub | Common operation |
| LOADB | 51 | 8-bit load | | Pretty common to read a byte (ex: char) |
| STOREB | 52 | 8-bit store | | Common to write a byte (ex: char) |
| LESSTHAN | 36 | < (signed comparison) | | Commonly used in conditional statements |
| LESSTHANOREQUAL | 37 | <= (signed comparison)| | Commonly used in conditional statements |
| ULESSTHAN | 38 | < (unsigned comparison)| | Commonly used in conditional statements |
| ULESSTHANOREQUAL | 39 | <= (unsigned comparison) | | Commonly used in conditional statements |
| MULT | 41 | Signed 32-bit multiply | mult | Too many steps in software |
| LSHIFTRIGHT | 42 | Unsigned shift right | lshiftright | |
| CALL | 45 | Call procedure (absolute) - go to the target address | | Function calls occur frequently |
| CALLPCREL | 63 | Call procedure (PC relative) - go to an address that is offsetted relative to curr PC| | Function calls occur frequently |
| EQ | 46 | Equality comparison | eq | Commonly used in conditional statements |

### Recommended Emulated Instruction Set
| Name | Opcode | Description | Assembly | Justification |
|---|---|---|---|---|
| PUSHPC | 59 | Pushes program counter onto the stack | ??? | |
| XOR | 50 | XOR of two popped values | | Can use other gates to build this + less frequently used compared to other gates|
| LOADH | 34 | 16-bit load | | 16 bit loads less common (ex: data type 'short') |
| STOREH | 35 | 16-bit store | | 16 bit stores less common (ex: data type 'short')|
| EQBRANCH | 55 | If top of stack == 0, do not go to the next instruction instead jump to a diff address | | Can use existing comparison/branch instructions|
| NEQBRANCH | 56 | If top of stack != 0, do not go to the next instruction instead jump to a diff address| | Can use existing comparison/branch instructions |
| DIV | 53 | Signed 32-bit divide | | Expensive in hardware |
| MOD | 54 | Signed 32-bit modulo | | Expensive in hardware|
| NEQ | 47 | Inequality comparison | | Can use EQ and NOT instructions |
| NEG | 48 | Negate top of stack | | Can use existing instructions (ex: SUB) |
| ASHIFTLEFT | 43 | Arithmetic (signed) shift left | | |
| ASHIFTRIGHT | 44 | Arithmetic (signed) shift right (error for opcode) | | |

