# x86_64 Linux syscall ABI: nr in %rax, args in %rdi/%rsi/%rdx/%r10/%r8/%r9, `syscall`.
# C ABI passes the 4th arg in %rcx, so 4+-arg syscalls would need %rcx -> %r10.
# All stubs here take <= 3 args, so the C args already sit in %rdi/%rsi/%rdx.
.text

.global read
.type read, @function
read:
	movq $0, %rax
	syscall
	ret

.global write
.type write, @function
write:
	movq $1, %rax
	syscall
	ret

.global open
.type open, @function
open:
	movq $2, %rax
	syscall
	ret

.global close
.type close, @function
close:
	movq $3, %rax
	syscall
	ret

.global lseek
.type lseek, @function
lseek:
	movq $8, %rax
	syscall
	ret

.global brk
.type brk, @function
brk:
	movq $12, %rax
	syscall
	ret

.global access
.type access, @function
access:
	movq $21, %rax
	syscall
	ret

.global _exit
.type _exit, @function
_exit:
	movq $60, %rax
	syscall

.global getcwd
.type getcwd, @function
getcwd:
	movq $79, %rax
	syscall
	ret
