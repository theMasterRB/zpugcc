/* Standalone Tier 0 layout, NOT the application or bootloader memory map.
 * Assumes writable RAM at 0x0000..0x7fff. No emulation vectors are used.
 */
OUTPUT_FORMAT("elf32-zpu")
ENTRY(_start)
MEMORY
{
    RAM (rwx) : ORIGIN = 0, LENGTH = 0x8000
}
SECTIONS
{
    .text 0 : { *(.text*) } > RAM
    /* tools/run.py checks image size; this old linker cannot evaluate ASSERT. */
    .results 0x1000 (NOLOAD) : { . += 0x100; } > RAM
    .scratch 0x1200 (NOLOAD) : { . += 0x400; } > RAM
    .stack 0x7000 (NOLOAD) : { . += 0x1000; } > RAM
}
