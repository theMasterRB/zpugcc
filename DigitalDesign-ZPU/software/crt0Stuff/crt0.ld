/*
 * ZPU memory map skeleton for crt0.S.
 * Every line marked TODO is a placeholder that needs a real value from the core team.
 * Not yet run through zpu-elf-ld.
 */

ENTRY(_start)

MEMORY
{
    /* TODO: base address and size of the unified code+data memory */
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x8000
}

/* TODO: base of the IO region (UART, timer, ...). The core's address bus has an extra
 * bit that selects IO space; get the exact address from the core team. */
_io_base = 0x80000000;

SECTIONS
{
    /* Must be first and must start at 0: EMULATE jumps to (opcode - 32) * 32 */
    .fixed_vectors 0x0 : { KEEP(*(.fixed_vectors)) } > RAM

    .text : { *(.text) *(.text.*) } > RAM
    .rodata : { *(.rodata) *(.rodata.*) } > RAM

    .data : { _data_start = .; *(.data) *(.data.*) _data_end = .; } > RAM

    .bss : { _bss_start = .; *(.bss) *(.bss.*) *(COMMON) _bss_end = .; } > RAM

    /* Memory registers used by compiled code (_memreg+0, +4, +8, +12 ...).
     * TODO: check how the toolchain's default script defines _memreg
     *       (zpu-elf-ld --verbose | grep -i memreg) and match it. */
    . = ALIGN(16);
    _memreg = .;
    . += 32;

    /* TODO: heap for malloc / _sbrk, if stdio or malloc will be used */
    _heap_start = .;

    /* TODO: initial SP. Check whether the hardware sets it at reset, and to what. */
}
