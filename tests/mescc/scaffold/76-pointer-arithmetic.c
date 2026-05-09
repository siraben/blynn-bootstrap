/* -*-comment-start: "//";comment-end:""-*-
 * GNU Mes --- Maxwell Equations of Software
 * Copyright © 2017,2018,2019,2025 Janneke Nieuwenhuizen <janneke@gnu.org>
 * Copyright © 2021 W. J. van der Laan <laanwj@protonmail.com>
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

#include <mes/lib.h>
#include <stdio.h>
#include <string.h>

char *list[2] = { "foo\n", "bar\n" };

struct foo
{
  int a;
  int b;
  int c;
  unsigned char *d;
#if __MESC__ && (__x86_64__ || __riscv_xlen == 64)
  int __align;
#endif
};

int
main ()
{
  char *pc = 0;
  void *pv = 0;
  int *pi = 0;
  char **ppc = 0;
  void **ppv = 0;
  int **ppi = 0;
  size_t int_size = sizeof (int);
  size_t ptr_size = sizeof (void *);
  size_t foo_size = sizeof (struct foo);
  oputs ("int_size:");
  oputs (itoa (int_size));
  oputs ("\n");
  oputs ("ptr_size:");
  oputs (itoa (ptr_size));
  oputs ("\n");
  oputs ("foo_size:");
  oputs (itoa (foo_size));
  oputs ("\n");
  // FIXME: add *14, *18
#if __i386__ || __arm__ || __riscv_xlen == 32
  int foo_size_14 = 224;
  int foo_size_18 = 288;
#elif __x86_64__ || __riscv_xlen == 64
  int foo_size_14 = 336;
  int foo_size_18 = 432;
#endif

  if ((size_t)++pc != 1)
    return 111;
  if ((size_t)++pv != 1)
    return 2;
  if ((size_t)++pi != int_size)
    return 3;
  if ((size_t)++ppc != ptr_size)
    return 4;
  if ((size_t)++ppv != ptr_size)
    return 5;
  if ((size_t)++ppi != ptr_size)
    return 6;
  if ((size_t)(pc + 1) != 2)
    return 7;
  if ((size_t)(pv + 1) != 2)
    return 8;
  if ((size_t)(pi + 1) != int_size << 1)
    return 9;
  if ((size_t)(ppc + 1) != ptr_size << 1)
    return 10;
  if ((size_t)(ppv + 1) != ptr_size << 1)
    return 11;
  if ((size_t)(ppi + 1) != ptr_size << 1)
    return 12;

  char **p = list;
  ++*p;
  eputs (*p);
  if (strcmp (*p, "oo\n"))
    return 13;
  --*p;
  eputs (*p);
  if (strcmp (*p, "foo\n"))
    return 14;

  struct foo *pfoo = 0;
  eputs ("pfoo=");
  eputs (itoa ((size_t)pfoo));
  eputs ("\n");
  pfoo++;
  eputs ("pfoo=");
  eputs (itoa ((size_t)pfoo));
  eputs ("\n");
  if ((size_t)pfoo != foo_size)
    return 15;

  pfoo--;
  eputs ("pfoo=");
  eputs (itoa ((size_t)pfoo));
  eputs ("\n");
  if (pfoo)
    return 16;

  pfoo++;
  eputs ("pfoo=");
  eputs (itoa ((size_t)pfoo));
  eputs ("\n");
  if ((size_t)pfoo != foo_size)
    return 17;

  long one = 1;
  long two = 2;
  pfoo = pfoo - one;
  eputs ("pfoo=");
  eputs (itoa ((size_t)pfoo));
  eputs ("\n");
  if (pfoo)
    return 18;

  pfoo = pfoo + one;
  eputs ("pfoo=");
  eputs (itoa ((size_t)pfoo));
  eputs ("\n");
  if ((size_t)pfoo != foo_size)
    return 19;

  pfoo -= one;
  eputs ("pfoo=");
  eputs (itoa ((size_t)pfoo));
  eputs ("\n");
  if (pfoo)
    return 20;

  pfoo += one;
  eputs ("pfoo=");
  eputs (itoa ((size_t)pfoo));
  eputs ("\n");
  if ((size_t)pfoo != foo_size)
    return 21;

  eputs ("&one: ");
  eputs (itoa ((size_t)&one));
  eputs ("\n");
  eputs ("&two: ");
  eputs (itoa ((size_t)&two));
  eputs ("\n");

  if (&one - 1 != &two)
    return 22;

  struct foo *sym = (void*)(foo_size + foo_size);
  size_t i = (size_t)(sym + 16);
  eputs ("i=");
  eputs (itoa (i));
  eputs ("\n");
  if (i != foo_size_18)
    return 23;

  size_t d = 16;
  i = (size_t)(sym + d);
  eputs ("i=");
  eputs (itoa (i));
  eputs ("\n");
  if (i != foo_size_18)
    return 24;

  i = (size_t)(sym - 16);
  eputs ("i=");
  eputs (itoa (i));
  eputs ("\n");
  if (i != -foo_size_14)
    return 25;

  i = (size_t)(sym - d);
  eputs ("i=");
  eputs (itoa (i));
  eputs ("\n");
  if (i != -foo_size_14)
    return 26;

  i = sym - (struct foo *) foo_size;
  eputs ("i=");
  eputs (itoa (i));
  eputs ("\n");
  if (i != 1)
    return 27;

  pfoo = sym + 1;
#if __GNUC__ // FIXME: No idea how to get this to work with gcc >= 14
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wint-conversion"
#endif
  pfoo -= (struct foo*)sym;
#if __GNUC__
#pragma GCC diagnostic pop
#endif

  eputs ("pfoo=");
  eputs (itoa ((size_t)pfoo));
  eputs ("\n");
  if ((size_t)pfoo != 1)
    return 28;

  return 0;
}
