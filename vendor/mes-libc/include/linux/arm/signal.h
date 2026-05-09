/* -*-comment-start: "//";comment-end:""-*-
 * GNU Mes --- Maxwell Equations of Software
 * Copyright © 2024 Ekaitz Zarraga <ekaitz@elenq.tech>
 * Copyright © 2024 Janneke Nieuwenhuizen <janneke@gnu.org>
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

typedef int greg_t;
typedef int gregset_t[18];
typedef struct sigcontext
{
  unsigned long trap_no, error_code, oldmask;
  unsigned long arm_r0, arm_r1, arm_r2, arm_r3;
  unsigned long arm_r4, arm_r5, arm_r6, arm_r7;
  unsigned long arm_r8, arm_r9, arm_r10, arm_fp;
  unsigned long arm_ip, arm_sp, arm_lr, arm_pc;
  unsigned long arm_cpsr, fault_address;
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
  unsigned long long uc_regspace[64];
} ucontext_t;
