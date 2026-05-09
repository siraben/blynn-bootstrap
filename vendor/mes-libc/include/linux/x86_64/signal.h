/* -*-comment-start: "//";comment-end:""-*-
 * GNU Mes --- Maxwell Equations of Software
 * Copyright © 2024 Ekaitz Zarraga <ekaitz@elenq.tech>
 *
 * This file is part of GNU Mes.
 *
 * GNU Mes is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or (at
 * your option) any later version.
 *
 * GNU Mes is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with GNU Mes.  If not, see <http://www.gnu.org/licenses/>.
 */

// Taken from musl libc (4a16ddf5) and simplified

#define REG_R8          0
#define REG_R9          1
#define REG_R10         2
#define REG_R11         3
#define REG_R12         4
#define REG_R13         5
#define REG_R14         6
#define REG_R15         7
#define REG_RDI         8
#define REG_RSI         9
#define REG_RBP         10
#define REG_RBX         11
#define REG_RDX         12
#define REG_RAX         13
#define REG_RCX         14
#define REG_RSP         15
#define REG_RIP         16
#define REG_EFL         17
#define REG_CSGSFS      18
#define REG_ERR         19
#define REG_TRAPNO      20
#define REG_OLDMASK     21
#define REG_CR2         22

typedef long long greg_t;
typedef long long gregset_t[23];

struct __st
{
  unsigned short significand[4], exponent, padding[3];
};

struct _xmm
{
  unsigned element[4];
};

typedef struct _fpstate
{
  unsigned short cwd, swd, ftw, fop;
  unsigned long long rip, rdp;
  unsigned mxcsr, mxcr_mask;
  struct __st _st[8];
  struct _xmm _xmm[16];
  unsigned padding[24];
} *fpregset_t;

struct sigcontext
{
  unsigned long r8, r9, r10, r11, r12, r13, r14, r15;
  unsigned long rdi, rsi, rbp, rbx, rdx, rax, rcx, rsp, rip, eflags;
  unsigned short cs, gs, fs, __pad0;
  unsigned long err, trapno, oldmask, cr2;
  struct _fpstate *fpstate;
  unsigned long __reserved1[8];
};

typedef struct
{
  gregset_t gregs;
  fpregset_t fpregs;
  unsigned long long __reserved1[8];
} mcontext_t;

struct sigaltstack
{
  void *ss_sp;
  int ss_flags;
  size_t ss_size;
};

typedef struct __ucontext
{
  unsigned long uc_flags;
  struct __ucontext *uc_link;
  stack_t uc_stack;
  mcontext_t uc_mcontext;
  sigset_t uc_sigmask;
  unsigned long __fpregs_mem[64];
} ucontext_t;
