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
, keepArtifacts ? false
, pname ? "hcc-gcc46-source-smoke"
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

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    mkdir -p probe/include/sys work

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
#define LONG_LONG_MIN (-9223372036854775807LL - 1LL)
#define LONG_LONG_MAX 9223372036854775807LL
#define ULONG_LONG_MAX 18446744073709551615ULL
#endif
EOF_LIMITS

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
extern int errno;
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
struct stat {
  long st_dev;
  long st_ino;
  int st_mode;
  long st_size;
  long st_mtime;
};
int stat(const char *, struct stat *);
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

    cat > probe/include/sys/mman.h <<'EOF_MMAN'
#ifndef HCC_PROBE_SYS_MMAN_H
#define HCC_PROBE_SYS_MMAN_H
#include <sys/types.h>
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
    DEFS="-D TARGET_NAME=\"x86_64-unknown-linux-gnu\" $VERSION_DEFS -D IN_GCC=1 -D HAVE_CONFIG_H=1 -D CHAR_BIT=8 -D __SIZEOF_LONG__=8 -D __SIZEOF_POINTER__=8 -D __SIZEOF_LONG_LONG__=8 -D __GNUC__=4 -D __GNUC_MINOR__=6 -D BASEVER=\"$BASEVER\" $PPDEFS -D MPFR_RNDN=GMP_RNDN -D MPFR_RNDZ=GMP_RNDZ -D MPFR_RNDU=GMP_RNDU -D MPFR_RNDD=GMP_RNDD -D MPFR_RNDA=GMP_RNDNA"
    INC="-I probe/include -I obj/gcc -I ${lib.getDev gmp}/include -I ${lib.getDev mpfr}/include -I ${lib.getDev libmpc}/include -I ${lib.getDev zlib}/include -I gcc-4.6.4/gcc -I gcc-4.6.4/include -I gcc-4.6.4/libcpp/include -I gcc-4.6.4/libgcc -I gcc-4.6.4/libdecnumber -I gcc-4.6.4/libdecnumber/bid -I gcc-4.6.4/libdecnumber/dpd"

    compiled=0
    : > work/compiled.txt
    : > work/m1-files.txt
    : > work/selected.txt

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

    {
      echo "gcc: gcc-4.6.4"
      echo "mode: configured source-to-M1 frontier"
      echo "target: ${target}"
      echo "compiled: $compiled"
      echo "selected: ${toString (builtins.length sourceFiles)}"
      echo "artifacts: ${if keepArtifacts then "kept" else "discarded"}"
      echo "note: this is the bounded flake test for representative GCC 4.6.4 C compiler sources; the full top-level source sweep is intentionally kept out of the regular test target because very large files such as builtins.c make hcpp memory-heavy."
    } > work/summary.txt

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 work/summary.txt "$out/share/hcc-gcc46-source-smoke/summary.txt"
    install -Dm644 work/compiled.txt "$out/share/hcc-gcc46-source-smoke/compiled.txt"
    install -Dm644 work/m1-files.txt "$out/share/hcc-gcc46-source-smoke/m1-files.txt"
    install -Dm644 work/selected.txt "$out/share/hcc-gcc46-source-smoke/selected.txt"
    if [ "${if keepArtifacts then "1" else "0"}" = 1 ]; then
      mkdir -p "$out/share/hcc-gcc46-source-smoke/m1"
      cp work/*.M1 "$out/share/hcc-gcc46-source-smoke/m1/"
    fi
    runHook postInstall
  '';

  meta = {
    description = "HCC source-to-M1 frontier over representative configured GCC 4.6.4 C compiler sources";
  };
}
