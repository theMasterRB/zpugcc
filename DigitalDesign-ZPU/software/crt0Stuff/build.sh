#!/usr/bin/env bash
# Assemble crt0.S and dump it, then compile every C file in asm_tests/ to assembly.
# Run from the root directory (where crt0.S lives).

set -e

CC=zpu-elf-gcc
OBJDUMP=zpu-elf-objdump

# 1. crt0: assemble, then dump
echo "== crt0.S =="
$CC -c crt0.S -o crt0.o
$OBJDUMP -dr -j .fixed_vectors crt0.o > crt0.dump
$OBJDUMP -t crt0.o > crt0.syms
echo "wrote crt0.o, crt0.dump, crt0.syms"

# 2. C tests: compile each asm_tests/*.c to asm_tests/*.S
echo "== asm_tests =="
shopt -s nullglob
for f in asm_tests/*.c; do
    out="${f%.c}.s"
    $CC -S -O0 "$f" -o "$out"
    echo "$f -> $out"
done
