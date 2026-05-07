{
  stdenv,
  lib,
  fetchurl,
  hcc,
  minimalBootstrap,
  m2libc,
}:

let
  version = "unstable-2024-07-07";
  rev = "ea3900f6d5e71776c5cfabcabee317652e3a19ee";
  support = ../vendor/hcc/support;

  tccIncludeSrc = fetchurl {
    url = "https://repo.or.cz/tinycc.git/snapshot/cb41cbfe717e4c00d7bb70035cda5ee5f0ff9341.tar.gz";
    hash = "sha256-MRuqq3TKcfIahtUWdhAcYhqDiGPkAjS8UTMsDE+/jGU=";
  };

  mesSrc = fetchurl {
    url = "https://ftpmirror.gnu.org/mes/mes-0.27.1.tar.gz";
    hash = "sha256-GDpA6kfqSfih470bnRLmdjdNZNY7x557wa59Zz398l0=";
  };
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
  '';

  buildPhase = ''
    runHook preBuild

    tar xzf ${tccIncludeSrc}
    tar xzf ${mesSrc}
    tcc_include_src="$PWD/tinycc-cb41cbf/include"
    mes_include_src="$PWD/mes-0.27.1/include"

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
    #define TCC_MUSL 1
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
      -D TCC_MUSL=1 \
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

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 tcc $out/bin/tcc
    mkdir -p $out/include
    cp -r include/. $out/include/
    runHook postInstall
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./tcc -version
    printf '%s\n' 'int main(){return 13;}' > smoke.c
    ./tcc -c smoke.c -o smoke.o
    test -s smoke.o
    runHook postCheck
  '';

  meta = with lib; {
    description = "Bootstrappable tinycc built through the GHC-backed hcc driver";
    homepage = "https://gitlab.com/janneke/tinycc";
    license = licenses.lgpl21Only;
    platforms = [ "x86_64-linux" ];
  };
}
