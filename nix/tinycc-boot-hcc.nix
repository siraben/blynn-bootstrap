{
  stdenv,
  lib,
  fetchurl,
  hcc,
  minimalBootstrap,
  mesLibc,
  m2libc,
}:

let
  version = "unstable-2024-07-07";
  rev = "ea3900f6d5e71776c5cfabcabee317652e3a19ee";
  support = ../vendor/hcc/support;

in
stdenv.mkDerivation {
  pname = "tinycc-boot-hcc";
  inherit version;

  src = fetchurl {
    url = "https://gitlab.com/janneke/tinycc/-/archive/${rev}/tinycc-${rev}.tar.gz";
    sha256 = "sha256-16JBGJATAWP+lPylOi3+lojpdv0SR5pqyxOV2PiVx0A=";
  };

  sourceRoot = "tinycc-${rev}";

  nativeBuildInputs = [
    hcc
    minimalBootstrap.stage0-posix.mescc-tools
  ];

  postPatch = ''
    substituteInPlace include/stddef.h \
      --replace-fail 'void *alloca' 'typedef union { long double ld; long long ll; } max_align_t; void *alloca'

    substituteInPlace x86_64-gen.c \
      --replace-fail 'char _onstack[nb_args], *onstack = _onstack;' 'char *onstack = tcc_malloc(nb_args);' \
      --replace-fail 'g(vtop->c.i & (ll ? 63 : 31));' 'if (ll) g(vtop->c.i & 63); else g(vtop->c.i & 31);'

    substituteInPlace tccelf.c \
      --replace-fail 'fill_got(s1);' '{ fill_got(s1); relocate_plt(s1); }'

    substituteInPlace libtcc.c \
      --replace-fail '#if defined(TCC_MUSL)' '#if defined(TCC_MUSL) || defined(TCC_MES_LIBC)'
  '';

  buildPhase = ''
    runHook preBuild

    tcc_include_src="$PWD/include"
    mes_include_src="${mesLibc}/include"

    cat > config.h <<'EOF'
    #define BOOTSTRAP 1
    #define HAVE_LONG_LONG 1
    #define HAVE_SETJMP 1
    #define HAVE_BITFIELD 1
    #define HAVE_FLOAT 1
    #define TCC_TARGET_X86_64 1
    #define inline
    #define CONFIG_TCCDIR ""
    #define CONFIG_SYSROOT ""
    #define CONFIG_TCC_CRTPREFIX "{B}"
    #define CONFIG_TCC_ELFINTERP "/mes/loader"
    #define CONFIG_TCC_LIBPATHS "{B}"
    #define CONFIG_TCC_SYSINCLUDEPATHS "/include"
    #define TCC_LIBGCC "libc.a"
    #define TCC_LIBTCC1 "libtcc1.a"
    #define CONFIG_TCC_LIBTCC1_MES 0
    #define CONFIG_TCCBOOT 1
    #define CONFIG_TCC_STATIC 1
    #define CONFIG_USE_LIBGCC 1
    #define TCC_MES_LIBC 1
    #define TCC_VERSION "0.9.28-${version}"
    #define ONE_SOURCE 1
    #define CONFIG_TCC_SEMLOCK 0
    EOF

    hcc \
      --expand-dump \
      -I . \
      -I "$tcc_include_src" \
      -I "$mes_include_src" \
      -D __linux__=1 \
      -D BOOTSTRAP=1 \
      -D HAVE_LONG_LONG=1 \
      -D HAVE_SETJMP=1 \
      -D HAVE_BITFIELD=1 \
      -D HAVE_FLOAT=1 \
      -D TCC_TARGET_X86_64=1 \
      -D inline= \
      -D CONFIG_TCCDIR=\"\" \
      -D CONFIG_SYSROOT=\"\" \
      -D CONFIG_TCC_CRTPREFIX=\"{B}\" \
      -D CONFIG_TCC_ELFINTERP=\"/mes/loader\" \
      -D CONFIG_TCC_LIBPATHS=\"{B}\" \
      -D CONFIG_TCC_SYSINCLUDEPATHS=\"$out/include\" \
      -D TCC_LIBGCC=\"libc.a\" \
      -D TCC_LIBTCC1=\"libtcc1.a\" \
      -D CONFIG_TCC_LIBTCC1_MES=0 \
      -D CONFIG_TCCBOOT=1 \
      -D CONFIG_TCC_STATIC=1 \
      -D CONFIG_USE_LIBGCC=1 \
      -D TCC_MES_LIBC=1 \
      -D TCC_VERSION=\"0.9.28-${version}\" \
      -D ONE_SOURCE=1 \
      -D CONFIG_TCC_SEMLOCK=0 \
      tcc.c > tcc-expanded.c

    hcc -S -o tcc-bootstrap-support.M1 ${support}/tcc-bootstrap-support.c
    hcc -S -o tcc-final-overrides.M1 ${support}/tcc-final-overrides.c
    hcc -S -o tcc.M1 tcc-expanded.c

    M1 --architecture amd64 --little-endian \
      -f ${m2libc}/amd64/amd64_defs.M1 \
      -f ${support}/amd64-start.M1 \
      -f ${support}/amd64-memory.M1 \
      -f tcc-bootstrap-support.M1 \
      -f tcc.M1 \
      -f tcc-final-overrides.M1 \
      -f ${support}/amd64-syscalls.M1 \
      --output tcc.hex2

    printf ':ELF_end\n' > tcc-end.hex2
    hex2 --architecture amd64 --little-endian --base-address 0x00600000 \
      --file ${m2libc}/amd64/ELF-amd64.hex2 \
      --file tcc.hex2 \
      --file tcc-end.hex2 \
      --output tcc
    chmod 555 tcc

    make_ar_noindex() {
      archive="$1"
      shift
      printf '!<arch>\n' > "$archive"
      for object in "$@"; do
        name="$(basename "$object")/"
        size="$(wc -c < "$object")"
        printf '%-16s%-12s%-6s%-6s%-8s%-10s`\n' "$name" 0 0 0 644 "$size" >> "$archive"
        cat "$object" >> "$archive"
        if [ $((size % 2)) -ne 0 ]; then
          printf '\n' >> "$archive"
        fi
      done
    }

    mkdir -p bootstrap-libs
    ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/crt1.o ${mesLibc}/lib/crt1.c
    ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/crti.o ${mesLibc}/lib/crti.c
    ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/crtn.o ${mesLibc}/lib/crtn.c
    ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/libc.o ${mesLibc}/lib/libc.c
    ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/libgetopt.o ${mesLibc}/lib/libgetopt.c
    ./tcc -c -I "$tcc_include_src" -I "$mes_include_src" -D TCC_TARGET_X86_64=1 -o bootstrap-libs/libtcc1.o lib/libtcc1.c
    ./tcc -c -I "$tcc_include_src" -I "$mes_include_src" -D TCC_TARGET_X86_64=1 -o bootstrap-libs/va_list.o lib/va_list.c
    make_ar_noindex bootstrap-libs/libc.a bootstrap-libs/libc.o
    make_ar_noindex bootstrap-libs/libgetopt.a bootstrap-libs/libgetopt.o
    make_ar_noindex bootstrap-libs/libtcc1.a bootstrap-libs/libtcc1.o bootstrap-libs/va_list.o

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 tcc $out/bin/tcc
    mkdir -p $out/lib
    cp bootstrap-libs/crt1.o bootstrap-libs/crti.o bootstrap-libs/crtn.o $out/lib/
    cp bootstrap-libs/libc.a bootstrap-libs/libgetopt.a bootstrap-libs/libtcc1.a $out/lib/
    mkdir -p $out/include
    cp -r ${mesLibc}/include/. $out/include/
    chmod -R u+w $out/include
    cp -r include/. $out/include/
    runHook postInstall
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./tcc -version

    cat > include-smoke-header.h <<'EOF'
    #define HCC_INCLUDE_SMOKE 7
    EOF
    cat > include-smoke.c <<'EOF'
    #include "include-smoke-header.h"
    int main(){return HCC_INCLUDE_SMOKE;}
    EOF
    ./tcc -E include-smoke.c > include-smoke.i
    grep -q 'return 7' include-smoke.i
    ./tcc -c include-smoke.c -o include-smoke.o
    test -s include-smoke.o

    cat > macro-smoke.c <<'EOF'
    #define HCC_MACRO(NAME, CODE, STRING) NAME=CODE,
    enum { HCC_MACRO(HCC_VALUE, 0x20, "value") HCC_LAST };
    EOF
    ./tcc -E macro-smoke.c > macro-smoke.i
    grep -q 'HCC_VALUE=0x20' macro-smoke.i
    ./tcc -c macro-smoke.c -o macro-smoke.o
    test -s macro-smoke.o

    printf '%s\n' 'int main(){return 13;}' > smoke.c
    ./tcc -c smoke.c -o smoke.o
    test -s smoke.o

    printf '%s\n' 'int f(void){return 17;} int main(void){return f();}' > internal-call-smoke.c
    ./tcc -B bootstrap-libs internal-call-smoke.c -o internal-call-smoke
    set +e
    ./internal-call-smoke
    internal_call_status="$?"
    set -e
    test "$internal_call_status" -eq 17

    ./tcc -c \
      -I . \
      -I include \
      -I ${mesLibc}/include \
      -D __linux__=1 \
      -D BOOTSTRAP=1 \
      -D HAVE_LONG_LONG=1 \
      -D HAVE_SETJMP=1 \
      -D HAVE_BITFIELD=1 \
      -D HAVE_FLOAT=1 \
      -D TCC_TARGET_X86_64=1 \
      -D inline= \
      -D CONFIG_TCCDIR=\"\" \
      -D CONFIG_SYSROOT=\"\" \
      -D CONFIG_TCC_CRTPREFIX=\"{B}\" \
      -D CONFIG_TCC_ELFINTERP=\"/mes/loader\" \
      -D CONFIG_TCC_LIBPATHS=\"{B}\" \
      -D CONFIG_TCC_SYSINCLUDEPATHS=\"$PWD/include:${mesLibc}/include\" \
      -D TCC_LIBGCC=\"libc.a\" \
      -D TCC_LIBTCC1=\"libtcc1.a\" \
      -D CONFIG_TCC_LIBTCC1_MES=0 \
      -D CONFIG_TCC_STATIC=1 \
      -D CONFIG_USE_LIBGCC=1 \
      -D TCC_MES_LIBC=1 \
      -D TCC_VERSION=\"0.9.28-${version}\" \
      -D ONE_SOURCE=1 \
      -D CONFIG_TCC_SEMLOCK=0 \
      tcc.c -o tcc-selfhost.o
    test -s tcc-selfhost.o

    ./tcc -c \
      -I . \
      -I include \
      -I ${mesLibc}/include \
      -D __linux__=1 \
      -D BOOTSTRAP=1 \
      -D HAVE_LONG_LONG=1 \
      -D HAVE_SETJMP=1 \
      -D HAVE_BITFIELD=1 \
      -D HAVE_FLOAT=1 \
      -D TCC_TARGET_X86_64=1 \
      -D TCC_MES_LIBC=1 \
      lib/libtcc1.c -o libtcc1.o
    ./tcc -ar rcs libtcc1.a libtcc1.o
    test -s libtcc1.a

    ./tcc -B bootstrap-libs smoke.c -o smoke-linked
    set +e
    ./smoke-linked
    smoke_status="$?"
    set -e
    test "$smoke_status" -eq 13

    ./tcc -B bootstrap-libs \
      -I . \
      -I include \
      -I ${mesLibc}/include \
      -D __linux__=1 \
      -D BOOTSTRAP=1 \
      -D HAVE_LONG_LONG=1 \
      -D HAVE_SETJMP=1 \
      -D HAVE_BITFIELD=1 \
      -D HAVE_FLOAT=1 \
      -D TCC_TARGET_X86_64=1 \
      -D inline= \
      -D CONFIG_TCCDIR=\"\" \
      -D CONFIG_SYSROOT=\"\" \
      -D CONFIG_TCC_CRTPREFIX=\"{B}\" \
      -D CONFIG_TCC_ELFINTERP=\"/mes/loader\" \
      -D CONFIG_TCC_LIBPATHS=\"{B}\" \
      -D CONFIG_TCC_SYSINCLUDEPATHS=\"$PWD/include:${mesLibc}/include\" \
      -D TCC_LIBGCC=\"libc.a\" \
      -D TCC_LIBTCC1=\"libtcc1.a\" \
      -D CONFIG_TCC_LIBTCC1_MES=0 \
      -D CONFIG_TCC_STATIC=1 \
      -D CONFIG_USE_LIBGCC=1 \
      -D TCC_MES_LIBC=1 \
      -D TCC_VERSION=\"0.9.28-${version}\" \
      -D ONE_SOURCE=1 \
      -D CONFIG_TCC_SEMLOCK=0 \
      tcc.c -o tcc-stage2
    ./tcc-stage2 -version
    ./tcc-stage2 -B bootstrap-libs internal-call-smoke.c -o internal-call-stage2
    set +e
    ./internal-call-stage2
    stage2_status="$?"
    set -e
    test "$stage2_status" -eq 17

    runHook postCheck
  '';

  meta = with lib; {
    description = "Bootstrappable tinycc built through the GHC-backed hcc driver";
    homepage = "https://gitlab.com/janneke/tinycc";
    license = licenses.lgpl21Only;
    platforms = [ "x86_64-linux" ];
  };
}
