# The exact inputs of tinycc-boot-hcc's preprocessing step, exposed so the
# ML preprocessor (ccpp) can be byte-checked against hcpp's tcc-expanded.c
# without rebuilding TinyCC: the patched tcc tree with the generated
# config.h, the mes libc includes, and the argument list.
{ stdenvNoCC, fetchgit, mesLibc, version ? "unstable-2025-12-03" }:

stdenvNoCC.mkDerivation {
  pname = "tinycc-preproc-inputs";
  inherit version;

  src = fetchgit {
    url = "https://repo.or.cz/tinycc.git";
    rev = "cb41cbfe717e4c00d7bb70035cda5ee5f0ff9341";
    hash = "sha256-LgYeX6Q80Z6VNJ7iPk46fPpEr/dEAezqvR6jQddSsxI=";
  };

  sourceRoot = "tinycc-cb41cbf";

  patches = [
    ../patches/upstreams/tinycc-mescc-source.patch
    ../patches/upstreams/tinycc-riscv64-hcc-bootstrap.patch
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/tinycc
    cp -R . $out/tinycc
    ln -s ${mesLibc}/include $out/mes-include
    cat > $out/tinycc/config.h <<EOF
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
    #define CONFIG_TCC_SYSINCLUDEPATHS "/hcc-bootstrap/include"
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
    # argument list for hcpp/ccpp, one per line, relative to $out/tinycc
    cat > $out/cpp-args <<EOF
    -I
    .
    -I
    $out/tinycc/include
    -I
    ${mesLibc}/include
    -D
    __linux__=1
    -D
    BOOTSTRAP=1
    -D
    HAVE_LONG_LONG=1
    -D
    HAVE_SETJMP=1
    -D
    HAVE_BITFIELD=1
    -D
    HAVE_FLOAT=1
    -D
    TCC_TARGET_X86_64=1
    -D
    inline=
    -D
    CONFIG_TCCDIR=\"\"
    -D
    CONFIG_SYSROOT=\"\"
    -D
    CONFIG_TCC_CRTPREFIX=\"{B}\"
    -D
    CONFIG_TCC_ELFINTERP=\"/mes/loader\"
    -D
    CONFIG_TCC_LIBPATHS=\"{B}\"
    -D
    CONFIG_TCC_SYSINCLUDEPATHS=\"/hcc-bootstrap/include\"
    -D
    TCC_LIBGCC=\"libc.a\"
    -D
    TCC_LIBTCC1=\"libtcc1.a\"
    -D
    CONFIG_TCC_LIBTCC1_MES=0
    -D
    CONFIG_TCCBOOT=1
    -D
    CONFIG_TCC_STATIC=1
    -D
    CONFIG_USE_LIBGCC=1
    -D
    TCC_MES_LIBC=1
    -D
    TCC_VERSION=\"0.9.28-${version}\"
    -D
    ONE_SOURCE=1
    -D
    CONFIG_TCC_SEMLOCK=0
    tcc.c
    EOF
    runHook postInstall
  '';
}
