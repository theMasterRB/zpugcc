.include "tier0.inc"
BEGIN_TEST

PUSH32 2
PUSH32 3
add
SAVE 0

PUSH32 0
PUSH32 0
add
SAVE 1

PUSH32 0xffffffff
PUSH32 1
add
SAVE 2                         /* unsigned wraparound */

PUSH32 0x7fffffff
PUSH32 1
add
SAVE 3                         /* signed boundary, checked as raw bits */

PUSH32 0x80000000
PUSH32 0x80000000
add
SAVE 4                         /* carry out of bit 31 is discarded */

PUSH32 0xaaaaaaaa
PUSH32 0x55555555
add
SAVE 5

END_TEST
