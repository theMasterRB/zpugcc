#include <cstdio>
#include "zpu_core.h"

// standalone version of the simulator, same thing simulator.cpp used to do
// build: g++ -std=c++11 -o zpusim zpu_core.cpp zpusim_main.cpp

// ---------------------------------------------------------------
// main
// ---------------------------------------------------------------
Cpu cpu; // global so the 64 KB array isn't on the program's own stack

int main() {
    reset(cpu);
    cpu.trace = true;

    // Test program: 3 + 4
    uint8_t program[] = {
        128 + 3, // IM 3
        NOP, // breaks the IM chain so the next IM pushes a new value
        128 + 4, // IM 4
        ADD,
        BREAKPOINT,
    };

    int program_size = sizeof(program);
    for (int i = 0; i < program_size; i++)
        cpu.memory[i] = program[i];

    while (!cpu.halted)
        step(cpu);

    if (cpu.error)
        return 1;

    printf("Result: %d\n", (int32_t)get_top(cpu));
    return 0;
}