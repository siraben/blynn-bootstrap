{
  lib,
  buildPlatform,
  hostPlatform,
  fetchurl,
  bash,
  tinycc,
  gnumake,
  gnupatch,
  gnused,
  gnugrep,
  gnutar,
  gzip,
  hccTinyccVaList ? false,
}:

let
  pname = "musl";
  version = "1.2.6";
  meta = {
    description = "Efficient, small, quality libc implementation";
    homepage = "https://musl.libc.org";
    license = lib.licenses.mit;
    teams = [ lib.teams.minimal-bootstrap ];
    platforms = lib.platforms.unix;
  };

  src = fetchurl {
    url = "https://musl.libc.org/releases/musl-${version}.tar.gz";
    hash = "sha256-1YX9O2E8ZhUfwySejtRPdwIMtebB5jWmFtP5+CRgUSo=";
  };

  # Thanks to the live-bootstrap project!
  # See https://github.com/fosslinux/live-bootstrap/blob/d98f97e21413efc32c770d0356f1feda66025686/sysa/musl-1.1.24/musl-1.1.24.sh
  liveBootstrap = "https://github.com/fosslinux/live-bootstrap/raw/d98f97e21413efc32c770d0356f1feda66025686/sysa/musl-1.1.24";
  patches = [
    # tinycc doesn't implement backward-jumping jecxz, and it would be hard to implement
    (fetchurl {
      url = "${liveBootstrap}/patches/sigsetjmp.patch";
      hash = "sha256-wd2Aev1zPJXy3q933aiup5p1IMKzVJBquAyl3gbK4PU=";
    })
  ];
in
bash.runCommand "${pname}-${version}"
  {
    inherit pname version meta;

    nativeBuildInputs = [
      tinycc.compiler
      gnumake
      gnupatch
      gnused
      gnugrep
      gnutar
      gzip
    ];
  }
  ''
    # Unpack
    tar xzf ${src}
    cd musl-${version}

    # Patch
    ${lib.concatMapStringsSep "\n" (f: "patch -Np0 -i ${f}") patches}
    # tcc does not support complex types
    rm -rf src/complex
    # Configure fails without this
    mkdir -p /dev
    # https://github.com/ZilchOS/bootstrap-from-tcc/blob/2e0c68c36b3437386f786d619bc9a16177f2e149/using-nix/2a3-intermediate-musl.nix
    sed -i 's|/bin/sh|${bash}/bin/bash|' \
      tools/*.sh
    chmod 755 tools/*.sh
    # patch popen/system to search in PATH instead of hardcoding /bin/sh
    sed -i 's|posix_spawn(&pid, "/bin/sh",|posix_spawnp(\&pid, "sh",|' \
      src/stdio/popen.c src/process/system.c
    sed -i 's|execl("/bin/sh", "sh", "-c",|execlp("sh", "-c",|'\
      src/misc/wordexp.c
    if [ "${if hccTinyccVaList then "1" else "0"}" = 1 ]; then
      cat > hcc-alltypes.sed <<'EOF'
    /TYPEDEF __builtin_va_list va_list;/{
    c\
    #if defined(__TINYC__) && defined(__x86_64__) && defined(__HCC_TCC_VA_LIST)\
    #if !defined(__DEFINED___va_list_struct)\
    typedef struct { unsigned int gp_offset; unsigned int fp_offset; union { unsigned int overflow_offset; char *overflow_arg_area; }; char *reg_save_area; } __va_list_struct;\
    #define __DEFINED___va_list_struct\
    #endif\
    #if defined(__NEED_va_list) && !defined(__DEFINED_va_list)\
    typedef __va_list_struct va_list[1];\
    #define __DEFINED_va_list\
    #endif\
    #if defined(__NEED___isoc_va_list) && !defined(__DEFINED___isoc_va_list)\
    typedef __va_list_struct __isoc_va_list[1];\
    #define __DEFINED___isoc_va_list\
    #endif\
    #else\
    TYPEDEF __builtin_va_list va_list;\
    TYPEDEF __builtin_va_list __isoc_va_list;\
    #endif
    }
    /TYPEDEF __builtin_va_list __isoc_va_list;/d
    EOF
      sed -i -f hcc-alltypes.sed include/alltypes.h.in
      cat > include/stdarg.h <<'EOF'
    #ifndef _STDARG_H
    #define _STDARG_H

    #ifdef __cplusplus
    extern "C" {
    #endif

    #define __NEED_va_list

    #include <bits/alltypes.h>

    #if defined(__TINYC__) && defined(__x86_64__) && defined(__HCC_TCC_VA_LIST)
    void __va_start(__va_list_struct *ap, void *fp);
    void *__va_arg(__va_list_struct *ap, int arg_type, int size, int align);
    #define va_start(ap, last) __va_start(ap, __builtin_frame_address(0))
    #define va_arg(ap, type) (*(type *)(__va_arg(ap, __builtin_va_arg_types(type), sizeof(type), __alignof__(type))))
    #define va_copy(dest, src) (*(dest) = *(src))
    #define va_end(ap)
    #else
    #define va_start(v,l)   __builtin_va_start(v,l)
    #define va_end(v)       __builtin_va_end(v)
    #define va_arg(v,l)     __builtin_va_arg(v,l)
    #define va_copy(d,s)    __builtin_va_copy(d,s)
    #endif

    #ifdef __cplusplus
    }
    #endif

    #endif
    EOF
    fi

    # @PLT specifier is not supported by tinycc.
    # Calls do go through PLT regardless.
    sed -i 's|@PLT||' src/math/x86_64/expl.s
    sed -i 's|@PLT||' src/signal/x86_64/sigsetjmp.s

    # TODO Implement the required asm constraints 'x' and 't' in tinycc.
    # For now, we just remove code using those constraints. musl automatically
    # polyfills with pure C implementations.
    rm src/math/i386/*.c
    rm src/math/x86_64/*.c

    # Configure
    bash ./configure \
      --prefix=$out \
      --build=${buildPlatform.config} \
      --host=${hostPlatform.config} \
      --disable-shared \
      CC=tcc

    # Build
    # NOTE: parallel build (-j) under tcc here is unstable and broke a previous run.
    make AR="tcc -ar" RANLIB=true CFLAGS="-DSYSCALL_NO_TLS ${lib.optionalString hccTinyccVaList "-D__HCC_TCC_VA_LIST"}"

    # Install
    make install
    cp ${tinycc.libs}/lib/libtcc1.a $out/lib
  ''
