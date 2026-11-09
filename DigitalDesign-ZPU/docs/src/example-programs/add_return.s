	.file	"add_return.c"
.text
	.globl	main
	.type	main, @function
main:
	im _memreg+12
	load
	pushsp
	im _memreg+12
	store
	im 0
	pushspadd
	popsp
	im 3
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
	.size	main, .-main
	.ident	"GCC: (GNU) 3.4.2"
