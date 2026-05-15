# x86_64 Linux _start: kernel places argc at (%rsp), argv at 8(%rsp).
# Call main(argc, argv), then exit(main's return) via syscall 60.
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
