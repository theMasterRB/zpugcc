	.file	"functions.c"
.text
	.globl	add
	.type	add, @function
add:
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
	add
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
	.size	add, .-add
	.globl	__mulsi3
	.globl	mul
	.type	mul, @function
mul:
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
	im 12
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
	.size	mul, .-mul
	.globl	__divsi3
	.globl	div
	.type	div, @function
div:
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
	im 12
	add
	load
	im _memreg+12
	load
	im 8
	add
	load
	div
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
	.size	div, .-div
	.globl	__divdf3
	.globl	ddiv
	.type	ddiv, @function
ddiv:
	im _memreg+12
	load
	pushsp
	im _memreg+12
	store
	im -10
	pushspadd
	popsp
	im _memreg+12
	load
	im 8
	add
	load
	im _memreg+12
	load
	im -8
	add
	storesp 36
	storesp 36
	im _memreg+12
	load
	im 20
	add
	load
	im _memreg+12
	load
	im 24
	add
	load
	storesp 32
	storesp 24
	loadsp 20
	storesp 16
	loadsp 24
	storesp 20
	im _memreg+12
	load
	im 12
	add
	load
	im _memreg+12
	load
	im 16
	add
	load
	storesp 32
	storesp 24
	loadsp 20
	storesp 8
	loadsp 24
	storesp 12
	loadsp 28
	storesp 4
	impcrel (__divdf3)
	callpcrel
	im _memreg+12
	load
	im -8
	add
	load
	im _memreg+12
	load
	im -4
	add
	load
	storesp 32
	storesp 24
	loadsp 20
	loadsp 36
	store
	loadsp 24
	im 4
	addsp 40
	store
	loadsp 32
	im _memreg+0
	store
	im 12
	pushspadd
	popsp
	im _memreg+12
	store
	poppc
	.size	ddiv, .-ddiv
	.globl	__floatsidf
	.globl	__fixdfsi
	.globl	main
	.type	main, @function
main:
	im _memreg+12
	load
	pushsp
	im _memreg+12
	store
	im -19
	pushspadd
	popsp
	im 5
	nop
	im _memreg+12
	load
	im -4
	add
	store
	im 6
	nop
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
	storesp 8
	im _memreg+12
	load
	im -4
	add
	load
	storesp 4
	impcrel (add)
	callpcrel
	im _memreg+0
	load
	loadsp 0
	im _memreg+12
	load
	im -12
	add
	store
	im _memreg+12
	load
	im -8
	add
	load
	storesp 12
	im _memreg+12
	load
	im -4
	add
	load
	storesp 8
	storesp 24
	impcrel (mul)
	callpcrel
	im _memreg+0
	load
	loadsp 0
	im _memreg+12
	load
	im -16
	add
	store
	im _memreg+12
	load
	im -8
	add
	load
	storesp 12
	im _memreg+12
	load
	im -4
	add
	load
	storesp 8
	storesp 24
	impcrel (div)
	callpcrel
	im _memreg+0
	load
	loadsp 0
	im _memreg+12
	load
	im -20
	add
	store
	im _memreg+12
	load
	im -28
	add
	im _memreg+12
	load
	im -36
	add
	im _memreg+12
	load
	im -8
	add
	load
	storesp 20
	loadsp 0
	storesp 16
	storesp 8
	storesp 36
	storesp 24
	impcrel (__floatsidf)
	callpcrel
	im _memreg+12
	load
	im -36
	add
	load
	im _memreg+12
	load
	im -32
	add
	load
	storesp 32
	storesp 24
	loadsp 20
	storesp 16
	loadsp 24
	storesp 20
	im _memreg+12
	load
	im -36
	add
	im _memreg+12
	load
	im -4
	add
	load
	storesp 12
	loadsp 0
	storesp 8
	storesp 24
	impcrel (__floatsidf)
	callpcrel
	im _memreg+12
	load
	im -36
	add
	load
	im _memreg+12
	load
	im -32
	add
	load
	storesp 32
	storesp 24
	loadsp 20
	storesp 8
	loadsp 24
	storesp 12
	loadsp 28
	storesp 4
	impcrel (ddiv)
	callpcrel
	im _memreg+12
	load
	im -44
	add
	im _memreg+12
	load
	im -4
	add
	load
	storesp 12
	loadsp 0
	storesp 8
	storesp 24
	impcrel (__floatsidf)
	callpcrel
	im _memreg+12
	load
	im -44
	add
	load
	im _memreg+12
	load
	im -40
	add
	load
	storesp 32
	storesp 24
	loadsp 20
	im _memreg+12
	load
	im -36
	add
	store
	loadsp 24
	im _memreg+12
	load
	im -32
	add
	store
	im _memreg+12
	load
	im -28
	add
	load
	im _memreg+12
	load
	im -24
	add
	load
	storesp 32
	storesp 24
	loadsp 20
	storesp 4
	loadsp 24
	storesp 8
	impcrel (__fixdfsi)
	callpcrel
	im _memreg+0
	load
	loadsp 0
	im _memreg+12
	load
	im -48
	add
	store
	storesp 24
	loadsp 20
	im _memreg+0
	store
	im 21
	pushspadd
	popsp
	im _memreg+12
	store
	poppc
	.size	main, .-main
	.ident	"GCC: (GNU) 3.4.2"
