# AArch64 Linux _start: kernel places argc at [sp], argv at sp+8.
# Load main's address from an inline literal (bl has +-128MB range; an indirect
# branch through x16 avoids needing a PLT in -nostdlib links).
# After main returns, exit(x0) via svc #0 with nr 93 in x8.
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
