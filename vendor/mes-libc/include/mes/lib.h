/* -*-comment-start: "//";comment-end:""-*-
 * GNU Mes --- Maxwell Equations of Software
 * Copyright © 2016,2017,2018,2019,2020,2022 Jan (janneke) Nieuwenhuizen <janneke@gnu.org>
 * Copyright © 2023 Timothy Sample <samplet@ngyro.com>
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

#ifndef __MES_LIB_H
#define __MES_LIB_H

#include <mes/lib-mini.h>
#include <mes/lib-cc.h>

#define __FILEDES_MAX 4096
extern char *__brk;

char *cast_intp_to_charp (int const *i);
char *cast_long_to_charp (long i);
long cast_charp_to_long (char const *);
long cast_int_to_long (int i);
long cast_voidp_to_long (void const *);

int __mes_debug ();
void __ungetc_init ();
void __ungetc_clear (int filedes);
void __ungetc_set (int filedes, int c);
int __ungetc_p (int filedes);
long abtol (char const **p, int base);
char *itoa (int number);
char *ltoa (long number);
char *ltoab (long x, int base);
char *ntoab (long number, unsigned base, int signed_p);
char *utoa (unsigned number);
int eputc (int c);
int fdgetc (int fd);
char * fdgets (char *s, int count, int fd);
int fdputc (int c, int fd);
int fdputs (char const *s, int fd);
int fdungetc (int c, int fd);
char *_getcwd (char *buffer, size_t size);
int ioctl3 (int filedes, size_t command, long data);
int isnumber (int c, int base);
int mes_open (char const *file_name, int flags, int mask);
int _open2 (char const *file_name, int flags);
int _open3 (char const *file_name, int flags, int mask);
int oputc (int c);
int oputs (char const *s);
char *search_path (char const *file_name);
ssize_t _read (int fd, void *buffer, size_t size);
void assert_msg (int check, char *msg);

long __mesabi_imod (long a, long b);
long __mesabi_idiv (long a, long b);
void *__memcpy (void *dest, void const *src, size_t n);
void *__memmove (void *dest, void const *src, size_t n);
void *__memset (void *s, int c, size_t n);

#if !SYSTEM_LIBC
void __assert_fail (char const *s, char const *file, unsigned line,
                    char const *function);
ssize_t __buffered_read (int filedes, void *buffer, size_t size);
size_t __buffered_read_clear (int filedes);
long brk (void *addr);
#ifndef __raise
int __raise (int signal);
#endif
#endif // !SYSTEM_LIBC

#if !__M2__
double abtod (char const **p, int base);
char *dtoab (double number, int base, int signed_p);
char *ultoa (unsigned long number);
unsigned long __mesabi_umod (unsigned long a, unsigned long b);
unsigned long __mesabi_udiv (unsigned long a, unsigned long b);
unsigned long __mesabi_uldiv (unsigned long a, unsigned long b,
                              unsigned long *remainder);
#endif

#endif //__MES_LIB_H
