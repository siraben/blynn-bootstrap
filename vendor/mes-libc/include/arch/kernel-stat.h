/* -*-comment-start: "//";comment-end:""-*-
 * GNU Mes --- Maxwell Equations of Software
 * Copyright © 2017,2022 Jan (janneke) Nieuwenhuizen <janneke@gnu.org>
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
#ifndef __MES_LINUX_X86_64_KERNEL_STAT_H
#define __MES_LINUX_X86_64_KERNEL_STAT_H 1

// https://github.com/torvalds/linux/blob/master/arch/x86/include/uapi/asm/stat.h

// *INDENT-OFF*
struct stat
{
  unsigned long	st_dev;
  unsigned long	st_ino;
  unsigned long	st_nlink;
  unsigned int	st_mode;
  unsigned int	st_uid;
  unsigned int	st_gid;
  unsigned int	__pad0;
  unsigned long	st_rdev;
  long		st_size;
  long		st_blksize;
  long		st_blocks;
  unsigned long	st_atime;
  unsigned long	st_atime_nsec;
  unsigned long	st_mtime;
  unsigned long	st_mtime_nsec;
  unsigned long	st_ctime;
  unsigned long	st_ctime_nsec;
  unsigned long	__pad1;
  unsigned long	__pad2;
  unsigned long	__pad3;
  unsigned long	__pad4;
};

#endif // __MES_LINUX_X86_64_KERNEL_STAT_H
