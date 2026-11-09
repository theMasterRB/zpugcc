	.file	"lessthan.c"
.text
	.globl	lessthan
	.type	lessthan, @function
lessthan:
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
	lessthanorequal
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
	.size	lessthan, .-lessthan
	.globl	lessthanorequal
	.type	lessthanorequal, @function
lessthanorequal:
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
	lessthan
	impcrel .L4
	neqbranch
	im 1
	nop
	im _memreg+12
	load
	im -4
	add
	store
.L4:
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
	.size	lessthanorequal, .-lessthanorequal
	.globl	ulessthan
	.type	ulessthan, @function
ulessthan:
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
	ulessthanorequal
	impcrel .L6
	neqbranch
	im 1
	nop
	im _memreg+12
	load
	im -4
	add
	store
.L6:
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
	.size	ulessthan, .-ulessthan
	.ident	"GCC: (GNU) 3.4.2"
