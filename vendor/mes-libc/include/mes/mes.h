/* -*-comment-start: "//";comment-end:""-*-
 * GNU Mes --- Maxwell Equations of Software
 * Copyright © 2016,2017,2018,2019,2020,2021,2022 Jan (janneke) Nieuwenhuizen <janneke@gnu.org>
 * Copyright © 2022 Timothy Sample <samplet@ngyro.com>
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

#ifndef __MES_MES_H
#define __MES_MES_H

#include <sys/types.h>
#include "mes/cc.h"

struct scm
{
  long type;
  union
  {
    struct scm *car;
    long car_value;
    char *bytes;
    long length;
    struct scm *ref;
    struct scm *binding;
    struct scm *macro;
    long port;
  };
  union
  {
    struct scm *cdr;
    long cdr_value;
    struct scm *closure;
    struct scm *continuation;
    char *name;
    struct scm *string;
    struct scm *structure;
    long value;
    FUNCTION function;
    struct scm *vector;
    long lexical_p; /* for bindings */
  };
};

/* M2-Planet does not support pointer arithmetic.  Explicitly compensate
   for that by multiplying with M2_CELL_SIZE when using cell
   pointers. */
#if __M2__
#define M2_CELL_SIZE sizeof (struct scm)
#else
#define M2_CELL_SIZE 1
#endif

/* mes */
extern char *g_datadir;
extern int g_debug;
extern char *g_buf;
extern int g_continuations;
extern struct scm *g_symbols;
extern struct scm *g_symbol_max;
extern int g_mini;

/* a/env */
extern struct scm *R0;
/* param 1 */
extern struct scm *R1;
/* save 2 */
extern struct scm *R2;
/* continuation */
extern struct scm *R3;
/* initial module obarray */
extern struct scm *M0;
/* current module */
extern struct scm *M1;
/* macro */
extern struct scm *g_macros;
extern struct scm *g_ports;

/* gc */
extern size_t ARENA_SIZE;
extern size_t MAX_ARENA_SIZE;
extern size_t STACK_SIZE;
extern size_t JAM_SIZE;
extern size_t GC_SAFETY;
extern size_t MAX_STRING;
extern char *g_arena;
extern struct scm *cell_arena;
extern struct scm *cell_zero;

extern struct scm *g_free;
extern struct scm *g_symbol;

extern struct scm **g_stack_array;
extern struct scm *g_cells;
extern struct scm *g_news;
extern long g_stack;
extern size_t gc_count;
extern struct timespec *gc_start_time;
extern struct timespec *gc_end_time;
extern size_t gc_time;

extern char **__execl_c_argv;
extern char **__execle_c_env;
extern char *__open_boot_buf;
extern char *__open_boot_file_name;
extern char *__setenv_buf;
extern char *__reader_read_char_buf;
extern struct timespec *g_start_time;
extern struct timeval *__gettimeofday_time;
extern struct timespec *__get_internal_run_time_ts;
extern struct utsname *__uts;

extern struct scm *scm_hash_table_type;
extern struct scm *scm_variable_type;

struct scm *cast_charp_to_scmp (char const *i);
struct scm **cast_charp_to_scmpp (char const *i);
char *cast_voidp_to_charp (void const *i);
long cast_scmp_to_long (struct scm *i);
char *cast_scmp_to_charp (struct scm *i);

struct scm *alloc (long n);
struct scm *apply (struct scm *f, struct scm *x, struct scm *a);
struct scm *apply_builtin (struct scm *fn, struct scm *x);
struct scm *apply_builtin0 (struct scm *fn);
struct scm *apply_builtin1 (struct scm *fn, struct scm *x);
struct scm *apply_builtin2 (struct scm *fn, struct scm *x, struct scm *y);
struct scm *apply_builtin3 (struct scm *fn, struct scm *x, struct scm *y, struct scm *z);
struct scm *builtin_name (struct scm *builtin);
struct scm *cstring_to_list (char const *s);
struct scm *cstring_to_symbol (char const *s);
struct scm *cell_ref (struct scm *cell, long index);
struct scm *current_module_variable (struct scm *name, struct scm *define_p);
struct scm *standard_eval_closure (struct scm *name, struct scm *define_p);
struct scm *standard_interface_eval_closure (struct scm *name, struct scm *define_p);
struct scm *module_make_local_var_x (struct scm *module, struct scm *name);
struct scm *module_variable (struct scm *module, struct scm *name);
struct scm *fdisplay_ (struct scm *, int, int);
struct scm *init_symbols ();
struct scm *init_time (struct scm *a);
struct scm *lookup_binding (struct scm *name, struct scm *define_p);
struct scm *lookup_value (struct scm *name);
struct scm *make_builtin_type ();
struct scm *make_bytes (size_t length);
struct scm *make_cell (long type, struct scm *car, struct scm *cdr);
struct scm *make_pointer_cell (long type, long car, void *cdr);
struct scm *make_value_cell (long type, long car, long cdr);
struct scm *make_char (int n);
struct scm *make_continuation (long n);
struct scm *make_hash_table_ (long size);
struct scm *make_hash_table_type ();
struct scm *make_initial_module (struct scm *a);
struct scm *make_macro (struct scm *name, struct scm *x);
struct scm *make_number (long n);
struct scm *make_ref (struct scm *x);
struct scm *make_string (char const *s, size_t length);
struct scm *make_string0 (char const *s);
struct scm *make_string_port (struct scm *x);
struct scm *make_variable_type ();
struct scm *make_vector_ (long k, struct scm *e);
struct scm *mes_builtins (struct scm *a);
struct scm *push_cc (struct scm *p1, struct scm *p2, struct scm *a, struct scm *c);
struct scm *set_x (struct scm *x, struct scm *e, int define_p);
struct scm *struct_ref_ (struct scm *x, long i);
struct scm *struct_set_x_ (struct scm *x, long i, struct scm *e);
struct scm *vector_ref_ (struct scm *x, long i);
struct scm *vector_set_x_ (struct scm *x, long i, struct scm *e);
FUNCTION builtin_function (struct scm *builtin);
void assert_num (long pos, struct scm *x);
void assert_range (int assert, long x);
void assert_struct (long pos, struct scm *x);
#if 0
void assert_type (long type, char const *name_name, struct scm *x)
#endif
char *cell_bytes (struct scm *x);
int peekchar ();
int readchar ();
int unreadchar ();
long gc_free ();
long length__ (struct scm *x);
size_t bytes_cells (size_t length);
void assert_max_string (size_t i, char const *msg, char const *string);
void assert_msg (int check, char *msg);
void assert_number (char const *name, struct scm *x);
void copy_cell (struct scm *to, struct scm *from);
void gc_ ();
void gc_dump_arena (struct scm *cells, long size);
void gc_init ();
void gc_peek_frame ();
void gc_pop_frame ();
void gc_push_frame ();
void gc_stats_ (char const* where);
void init_symbols_ ();
long seconds_and_nanoseconds_to_long (long s, long ns);

#include "mes/builtins.h"
#include "mes/constants.h"
#include "mes/symbols.h"

#endif /* __MES_MES_H */
