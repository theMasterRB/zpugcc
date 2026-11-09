.include "tier0.inc"
BEGIN_TEST

/* STORE takes address from TOS, value from NOS: value goes first. */
PUSH32 0x13579bdf
PUSH32 SCRATCH
store
PUSH32 0
PUSH32 (SCRATCH + 4)
store
PUSH32 0x2468ace0
PUSH32 (SCRATCH + 8)
store

/* Overwrite the middle word, then check it and both neighbors. */
PUSH32 0x89abcdef
PUSH32 (SCRATCH + 4)
store

PUSH32 SCRATCH
load
SAVE 0
PUSH32 (SCRATCH + 4)
load
SAVE 1
PUSH32 (SCRATCH + 8)
load
SAVE 2

PUSH32 0
PUSH32 (SCRATCH + 4)
store
PUSH32 (SCRATCH + 4)
load
SAVE 3

PUSH32 0xffffffff
PUSH32 (SCRATCH + 4)
store
PUSH32 (SCRATCH + 4)
load
SAVE 4

END_TEST
