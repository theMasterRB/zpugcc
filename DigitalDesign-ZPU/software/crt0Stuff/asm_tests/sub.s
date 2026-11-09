	.file	"sub.c"
.text
	.globl	sub
	.type	sub, @function
sub:
	im _memreg+12
	load
	pushsp
	im _memreg+12
	store
	im 0
	pushspadd
	popsp
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
	sub
	loadsp 0
	im _memreg+0
	store
	storesp 4
	im 2
	pushspadd
	popsp
	im _memreg+12
	store
	poppc
	.size	sub, .-sub
	.ident	"GCC: (GNU) 3.4.2"
