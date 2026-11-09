/* Standalone handler tests. Deliberately bypass application/boot startup. */
ENTRY(main)
SECTIONS
{
  .fixed_vectors 0 : { KEEP(*(.fixed_vectors)) }
  ASSERT(SIZEOF(.fixed_vectors) <= 0x400, "vector slots exceed 0x400")
  .runtime 0x400 : { *(.text) }
  ASSERT(. <= 0x1000, "handler bodies overlap result RAM")
  /* Completion/results/scratch retain the Tier 0 addresses. */
  _memreg = 0x1600;
  _zpu_interrupt = 0x20; /* Never called: interrupts are disabled. */
  .test 0x2000 : { *(.text.test) }
  ASSERT(. <= 0x4000, "test code overlaps reserved upper RAM")
  /DISCARD/ : { *(.comment) *(.note*) }
}
