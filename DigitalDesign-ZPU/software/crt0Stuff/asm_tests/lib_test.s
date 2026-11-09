	.file	"lib_test.c"
	.section	.rodata
	.balign 4;
.LC0:
	.string	"Type name: "
	.balign 4;
.LC1:
	.string	"%s"
	.balign 4;
.LC2:
	.string	"Hello, %s"
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
	im .LC0
	storesp 4
	impcrel (printf)
	callpcrel
	im _memreg+12
	load
	im -4
	add
	load
	storesp 8
	im .LC1
	storesp 4
	impcrel (scanf)
	callpcrel
	im _memreg+12
	load
	im -4
	add
	load
	storesp 8
	im .LC2
	storesp 4
	impcrel (printf)
	callpcrel
	im 0
	loadsp 0
	im _memreg+0
	store
	storesp 12
	im 5
	pushspadd
	popsp
	im _memreg+12
	store
	poppc
	.size	main, .-main
	.ident	"GCC: (GNU) 3.4.2"
