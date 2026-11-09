	.file	"basic_func.c"
	.globl	__mulsi3
.text
	.globl	square
	.type	square, @function
square:
	im _memreg+12
	load
	pushsp
	im _memreg+12
	store
	im -2
	pushspadd
	popsp
	im _memreg+12
	load
	im 8
	add
	load
	im _memreg+12
	load
	im 8
	add
	load
	mult
	loadsp 0
	im _memreg+0
	store
	storesp 12
	im 4
	pushspadd
	popsp
	im _memreg+12
	store
	poppc
	.size	square, .-square
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
	storesp 4
	impcrel (square)
	callpcrel
	im _memreg+0
	load
	loadsp 0
	im _memreg+12
	load
	im -8
	add
	store
	im _memreg+12
	load
	im -8
	add
	load
	loadsp 0
	im _memreg+0
	store
	storesp 4
	storesp 8
	im 5
	pushspadd
	popsp
	im _memreg+12
	store
	poppc
	.size	main, .-main
	.ident	"GCC: (GNU) 3.4.2"
