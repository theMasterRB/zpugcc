#ifndef ZPU_CORE_H
#define ZPU_CORE_H

#include <cstdint>

// shared by the normal simulator (zpusim_main.cpp) and the DPI wrapper (zpu_dpi.cpp)

const int MEM_SIZE = 65536; //64kb memory
const int SIZE = 4; //stack entry is 32 bits which is 4 bytes

// Opcode numbers for the fixed instructions
const int BREAKPOINT = 0;
const int PUSHSP = 2;
const int POPPC = 4;
const int ADD = 5;
const int AND = 6;
const int OR = 7;
const int LOAD = 8;
const int NOT = 9;
const int FLIP = 10;
const int NOP = 11;
const int STORE = 12;
const int POPSP = 13;

//cpu state
struct Cpu {
    uint8_t memory[MEM_SIZE]; // program + stack live here
    uint32_t pc; // address of next instruction
    uint32_t sp; // address of top of stack
    bool idim; // was the last instruction an IM?
    bool halted;
    bool error; // set if something went wrong so we stop instead of crashing
    bool trace; // print a line after every instruction
};

void reset(Cpu &cpu);
void step(Cpu &cpu);

uint32_t read32(Cpu &cpu, uint32_t addr);
void write32(Cpu &cpu, uint32_t addr, uint32_t value);
uint32_t get_top(Cpu &cpu);

#endif