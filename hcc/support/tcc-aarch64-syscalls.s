.text
.global read
.type read, %function
read:
	mov x8, #63
	svc #0
	ret

.global write
.type write, %function
write:
	mov x8, #64
	svc #0
	ret

.global close
.type close, %function
close:
	mov x8, #57
	svc #0
	ret

.global lseek
.type lseek, %function
lseek:
	mov x8, #62
	svc #0
	ret

.global brk
.type brk, %function
brk:
	mov x8, #214
	svc #0
	ret

.global getcwd
.type getcwd, %function
getcwd:
	mov x8, #17
	svc #0
	ret

.global open
.type open, %function
open:
	mov x3, x2
	mov x2, x1
	mov x1, x0
	mov x0, #-100
	mov x8, #56
	svc #0
	ret

.global access
.type access, %function
access:
	mov x2, x1
	mov x1, x0
	mov x0, #-100
	mov x3, #0
	mov x8, #48
	svc #0
	ret

.global _exit
.type _exit, %function
_exit:
	mov x8, #93
	svc #0
