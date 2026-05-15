# RISC-V64 Linux _start: kernel places argc at 0(sp), argv at sp+8.
# Call main(argc, argv), then exit(a0) via ecall with nr 93 in a7.
.text
.globl _start
.type _start, @function
_start:
	ld a0, 0(sp)
	addi a1, sp, 8
	jal main
	addi a7, zero, 93
	ecall
