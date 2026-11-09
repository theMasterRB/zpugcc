#include <cstdio>
#include <cstdint>
#include <cstdlib>

const int MEM_SIZE  = 65536;//64kb memory
const int SIZE = 4;//stack entry is 32 bits which is 4 bytes

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
    uint8_t memory[MEM_SIZE];   // program + stack live here
    uint32_t pc; // address of next instruction
    uint32_t sp; // address of top of stack
    bool idim; // was the last instruction an IM?
    bool halted;
};

void reset(Cpu &cpu) {
    for (int i = 0; i < MEM_SIZE; i++)
        cpu.memory[i] = 0;
    cpu.pc = 0;
    cpu.sp = MEM_SIZE - 8; // start near the top of memory
    cpu.idim = false;
    cpu.halted = false;
}

//memory
//read/write one 32-bit word as 4 bytes, big-endian - the biggest byte is stored first at the lowest address
void check_addr(uint32_t addr) {
    if (addr + 3 >= MEM_SIZE) {
        printf("ERROR: bad address %u\n", addr);
        exit(1);
    }
}

uint32_t read32(Cpu &cpu, uint32_t addr) {
    check_addr(addr);
    uint32_t byte0 = cpu.memory[addr]; // biggest byte
    uint32_t byte1 = cpu.memory[addr + 1];
    uint32_t byte2 = cpu.memory[addr + 2];
    uint32_t byte3 = cpu.memory[addr + 3]; // smallest byte
    return byte0 * 16777216 + byte1 * 65536 + byte2 * 256 + byte3;
}

void write32(Cpu &cpu, uint32_t addr, uint32_t value) {
    check_addr(addr);
    cpu.memory[addr] = (value / 16777216) % 256;   // biggest byte
    cpu.memory[addr + 1] = (value / 65536) % 256;
    cpu.memory[addr + 2] = (value / 256) % 256;
    cpu.memory[addr + 3] = value % 256; // smallest byte
}

//stack that grows down
void push(Cpu &cpu, uint32_t value) {
    cpu.sp = cpu.sp - SIZE;
    write32(cpu, cpu.sp, value);
}

uint32_t pop(Cpu &cpu) {
    uint32_t value = read32(cpu, cpu.sp);
    cpu.sp = cpu.sp + SIZE;
    return value;
}

uint32_t get_top(Cpu &cpu) {
    return read32(cpu, cpu.sp);

}
void set_top(Cpu &cpu, uint32_t value) {
    write32(cpu, cpu.sp, value);
}


void step(Cpu &cpu) {
    uint32_t this_pc = cpu.pc;
    int op = cpu.memory[this_pc]; // fetch the 1-byte opcode (0 to 255)
    cpu.pc = this_pc + 1; // by default go to the next byte

    bool last_was_im = cpu.idim;
    cpu.idim = false;

    // ----- IM x: opcodes 128 to 255 -----------------------------
    if (op >= 128) {
        uint32_t x = op - 128;             // 0 to 127
        if (last_was_im) {
            // Glue 7 more bits onto the bottom: multiply by 128, add x
            uint32_t top = get_top(cpu);
            set_top(cpu, top * 128 + x);
        } else {
            // 7-bit signed number: 0..63 positive, 64..127 means -64..-1
            int32_t value = x;
            if (x >= 64) value = x - 128;
            push(cpu, value);
        }
        cpu.idim = true;
    }
    // ----- LOADSP x: opcodes 96 to 127 --------------------------
    else if (op >= 96) {
        uint32_t x = op - 96;              // 0 to 31
        uint32_t slot = x ^ 16;            // ZPU quirk: flip bit 4
        uint32_t address = cpu.sp + slot * SIZE;
        uint32_t value = read32(cpu, address);
        push(cpu, value);
    }
    // ----- STORESP x: opcodes 64 to 95 --------------------------
    else if (op >= 64) {
        uint32_t x = op - 64;              // 0 to 31
        uint32_t slot = x ^ 16;            // ZPU quirk: flip bit 4
        uint32_t address = cpu.sp + slot * SIZE;
        uint32_t value = pop(cpu);
        write32(cpu, address, value);
    }
    // ----- EMULATE x: opcodes 32 to 63 --------------------------
    else if (op >= 32) {
        uint32_t x = op - 32;              // 0 to 31
        uint32_t return_address = cpu.pc;
        push(cpu, return_address);
        cpu.pc = x * 32;                   // jump to the software handler
    }
    // ----- ADDSP x: opcodes 16 to 31 ----------------------------
    else if (op >= 16) {
        uint32_t x = op - 16;              // 0 to 15
        uint32_t address = cpu.sp + x * SIZE;
        uint32_t top = get_top(cpu);
        uint32_t other = read32(cpu, address);
        set_top(cpu, top + other);
    }
    // ----- Fixed instructions: opcodes 0 to 15 ------------------
    else {
        switch (op) {
        case BREAKPOINT: {
            cpu.halted = true;
            break;
        }
        case PUSHSP: {
            uint32_t old_sp = cpu.sp;
            push(cpu, old_sp);
            break;
        }
        case POPPC: {
            uint32_t target = pop(cpu);
            cpu.pc = target;
            break;
        }
        case ADD: {
            uint32_t a = pop(cpu);
            uint32_t b = pop(cpu);
            push(cpu, a + b);
            break;
        }
        case AND: {
            uint32_t a = pop(cpu);
            uint32_t b = pop(cpu);
            push(cpu, a & b);
            break;
        }
        case OR: {
            uint32_t a = pop(cpu);
            uint32_t b = pop(cpu);
            push(cpu, a | b);
            break;
        }
        case LOAD: {
            uint32_t address = get_top(cpu);
            uint32_t value = read32(cpu, address);
            set_top(cpu, value);
            break;
        }
        case NOT: {
            uint32_t top = get_top(cpu);
            set_top(cpu, ~top);
            break;
        }
        case FLIP: {
            uint32_t top = get_top(cpu);
            uint32_t result = 0;
            for (int i = 0; i < 32; i++) {
                uint32_t bit = (top >> i) & 1;     // bit i of the input
                result = result | (bit << (31 - i)); // goes to bit 31 - i
            }
            set_top(cpu, result);
            break;
        }
        case NOP: {
            break;
        }
        case STORE: {
            uint32_t address = pop(cpu);
            uint32_t value = pop(cpu);
            write32(cpu, address, value);
            break;
        }
        case POPSP: {
            uint32_t new_sp = get_top(cpu);
            cpu.sp = new_sp;
            break;
        }
        default: {
            printf("ERROR: unknown opcode %d at pc %u\n", op, this_pc);
            exit(1);
        }
        }
    }

    printf("pc=%-5u  op=%-3d  sp=%-5u  top=%d\n",
           this_pc, op, cpu.sp, (int32_t)get_top(cpu));
}

// ---------------------------------------------------------------
// main
// ---------------------------------------------------------------
Cpu cpu;   // global so the 64 KB array isn't on the program's own stack

int main() {
    reset(cpu);

    // Test program: 3 + 4
    uint8_t program[] = {
        128 + 3,   // IM 3
        NOP,       // breaks the IM chain so the next IM pushes a new value
        128 + 4,   // IM 4
        ADD,
        BREAKPOINT,
    };

    int program_size = sizeof(program);
    for (int i = 0; i < program_size; i++)
        cpu.memory[i] = program[i];

    while (!cpu.halted)
        step(cpu);

    printf("Result: %d\n", (int32_t)get_top(cpu));
    return 0;
}
