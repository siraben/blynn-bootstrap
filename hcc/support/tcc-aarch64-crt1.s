.text
.global _start
.type _start, %function
_start:
	ldr x0, [sp]
	add x1, sp, #8
	ldr x16, 1f
	b 2f
1:
	.xword main
2:
	blr x16
	mov x8, #93
	svc #0
