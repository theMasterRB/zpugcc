// Execution/export adapter. Instruction semantics come only from zpu_core.cpp.
#include "zpu_core.h"
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

static Cpu cpu;
static const uint32_t ram_bytes = 32768;

static uint32_t peek(uint32_t address) {
    if (address > ram_bytes - 4) return 0;
    return (uint32_t(cpu.memory[address]) << 24)
         | (uint32_t(cpu.memory[address + 1]) << 16)
         | (uint32_t(cpu.memory[address + 2]) << 8)
         | uint32_t(cpu.memory[address + 3]);
}

int main(int argc, char **argv) {
    if (argc != 5) return 2;
    std::ifstream input(argv[1], std::ios::binary);
    if (!input) return 2;
    std::vector<unsigned char> image((std::istreambuf_iterator<char>(input)), {});
    if (image.empty() || image.size() > ram_bytes) return 2;
    const std::string directory(argv[2]);
    char *end = nullptr;
    const unsigned long long budget = std::strtoull(argv[3], &end, 10);
    if (!end || *end || !budget) return 2;
    const unsigned long entry = std::strtoul(argv[4], &end, 0);
    if (!end || *end || entry >= image.size()) return 2;
    FILE *trace = std::fopen((directory + "/trace.txt").c_str(), "w");
    if (!trace) return 2;
    reset(cpu);
    cpu.trace = false;
    cpu.pc = entry;
    cpu.sp = 0x7ff8; // Shared standalone contract; core reset defaults to 64 KiB.
    for (size_t i = 0; i < image.size(); ++i) cpu.memory[i] = image[i];
    std::fprintf(trace, "# PC OPCODE SP TOS NOS; pre-execution\n");
    unsigned long long count = 0;
    std::string outcome = "TIMEOUT";
    while (!cpu.halted && count < budget) {
        if (cpu.pc >= ram_bytes || cpu.sp > ram_bytes - 4 || cpu.sp % 4) {
            outcome = "FAULT";
            break;
        }
        std::fprintf(trace, "%08x %02x %08x %08x %08x\n", cpu.pc,
                     cpu.memory[cpu.pc], cpu.sp, peek(cpu.sp), peek(cpu.sp + 4));
        ++count;
        step(cpu);
    }
    if (cpu.error) outcome = "FAULT";
    else if (cpu.halted) outcome = "HALT";
    std::fclose(trace);
    FILE *dump = std::fopen((directory + "/dump.hex").c_str(), "w");
    FILE *status = std::fopen((directory + "/status.txt").c_str(), "w");
    if (!dump || !status) return 2;
    for (uint32_t address = 0; address < ram_bytes; address += 4)
        std::fprintf(dump, "%08x\n", peek(address));
    std::fprintf(status, "%s instructions=%llu\n", outcome.c_str(), count);
    std::printf("%s instructions=%llu\n", outcome.c_str(), count);
    std::fclose(dump);
    std::fclose(status);
    return 0; // The Python checker judges execution status separately.
}
