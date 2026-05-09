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
#ifndef __LINUX_M2_KERNEL_STAT_H
#define __LINUX_M2_KERNEL_STAT_H

/* https://github.com/torvalds/linux/blob/master/arch/x86/include/uapi/asm/stat.h */

/* *INDENT-OFF* */
struct stat
{
  unsigned st_dev;
  unsigned st_ino;
  char st_mode[2];
  char st_nlink[2];
  char st_uid[2];
  char st_gid[2];
  unsigned st_rdev;
  unsigned st_size;
  unsigned st_blksize;
  unsigned st_blocks;
  unsigned st_atime;
  unsigned st_atime_usec;
  unsigned st_mtime;
  unsigned st_mtime_usec;
  unsigned st_ctime;
  unsigned st_ctime_usec;
  unsigned __pad0;
  unsigned __pad1;
};
#endif /* __LINUX_M2_KERNEL_STAT_H */
