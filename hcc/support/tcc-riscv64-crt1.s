.text
.globl _start
.type _start, @function
_start:
	ld a0, 0(sp)
	addi a1, sp, 8
	jal main
	addi a7, zero, 93
	ecall
