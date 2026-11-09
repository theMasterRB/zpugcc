	.file	"neqlbranch.c"
.text
	.globl	neql
	.type	neql, @function
neql:
	im _memreg+12
	load
	pushsp
	im _memreg+12
	store
	im -1
	pushspadd
	popsp
	im 0
	nop
	im _memreg+12
	load
	im -4
	add
	store
	im _memreg+12
	load
	im 8
	add
	load
	im _memreg+12
	load
	im 12
	add
	load
	eq
	impcrel .L2
	neqbranch
	im 1
	nop
	im _memreg+12
	load
	im -4
	add
	store
.L2:
	im _memreg+12
	load
	im -4
	add
	load
	loadsp 0
	im _memreg+0
	store
	storesp 4
	im 3
	pushspadd
	popsp
	im _memreg+12
	store
	poppc
	.size	neql, .-neql
	.ident	"GCC: (GNU) 3.4.2"
