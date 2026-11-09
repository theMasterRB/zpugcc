	.file	"var_add.c"
.text
	.globl	main
	.type	main, @function
main:
	im _memreg+12
	load
	pushsp
	im _memreg+12
	store
	im -1
	pushspadd
	popsp
	im 2
	nop
	im _memreg+12
	load
	im -4
	add
	store
	im _memreg+12
	load
	im -4
	add
	load
	im 5
	add
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
	.size	main, .-main
	.ident	"GCC: (GNU) 3.4.2"
