	.file	"double_num.c"
.text
	.globl	main
	.type	main, @function
main:
	im _memreg+12
	load
	pushsp
	im _memreg+12
	store
	im -3
	pushspadd
	popsp
	im 1074003968
	storesp 4
	im 0
	storesp 8
	loadsp 0
	im _memreg+12
	load
	im -8
	add
	store
	loadsp 4
	im _memreg+12
	load
	im -4
	add
	store
	im 1
	loadsp 0
	im _memreg+0
	store
	storesp 4
	im 5
	pushspadd
	popsp
	im _memreg+12
	store
	poppc
	.size	main, .-main
	.ident	"GCC: (GNU) 3.4.2"
