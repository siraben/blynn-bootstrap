/* -*-comment-start: "//";comment-end:""-*-
 * GNU Mes --- Maxwell Equations of Software
 * Copyright © 2023 Andrius Štikonas <andrius@stikonas.eu>
 * Copyright © 2023 Janneke Nieuwenhuizen <janneke@gnu.org>
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

#include <mes/lib.h>

int
main ()
{
  int a = 0x1001;
  eputs ("a=");
  eputs (ntoab (a, 16, 1));
  eputs ("\n");

#if __riscv
  asm ("#//b = a << 20;");
#else
  asm (";;//b = a << 20;");
#endif
  int b = a << 20;
#if __riscv
  asm ("#//print b;");
#else
  asm (";;//print b;");
#endif
  eputs ("b=");
  eputs (ntoab (b, 16, 1));
  eputs ("\n");
  if (b != 0x100000)
    return 1;

#if __riscv
  asm ("#//c = b >> 20;");
#else
  asm (";;//c = b >> 20;");
#endif
  int c = b >> 20;;
#if __riscv
  asm ("#//print c;");
#else
  asm (";;//print c;");
#endif
  eputs ("c=");
  eputs (ntoab (c, 16, 1));
  eputs ("\n");
  if (c != 1)
    return 2;

#if __riscv
  asm ("#//x = a << 20 >> 20;");
#else
  asm (";;//x = a << 20 >> 20;");
#endif
  int x = a << 20 >> 20;
  // printf ("x=%d\n", x);

#if __riscv
  asm ("#//print x;");
#else
  asm (";;//print x;");
#endif
  eputs ("x=");
  eputs (ntoab (x, 16, 1));
  eputs ("\n");
  if (x != 1)
    return 3;

  return 0;
}
