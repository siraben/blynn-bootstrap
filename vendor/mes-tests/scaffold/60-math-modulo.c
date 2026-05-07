/* -*-comment-start: "//";comment-end:""-*-
 * GNU Mes --- Maxwell Equations of Software
 * Copyright © 2022 Jan (janneke) Nieuwenhuizen <janneke@gnu.org>
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

#include <limits.h>
#include <stdio.h>
#include <string.h>

#include <mes/lib.h>

int
main ()
{
  int i;

  oputs ("\n");

  oputs ("t: 1 % 2\n");
  i = 1 % 2;
  if (i != 1)
    return 1;

  oputs ("t: 2 % 4\n");
  i = 2 % 4;
  if (i != 2)
    return 2;

  oputs ("t: 3 % 4\n");
  i = 3 % 4;
  if (i != 3)
    return 3;

  oputs ("t: 1 % 256\n");
  i = 1 % 256;
  if (i != 1)
    return 4;

  unsigned u;

  oputs ("\n");

  oputs ("t: 1U % 2\n");
  u = 1 % 2;
  if (u != 1)
    return 5;

  oputs ("t: 2U % 4\n");
  u = 2 % 4;
  if (u != 2)
    return 6;

  oputs ("t: 3U % 4\n");
  u = 3 % 4;
  if (u != 3)
    return 7;

  oputs ("t: 1U % 256\n");
  u = 1 % 256;
  if (u != 1)
    return 8;

  return 0;
}
