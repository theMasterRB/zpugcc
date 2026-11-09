#include "zpu_core.h"

// these are the functions systemverilog calls through DPI-C
// if you change anything here, change zpu_dpi_pkg.sv to match
// types: sv int unsigned = unsigned int, sv int = int, sv byte unsigned = unsigned char

Cpu model; // only one model, kept global so the 64 KB array isn't on questa's stack

extern "C" {

void zpu_dpi_reset() {
    reset(model);
}

void zpu_dpi_set_trace(int on) {
    model.trace = (on != 0);
}

// sv loads the program one byte at a time with this
void zpu_dpi_write_byte(unsigned int addr, unsigned char value) {
    if (addr < MEM_SIZE)
        model.memory[addr] = value;
}

// runs one instruction
// returns 1 if it's still running, 0 if it halted, -1 if something broke
int zpu_dpi_step() {
    step(model);
    if (model.error)
        return -1;
    if (model.halted)
        return 0;
    return 1;
}

unsigned int zpu_dpi_get_pc() {
    return model.pc;
}

unsigned int zpu_dpi_get_sp() {
    return model.sp;
}

unsigned int zpu_dpi_get_top() {
    return get_top(model);
}

int zpu_dpi_is_halted() {
    return model.halted;
}

int zpu_dpi_has_error() {
    return model.error;
}

unsigned int zpu_dpi_read32(unsigned int addr) {
    return read32(model, addr);
}

// TODO: load a program from a .bin/.hex file instead of byte by byte
// TODO: let sv see memory writes so we can check them against the rtl

}
