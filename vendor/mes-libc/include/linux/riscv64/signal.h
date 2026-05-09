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

// Taken from musl libc (4a16ddf5)

#define REG_PC 0
#define REG_RA 1
#define REG_SP 2
#define REG_TP 4
#define REG_S0 8
#define REG_A0 10

typedef unsigned long __riscv_mc_gp_state[32];

struct __riscv_mc_f_ext_state
{
  unsigned int __f[32];
  unsigned int __fcsr;
};

struct __riscv_mc_d_ext_state
{
  unsigned long long __f[32];
  unsigned int __fcsr;
};

struct __riscv_mc_q_ext_state
{
  unsigned long long __f[64]; //  __attribute__((aligned(16)))
  unsigned int __fcsr;
  unsigned int __reserved[3];
};

union __riscv_mc_fp_state
{
  struct __riscv_mc_f_ext_state __f;
  struct __riscv_mc_d_ext_state __d;
  struct __riscv_mc_q_ext_state __q;
};

typedef struct mcontext_t
{
  __riscv_mc_gp_state __gregs;
  union __riscv_mc_fp_state __fpregs;
} mcontext_t;

typedef unsigned long greg_t;
typedef unsigned long gregset_t[32];
typedef union __riscv_mc_fp_state fpregset_t;

struct sigcontext
{
  gregset_t gregs;
  fpregset_t fpregs;
};

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
  sigset_t uc_sigmask;
  mcontext_t uc_mcontext;
} ucontext_t;
