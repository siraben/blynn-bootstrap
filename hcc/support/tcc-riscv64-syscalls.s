.text
.globl read
.type read, @function
read:
	addi a7, zero, 63
	ecall
	ret

.globl write
.type write, @function
write:
	addi a7, zero, 64
	ecall
	ret

.globl close
.type close, @function
close:
	addi a7, zero, 57
	ecall
	ret

.globl lseek
.type lseek, @function
lseek:
	addi a7, zero, 62
	ecall
	ret

.globl brk
.type brk, @function
brk:
	addi a7, zero, 214
	ecall
	ret

.globl getcwd
.type getcwd, @function
getcwd:
	addi a7, zero, 17
	ecall
	ret

.globl open
.type open, @function
open:
	mv a3, a2
	mv a2, a1
	mv a1, a0
	addi a0, zero, -100
	addi a7, zero, 56
	ecall
	ret

.globl access
.type access, @function
access:
	mv a2, a1
	mv a1, a0
	addi a0, zero, -100
	addi a3, zero, 0
	addi a7, zero, 48
	ecall
	ret

.globl _exit
.type _exit, @function
_exit:
	addi a7, zero, 93
	ecall

.globl mprotect
.type mprotect, @function
mprotect:
	addi a7, zero, 226
	ecall
	ret

.globl __builtin_va_start
.type __builtin_va_start, @function
__builtin_va_start:
	ret

.globl __builtin_va_arg
.type __builtin_va_arg, @function
__builtin_va_arg:
	addi a0, zero, 0
	ret

.globl __builtin_va_copy
.type __builtin_va_copy, @function
__builtin_va_copy:
	ret

.globl __builtin_va_end
.type __builtin_va_end, @function
__builtin_va_end:
	ret
