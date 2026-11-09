.include "tier0.inc"
BEGIN_TEST

/* Explicit opcode bytes isolate IM from the assembler's FLIP optimization. */
.byte 0x80                     /* 7-bit zero */
SAVE 0
.byte 0xff                     /* sign-extended -1 */
SAVE 1
.byte 0xbf                     /* largest positive single-byte value: 63 */
SAVE 2
.byte 0xc0                     /* smallest negative single-byte value: -64 */
SAVE 3
.byte 0x80, 0xc0               /* 0 followed by chunk 64: +64 */
SAVE 4
.byte 0xff, 0xbf               /* (-1 << 7) | 63: -65 */
SAVE 5
.byte 0x81, 0x82, 0x83         /* (1 << 14) | (2 << 7) | 3 */
SAVE 6

/* NOP must end chaining: these must be TWO stack values, not 130. */
.byte 0x81
nop
.byte 0x82
SAVE 7                         /* pop the 2 */
SAVE 8                         /* the 1 must still be beneath it */

END_TEST
