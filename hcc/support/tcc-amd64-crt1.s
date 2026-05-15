.text
.global _start
.type _start, @function
_start:
	movq (%rsp), %rdi
	leaq 8(%rsp), %rsi
	call main
	movq %rax, %rdi
	movq $60, %rax
	syscall
