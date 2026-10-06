{ stdenv
, lib
, fetchurl
, bzip2
, gawk
, gmp
, gnumake
, hcc
, libmpc
, mpfr
, perl
, fullManifest ? false
, keepArtifacts ? false
, pname ? "hcc-gcc46-source-smoke"
, softFloatRuntime ? false
, sourceFiles ? [
    "alias.c"
    "alloc-pool.c"
    "attribs.c"
    "auto-inc-dec.c"
    "bb-reorder.c"
    "cfg.c"
    "ggc-none.c"
    "intl.c"
    "read-rtl.c"
    "recog.c"
    "targhooks.c"
    "timevar.c"
    "tree.c"
    "tree-ssa-operands.c"
    "unwind-dw2.c"
    "vmsdbgout.c"
  ]
, target ? "amd64"
, texinfo
, zlib
}:

stdenv.mkDerivation {
  inherit pname;
  version = "4.6.4";

  src = fetchurl {
    url = "https://ftp.gnu.org/gnu/gcc/gcc-4.6.4/gcc-4.6.4.tar.bz2";
    hash = "sha256-Na8Wr6C2evm46xXK+3bSvF9WhUBVJSL13CyI3UXZd+g=";
  };

  patches = [ ./patches/gcc46-hcc-bootstrap.patch ];
  patchFlags = [ "-p1" "-d" "gcc-4.6.4" "--fuzz=0" ];

  nativeBuildInputs = [
    bzip2
    gawk
    gnumake
    hcc
    perl
    texinfo
  ];

  buildInputs = [
    gmp
    libmpc
    mpfr
    zlib
  ];

  unpackPhase = ''
    runHook preUnpack
    tar -xjf "$src"
    runHook postUnpack
  '';

  configurePhase = ''
    runHook preConfigure

    mkdir -p work
    printf 'gcc-configure-start\t%s\n' "$(date +%s)" > work/source-events.tsv

    export CFLAGS="-g -std=gnu89"
    export CFLAGS_FOR_BUILD="-g -std=gnu89"

    mkdir obj
    cd obj
    ../gcc-4.6.4/configure \
      --disable-bootstrap \
      --disable-decimal-float \
      --disable-dependency-tracking \
      --disable-libatomic \
      --disable-libcilkrts \
      --disable-libgomp \
      --disable-libitm \
      --disable-libmudflap \
      --disable-libquadmath \
      --disable-libsanitizer \
      --disable-libssp \
      --disable-libvtv \
      --disable-lto \
      --disable-lto-plugin \
      --disable-multilib \
      --disable-plugin \
      --disable-threads \
      --enable-languages=c \
      --enable-static \
      --disable-shared \
      --enable-threads=single \
      --disable-libstdcxx-pch \
      --disable-build-with-cxx \
      --with-gmp-include=${lib.getDev gmp}/include \
      --with-gmp-lib=${lib.getLib gmp}/lib \
      --with-mpfr-include=${lib.getDev mpfr}/include \
      --with-mpfr-lib=${lib.getLib mpfr}/lib \
      --with-mpc-include=${lib.getDev libmpc}/include \
      --with-mpc-lib=${lib.getLib libmpc}/lib
    cd ..

    make -C obj all-build-libiberty configure-gcc
    make -C obj/gcc \
      config.h \
      tconfig.h \
      tm.h \
      options.h \
      genrtl.h \
      target-hooks-def.h \
      tree-check.h \
      insn-modes.h \
      insn-constants.h \
      insn-flags.h \
      insn-config.h \
      insn-attr.h \
      insn-codes.h

    ${lib.optionalString fullManifest ''
      # Build every generated C/header prerequisite before replacing the host
      # compiler with HCC.  These build-machine generators are not linked into
      # stage1; their outputs are inputs to the real stage1 object graph.
      make -C obj configure-libdecnumber
      make -C obj/gcc \
        --eval='.SECONDEXPANSION:
      .PHONY: hcc-generated-files
      hcc-generated-files: $$(generated_files) $$(simple_generated_c)' \
        hcc-generated-files

      # GCC normally computes this after all stage1 objects and support
      # archives exist.  Its value is intentionally volatile and has no effect
      # on compiler semantics, so give the source sweep a deterministic value.
      cat > obj/gcc/cc1-checksum.c <<'EOF_CC1_CHECKSUM'
const unsigned char executable_checksum[16] = {
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};
EOF_CC1_CHECKSUM
    ''}

    printf 'gcc-configure-end\t%s\n' "$(date +%s)" >> work/source-events.tsv

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    mkdir -p probe/include/sys work
    ${lib.optionalString softFloatRuntime "export HCC_SOFT_FLOAT_RUNTIME=1"}
    ${lib.optionalString fullManifest "export HCC_KEEP_FAILED_TEMPS=1"}

    cat > probe/include/limits.h <<'EOF_LIMITS'
#ifndef HCC_PROBE_LIMITS_H
#define HCC_PROBE_LIMITS_H
#define CHAR_BIT 8
#define SCHAR_MAX 127
#define UCHAR_MAX 255
#define CHAR_MIN (-128)
#define CHAR_MAX 127
#define SHRT_MIN (-32768)
#define SHRT_MAX 32767
#define USHRT_MAX 65535
#define INT_MIN (-2147483647 - 1)
#define INT_MAX 2147483647
#define UINT_MAX 4294967295U
#define LONG_MIN (-9223372036854775807L - 1L)
#define LONG_MAX 9223372036854775807L
#define ULONG_MAX 18446744073709551615UL
#define SSIZE_MAX LONG_MAX
#define LONG_LONG_MIN (-9223372036854775807LL - 1LL)
#define LONG_LONG_MAX 9223372036854775807LL
#define ULONG_LONG_MAX 18446744073709551615ULL
#endif
EOF_LIMITS

    cat > probe/include/float.h <<'EOF_FLOAT'
#ifndef HCC_PROBE_FLOAT_H
#define HCC_PROBE_FLOAT_H
#define FLT_RADIX 2
#define FLT_MANT_DIG 24
#define DBL_MANT_DIG 53
#define LDBL_MANT_DIG 64
#define FLT_MIN_EXP (-125)
#define DBL_MIN_EXP (-1021)
#define LDBL_MIN_EXP (-16381)
#define FLT_MAX_EXP 128
#define DBL_MAX_EXP 1024
#define LDBL_MAX_EXP 16384
#endif
EOF_FLOAT

    cat > probe/include/stddef.h <<'EOF_STDDEF'
#ifndef HCC_PROBE_STDDEF_H
#define HCC_PROBE_STDDEF_H
typedef unsigned long size_t;
typedef long ptrdiff_t;
typedef int wchar_t;
#define NULL ((void *)0)
#define offsetof(type, member) ((size_t)&((type *)0)->member)
#endif
EOF_STDDEF

    cat > probe/include/stdarg.h <<'EOF_STDARG'
#ifndef HCC_PROBE_STDARG_H
#define HCC_PROBE_STDARG_H
struct __hcc_va_state {
  unsigned int gp_offset;
  unsigned int fp_offset;
  void *overflow_arg_area;
  void *reg_save_area;
};
typedef struct __hcc_va_state __gnuc_va_list[1];
typedef __gnuc_va_list va_list;
#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_end(ap) __builtin_va_end(ap)
#define va_copy(dst, src) __builtin_va_copy(dst, src)
#define __va_copy(dst, src) __builtin_va_copy(dst, src)
#define va_arg(ap, type) __builtin_va_arg(ap, type)
#endif
EOF_STDARG

    cat > probe/include/ctype.h <<'EOF_CTYPE'
#ifndef HCC_PROBE_CTYPE_H
#define HCC_PROBE_CTYPE_H
int isalnum(int);
int isalpha(int);
int iscntrl(int);
int isdigit(int);
int isgraph(int);
int islower(int);
int isprint(int);
int ispunct(int);
int isspace(int);
int isupper(int);
int isxdigit(int);
int tolower(int);
int toupper(int);
#endif
EOF_CTYPE

    cat > probe/include/string.h <<'EOF_STRING'
#ifndef HCC_PROBE_STRING_H
#define HCC_PROBE_STRING_H
#include <stddef.h>
void *memchr(const void *, int, size_t);
int memcmp(const void *, const void *, size_t);
void *memcpy(void *, const void *, size_t);
void *memmove(void *, const void *, size_t);
void *memset(void *, int, size_t);
char *strcat(char *, const char *);
char *strchr(const char *, int);
int strcmp(const char *, const char *);
char *strcpy(char *, const char *);
size_t strcspn(const char *, const char *);
size_t strlen(const char *);
char *strncat(char *, const char *, size_t);
int strncmp(const char *, const char *, size_t);
char *strncpy(char *, const char *, size_t);
char *strpbrk(const char *, const char *);
char *strrchr(const char *, int);
size_t strspn(const char *, const char *);
char *strstr(const char *, const char *);
char *strtok(char *, const char *);
char *strerror(int);
#endif
EOF_STRING

    cat > probe/include/strings.h <<'EOF_STRINGS'
#ifndef HCC_PROBE_STRINGS_H
#define HCC_PROBE_STRINGS_H
#include <string.h>
int strcasecmp(const char *, const char *);
int strncasecmp(const char *, const char *, size_t);
void bzero(void *, size_t);
#endif
EOF_STRINGS

    cat > probe/include/stdlib.h <<'EOF_STDLIB'
#ifndef HCC_PROBE_STDLIB_H
#define HCC_PROBE_STDLIB_H
#include <stddef.h>
void free(void *);
void *malloc(size_t);
void *calloc(size_t, size_t);
void *realloc(void *, size_t);
void abort(void);
void exit(int);
#endif
EOF_STDLIB

    cat > probe/include/stdio.h <<'EOF_STDIO'
#ifndef HCC_PROBE_STDIO_H
#define HCC_PROBE_STDIO_H
typedef struct FILE FILE;
#define BUFSIZ 8192
#define EOF (-1)
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;
int printf(const char *, ...);
int fprintf(FILE *, const char *, ...);
int fputs(const char *, FILE *);
int putchar(int);
#endif
EOF_STDIO

    cat > probe/include/errno.h <<'EOF_ERRNO'
#ifndef HCC_PROBE_ERRNO_H
#define HCC_PROBE_ERRNO_H
int *__errno_location(void);
#define errno (*__errno_location())
#define ENOENT 2
#define EINTR 4
#define E2BIG 7
#define EINVAL 22
#endif
EOF_ERRNO

    cat > probe/include/signal.h <<'EOF_SIGNAL'
#ifndef HCC_PROBE_SIGNAL_H
#define HCC_PROBE_SIGNAL_H
#define SIG_DFL ((void (*)(int))0)
#define SIG_IGN ((void (*)(int))1)
#define SIG_ERR ((void (*)(int))-1)
#define SIGHUP 1
#define SIGINT 2
#define SIGQUIT 3
#define SIGBUS 7
#define SIGSEGV 11
#define SIGPIPE 13
#define SIGALRM 14
#define SIGTERM 15
#define SIGCHLD 17
typedef void (*sighandler_t)(int);
sighandler_t signal(int, sighandler_t);
#endif
EOF_SIGNAL

    cat > probe/include/sys/stat.h <<'EOF_STAT'
#ifndef HCC_PROBE_SYS_STAT_H
#define HCC_PROBE_SYS_STAT_H
#define S_IFMT 0170000
#define S_IFDIR 0040000
#define S_IFREG 0100000
/* Match the x86_64 Linux/glibc ABI used by the host-assisted direct link.
   Passing a reduced source-level model to libc would let stat overwrite the
   caller's storage even if GCC only names a subset of these fields. */
struct stat {
  unsigned long st_dev;
  unsigned long st_ino;
  unsigned long st_nlink;
  unsigned int st_mode;
  unsigned int st_uid;
  unsigned int st_gid;
  int __pad0;
  unsigned long st_rdev;
  long st_size;
  long st_blksize;
  long st_blocks;
  long st_atime;
  unsigned long st_atimensec;
  long st_mtime;
  unsigned long st_mtimensec;
  long st_ctime;
  unsigned long st_ctimensec;
  long __glibc_reserved[3];
};
int stat(const char *, struct stat *);
int fstat(int, struct stat *);
int lstat(const char *, struct stat *);
#endif
EOF_STAT

    cat > probe/include/sys/file.h <<'EOF_FILE'
#ifndef HCC_PROBE_SYS_FILE_H
#define HCC_PROBE_SYS_FILE_H
#define LOCK_SH 1
#define LOCK_EX 2
#define LOCK_NB 4
#define LOCK_UN 8
int flock(int, int);
#endif
EOF_FILE

    cat > probe/include/sys/types.h <<'EOF_TYPES'
#ifndef HCC_PROBE_SYS_TYPES_H
#define HCC_PROBE_SYS_TYPES_H
typedef unsigned long size_t;
typedef long ssize_t;
typedef long off_t;
typedef unsigned long dev_t;
typedef unsigned long ino_t;
typedef char *caddr_t;
#endif
EOF_TYPES

    cat > probe/include/unistd.h <<'EOF_UNISTD'
#ifndef HCC_PROBE_UNISTD_H
#define HCC_PROBE_UNISTD_H
#include <stddef.h>
#include <sys/types.h>
#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
#define R_OK 4
#define W_OK 2
#define X_OK 1
#define F_OK 0
int access(const char *, int);
int close(int);
int dup(int);
int dup2(int, int);
int execv(const char *, char *const []);
int execvp(const char *, char *const []);
long lseek(int, long, int);
ssize_t read(int, void *, size_t);
ssize_t write(int, const void *, size_t);
int unlink(const char *);
char *getcwd(char *, size_t);
#endif
EOF_UNISTD

    cat > probe/include/sys/param.h <<'EOF_PARAM'
#ifndef HCC_PROBE_SYS_PARAM_H
#define HCC_PROBE_SYS_PARAM_H
#define MAXPATHLEN 4096
#endif
EOF_PARAM

    cat > probe/include/sys/time.h <<'EOF_TIMEVAL'
#ifndef HCC_PROBE_SYS_TIME_H
#define HCC_PROBE_SYS_TIME_H
#include <sys/types.h>
struct timeval {
  long tv_sec;
  long tv_usec;
};
struct timezone {
  int tz_minuteswest;
  int tz_dsttime;
};
int gettimeofday(struct timeval *, struct timezone *);
#endif
EOF_TIMEVAL

    cat > probe/include/time.h <<'EOF_TIME'
#ifndef HCC_PROBE_TIME_H
#define HCC_PROBE_TIME_H
#include <stddef.h>
typedef long time_t;
typedef long clock_t;
struct tm {
  int tm_sec;
  int tm_min;
  int tm_hour;
  int tm_mday;
  int tm_mon;
  int tm_year;
  int tm_wday;
  int tm_yday;
  int tm_isdst;
};
time_t time(time_t *);
clock_t clock(void);
double difftime(time_t, time_t);
struct tm *localtime(const time_t *);
struct tm *gmtime(const time_t *);
#endif
EOF_TIME

    cat > probe/include/sys/wait.h <<'EOF_WAIT'
#ifndef HCC_PROBE_SYS_WAIT_H
#define HCC_PROBE_SYS_WAIT_H
#include <sys/types.h>
#define WNOHANG 1
#define WIFEXITED(status) (((status) & 0x7f) == 0)
#define WEXITSTATUS(status) (((status) >> 8) & 0xff)
int wait(int *);
int waitpid(int, int *, int);
#endif
EOF_WAIT

    cat > probe/include/sys/mman.h <<'EOF_MMAN'
#ifndef HCC_PROBE_SYS_MMAN_H
#define HCC_PROBE_SYS_MMAN_H
#include <sys/types.h>
#define PROT_NONE 0
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_PRIVATE 2
#define MAP_ANON 32
#define MAP_ANONYMOUS MAP_ANON
void *mmap(void *, size_t, int, int, int, off_t);
int munmap(caddr_t, size_t);
#endif
EOF_MMAN

    cat > probe/include/sys/resource.h <<'EOF_RESOURCE'
#ifndef HCC_PROBE_SYS_RESOURCE_H
#define HCC_PROBE_SYS_RESOURCE_H
typedef unsigned long rlim_t;
struct rlimit {
  rlim_t rlim_cur;
  rlim_t rlim_max;
};
#define RLIM_INFINITY ((rlim_t)-1)
#define RLIMIT_AS 9
#define RLIMIT_CORE 4
#define RLIMIT_DATA 2
#define RLIMIT_RSS 5
int getrlimit(int, struct rlimit *);
int setrlimit(int, const struct rlimit *);
#endif
EOF_RESOURCE

    cat > probe/include/sys/times.h <<'EOF_TIMES'
#ifndef HCC_PROBE_SYS_TIMES_H
#define HCC_PROBE_SYS_TIMES_H
typedef long clock_t;
struct tms {
  clock_t tms_utime;
  clock_t tms_stime;
  clock_t tms_cutime;
  clock_t tms_cstime;
};
clock_t times(struct tms *);
#endif
EOF_TIMES

    cat > probe/include/fcntl.h <<'EOF_FCNTL'
#ifndef HCC_PROBE_FCNTL_H
#define HCC_PROBE_FCNTL_H
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0100
#define O_TRUNC 01000
#define O_APPEND 02000
int open(const char *, int, ...);
#endif
EOF_FCNTL

    cat > probe/include/malloc.h <<'EOF_MALLOC'
#ifndef HCC_PROBE_MALLOC_H
#define HCC_PROBE_MALLOC_H
#include <stdlib.h>
#endif
EOF_MALLOC

    cat > probe/include/stdint.h <<'EOF_STDINT'
#ifndef HCC_PROBE_STDINT_H
#define HCC_PROBE_STDINT_H
typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef short int16_t;
typedef unsigned short uint16_t;
typedef int int32_t;
typedef unsigned int uint32_t;
typedef long int64_t;
typedef unsigned long uint64_t;
typedef long intptr_t;
typedef unsigned long uintptr_t;
typedef long intmax_t;
typedef unsigned long uintmax_t;
#define INT64_MAX 9223372036854775807L
#define UINT64_MAX 18446744073709551615UL
#endif
EOF_STDINT

    cat > probe/include/inttypes.h <<'EOF_INTTYPES'
#ifndef HCC_PROBE_INTTYPES_H
#define HCC_PROBE_INTTYPES_H
#include <stdint.h>
#define PRId64 "ld"
#define PRIu64 "lu"
#define PRIx64 "lx"
#endif
EOF_INTTYPES

    cat > probe/include/dlfcn.h <<'EOF_DLFCN'
#ifndef HCC_PROBE_DLFCN_H
#define HCC_PROBE_DLFCN_H
#define RTLD_LAZY 1
#define RTLD_NOW 2
#define RTLD_GLOBAL 256
void *dlopen(const char *, int);
void *dlsym(void *, const char *);
char *dlerror(void);
int dlclose(void *);
#endif
EOF_DLFCN

    cat > probe/include/pthread.h <<'EOF_PTHREAD'
#ifndef HCC_PROBE_PTHREAD_H
#define HCC_PROBE_PTHREAD_H
typedef int pthread_t;
typedef int pthread_attr_t;
typedef int pthread_cond_t;
typedef int pthread_condattr_t;
typedef int pthread_key_t;
typedef int pthread_mutex_t;
typedef int pthread_mutexattr_t;
typedef int pthread_once_t;
#define PTHREAD_ONCE_INIT 0
#define PTHREAD_MUTEX_INITIALIZER 0
#define PTHREAD_COND_INITIALIZER 0
#define PTHREAD_RECURSIVE_MUTEX_INITIALIZER 0
#define PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP 0
#define PTHREAD_MUTEX_RECURSIVE 1
#define PTHREAD_MUTEX_RECURSIVE_NP 1
#endif
EOF_PTHREAD

    cat > probe/include/wchar.h <<'EOF_WCHAR'
#ifndef HCC_PROBE_WCHAR_H
#define HCC_PROBE_WCHAR_H
typedef int wchar_t;
unsigned long mbstowcs(wchar_t *, const char *, unsigned long);
int wcswidth(const wchar_t *, unsigned long);
#endif
EOF_WCHAR

    cat > probe/include/locale.h <<'EOF_LOCALE'
#ifndef HCC_PROBE_LOCALE_H
#define HCC_PROBE_LOCALE_H
#define LC_CTYPE 0
#define LC_MESSAGES 5
#define LC_ALL 6
char *setlocale(int, const char *);
#endif
EOF_LOCALE

    cat > probe/include/langinfo.h <<'EOF_LANGINFO'
#ifndef HCC_PROBE_LANGINFO_H
#define HCC_PROBE_LANGINFO_H
#define CODESET 14
char *nl_langinfo(int);
#endif
EOF_LANGINFO

    cat > probe/include/libintl.h <<'EOF_LIBINTL'
#ifndef HCC_PROBE_LIBINTL_H
#define HCC_PROBE_LIBINTL_H
char *gettext(const char *);
char *dgettext(const char *, const char *);
char *dcgettext(const char *, const char *, int);
char *ngettext(const char *, const char *, unsigned long);
char *dngettext(const char *, const char *, const char *, unsigned long);
char *textdomain(const char *);
char *bindtextdomain(const char *, const char *);
#endif
EOF_LIBINTL

    cat > probe/include/zlib.h <<'EOF_ZLIB'
#ifndef HCC_PROBE_ZLIB_H
#define HCC_PROBE_ZLIB_H
#define Z_NULL 0
#define Z_OK 0
#define Z_STREAM_END 1
#define Z_NO_COMPRESSION 0
#define Z_BEST_COMPRESSION 9
#define Z_DEFAULT_COMPRESSION (-1)
#define Z_FINISH 4
#define Z_SYNC_FLUSH 2
typedef struct z_stream_s {
  unsigned char *next_in;
  unsigned int avail_in;
  unsigned char *next_out;
  unsigned int avail_out;
  void *(*zalloc)(void *, unsigned int, unsigned int);
  void (*zfree)(void *, void *);
  void *opaque;
} z_stream;
int deflateInit(z_stream *, int);
int deflate(z_stream *, int);
int deflateEnd(z_stream *);
int inflateInit(z_stream *, int);
int inflate(z_stream *, int);
int inflateEnd(z_stream *);
const char *zError(int);
#endif
EOF_ZLIB

    cat > probe/include/iconv.h <<'EOF_ICONV'
#ifndef HCC_PROBE_ICONV_H
#define HCC_PROBE_ICONV_H
typedef void *iconv_t;
iconv_t iconv_open(const char *, const char *);
unsigned long iconv(iconv_t, char **, unsigned long *, char **, unsigned long *);
int iconv_close(iconv_t);
#endif
EOF_ICONV

    cat > probe/include/unwind.h <<'EOF_UNWIND'
#ifndef HCC_PROBE_UNWIND_H
#define HCC_PROBE_UNWIND_H
#include "unwind-generic.h"
#endif
EOF_UNWIND

    BASEVER=$(sed -n '1p' gcc-4.6.4/gcc/BASE-VER)
    PPDEFS="-D GCC_INCLUDE_DIR=\"/usr/local/lib/gcc/x86_64-unknown-linux-gnu/$BASEVER/include\" -D FIXED_INCLUDE_DIR=\"/usr/local/lib/gcc/x86_64-unknown-linux-gnu/$BASEVER/include-fixed\" -D GPLUSPLUS_INCLUDE_DIR=\"/usr/local/include/c++/$BASEVER\" -D GPLUSPLUS_TOOL_INCLUDE_DIR=\"/usr/local/include/c++/$BASEVER/x86_64-unknown-linux-gnu\" -D GPLUSPLUS_BACKWARD_INCLUDE_DIR=\"/usr/local/include/c++/$BASEVER/backward\" -D LOCAL_INCLUDE_DIR=\"/usr/local/include\" -D CROSS_INCLUDE_DIR=\"/usr/local/lib/gcc/x86_64-unknown-linux-gnu/$BASEVER/x86_64-unknown-linux-gnu/sys-include\" -D TOOL_INCLUDE_DIR=\"/usr/local/lib/gcc/x86_64-unknown-linux-gnu/$BASEVER/x86_64-unknown-linux-gnu/include\" -D PREFIX=\"/usr/local/\" -D STANDARD_EXEC_PREFIX=\"/usr/local/lib/gcc/\""
    VERSION_DEFS="-D DATESTAMP=\"\" -D DEVPHASE=\"\" -D REVISION=\"\" -D PKGVERSION=\"\" -D BUGURL=\"\""
    DEFS="-D TARGET_NAME=\"x86_64-unknown-linux-gnu\" $VERSION_DEFS -D IN_GCC=1 -D HAVE_CONFIG_H=1 -D __HCC_BOOTSTRAP__=1 -D CHAR_BIT=8 -D __SIZEOF_LONG__=8 -D __SIZEOF_POINTER__=8 -D __SIZEOF_LONG_LONG__=8 -D __GNUC__=4 -D __GNUC_MINOR__=6 -D BASEVER=\"$BASEVER\" $PPDEFS"
    INC="-I probe/include -I obj/gcc -I ${lib.getDev gmp}/include -I ${lib.getDev mpfr}/include -I ${lib.getDev libmpc}/include -I ${lib.getDev zlib}/include -I gcc-4.6.4/gcc -I gcc-4.6.4/include -I gcc-4.6.4/libcpp/include -I gcc-4.6.4/libgcc -I gcc-4.6.4/libdecnumber -I gcc-4.6.4/libdecnumber/bid -I gcc-4.6.4/libdecnumber/dpd"

    compiled=0
    : > work/compiled.txt
    : > work/m1-files.txt
    : > work/selected.txt

    ${if fullManifest then ''
      hcc_sweep_start=$(date +%s)
      # Ask the configured GCC makefile for the exact objects linked into the
      # driver, C front end, and collect2.  Keep the roles as well as a unique
      # object list so the manifest is both auditable and directly executable.
      make -s -C obj/gcc \
        --eval='.PHONY: hcc-stage1-link-manifest
      hcc-stage1-link-manifest:
	@printf "xgcc %s\n" $(GCC_OBJS) gccspec.o version.o intl.o prefix.o $(EXTRA_GCC_OBJS)
	@printf "cc1 %s\n" $(C_OBJS) cc1-checksum.o main.o $(OBJS)
	@printf "collect2 %s\n" $(COLLECT2_OBJS)' \
        hcc-stage1-link-manifest > work/stage1-link-manifest.txt
      gawk '!seen[$2]++ { print $2 }' work/stage1-link-manifest.txt \
        > work/stage1-objects.txt

      # `make -q` deliberately exits 1 when targets are out of date.  Capture
      # the database separately so pipefail cannot mistake that for a manifest
      # failure.
      make -C obj/gcc -qp > work/make-database.txt 2>/dev/null ||
        test "$?" = 1
      gawk '
          NR == FNR { wanted[$1] = 1; order[++count] = $1; next }
          {
            object = $1
            sub(/:$/, "", object)
            if (!(object in wanted)) next
            basename = object
            sub(/^.*\//, "", basename)
            sub(/\.o$/, "", basename)
            for (i = 2; i <= NF; i++) {
              candidate = $i
              sub(/\|$/, "", candidate)
              if (candidate ~ /\.c$/) {
                if (!(object in source)) source[object] = candidate
                candidate_basename = candidate
                sub(/^.*\//, "", candidate_basename)
                sub(/\.c$/, "", candidate_basename)
                if (candidate_basename == basename) exact[object] = candidate
              }
            }
          }
          END {
            for (i = 1; i <= count; i++) {
              object = order[i]
              if (object in exact) source[object] = exact[object]
              if (!(object in source)) {
                print "missing source for " object > "/dev/stderr"
                bad = 1
              } else {
                print object, source[object]
              }
            }
            exit bad
          }
        ' work/stage1-objects.txt work/make-database.txt \
        > work/stage1-source-manifest.txt
      rm work/make-database.txt

      mkdir -p work/m1
      gawk '$1 != "cc1-checksum.o" { print }' work/stage1-objects.txt \
        > work/stage1-make-objects.txt
      while IFS= read -r object; do
        rm -f "obj/gcc/$object" "obj/gcc/$object.M1"
      done < work/stage1-objects.txt

      # cc1-checksum.c is generated outside the ordinary GCC object rules.
      hcc-cc-frontier --target ${lib.escapeShellArg target} -c \
        $DEFS $INC -o obj/gcc/cc1-checksum.o obj/gcc/cc1-checksum.c

      # A single make invocation preserves the configured dependency graph and
      # lets independent HCC front ends overlap.  Four jobs stays below the
      # memory budget of standard CI runners while avoiding the former
      # one-process-at-a-time 336-object sweep.
      hcc_jobs="$NIX_BUILD_CORES"
      if [ "$hcc_jobs" -gt 4 ]; then hcc_jobs=4; fi
      readarray -t stage1_make_objects < work/stage1-make-objects.txt
      make -C obj/gcc -j "$hcc_jobs" "''${stage1_make_objects[@]}" \
        CC=hcc-cc-frontier \
        CXX=hcc-cc-frontier \
        CPPFLAGS="$DEFS -I $PWD/probe/include"

      while IFS= read -r object; do
        echo "HCC GCC46 stage1 $object"
        test -s "obj/gcc/$object.M1"
        mkdir -p "work/m1/$(dirname "$object")"
        mv "obj/gcc/$object.M1" "work/m1/$object.M1"
        rm -f "obj/gcc/$object"
        echo "$object" >> work/compiled.txt
        echo "$object.M1" >> work/m1-files.txt
        echo "$object" >> work/selected.txt
        compiled=$((compiled + 1))
      done < work/stage1-objects.txt
      hcc_sweep_end=$(date +%s)
      {
        printf 'hcc-source-to-m1-start\t%s\n' "$hcc_sweep_start"
        printf 'hcc-source-to-m1-end\t%s\n' "$hcc_sweep_end"
      } >> work/source-events.tsv
    '' else ''
      for src in ${lib.escapeShellArgs sourceFiles}; do
        path="gcc-4.6.4/gcc/$src"
        base=''${src%.c}
        extra=
        case "$src" in
          intl.c) extra='-D LOCALEDIR="/usr/local/share/locale"' ;;
          read-rtl.c) extra='-D GENERATOR_FILE=1' ;;
        esac

        echo "HCC GCC46 $src"
        hcc-cc-frontier --target ${lib.escapeShellArg target} -c $DEFS $extra $INC -o "work/$base.o" "$path"
        mv "work/$base.o.M1" "work/$base.M1"
        rm -f "work/$base.o"
        if [ "${if keepArtifacts then "1" else "0"}" != 1 ]; then
          rm -f "work/$base.M1"
        fi
        echo "$src" >> work/compiled.txt
        echo "$base.M1" >> work/m1-files.txt
        echo "$src" >> work/selected.txt
        compiled=$((compiled + 1))
      done
    ''}

    {
      echo "gcc: gcc-4.6.4"
      echo "mode: ${if fullManifest then "make-derived stage1 source-to-M1 manifest" else "configured source-to-M1 frontier"}"
      echo "target: ${target}"
      echo "soft-float-runtime: ${if softFloatRuntime then "enabled" else "disabled"}"
      echo "compiled: $compiled"
      echo "selected: ${if fullManifest then "$compiled" else toString (builtins.length sourceFiles)}"
      echo "artifacts: ${if keepArtifacts then "kept" else "discarded"}"
      gcc_configure_start=$(gawk '$1 == "gcc-configure-start" { print $2; exit }' work/source-events.tsv)
      gcc_configure_end=$(gawk '$1 == "gcc-configure-end" { print $2; exit }' work/source-events.tsv)
      echo "gcc-configure-seconds: $((gcc_configure_end - gcc_configure_start))"
      ${lib.optionalString fullManifest ''
        echo "hcc-source-to-m1-seconds: $((hcc_sweep_end - hcc_sweep_start))"
        echo "hcc-jobs: $hcc_jobs"
      ''}
      echo "note: ${if fullManifest then "the configured GCC make graph derives this manifest from every object role linked into xgcc, cc1, and collect2" else "this is the bounded flake test for representative GCC 4.6.4 C compiler sources; the full make-derived stage1 sweep is a separate test target"}."
    } > work/summary.txt

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 work/summary.txt "$out/share/hcc-gcc46-source-smoke/summary.txt"
    install -Dm644 work/compiled.txt "$out/share/hcc-gcc46-source-smoke/compiled.txt"
    install -Dm644 work/m1-files.txt "$out/share/hcc-gcc46-source-smoke/m1-files.txt"
    install -Dm644 work/selected.txt "$out/share/hcc-gcc46-source-smoke/selected.txt"
    ${lib.optionalString fullManifest ''
      install -Dm644 work/stage1-link-manifest.txt "$out/share/hcc-gcc46-source-smoke/stage1-link-manifest.txt"
      install -Dm644 work/stage1-objects.txt "$out/share/hcc-gcc46-source-smoke/stage1-objects.txt"
      install -Dm644 work/stage1-source-manifest.txt "$out/share/hcc-gcc46-source-smoke/stage1-source-manifest.txt"
      install -Dm644 work/source-events.tsv "$out/share/hcc-gcc46-source-smoke/source-events.tsv"
    ''}
    if [ "${if keepArtifacts then "1" else "0"}" = 1 ]; then
      mkdir -p "$out/share/hcc-gcc46-source-smoke/m1"
      ${if fullManifest then ''
        cp -R work/m1/. "$out/share/hcc-gcc46-source-smoke/m1/"
      '' else ''
        cp work/*.M1 "$out/share/hcc-gcc46-source-smoke/m1/"
      ''}
    fi
    runHook postInstall
  '';

  meta = {
    description = "HCC source-to-M1 frontier over representative configured GCC 4.6.4 C compiler sources";
  };
}
