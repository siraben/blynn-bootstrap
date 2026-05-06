{
  stdenv,
  lib,
  fetchurl,
  hcc,
}:

let
  version = "unstable-2024-07-07";
  rev = "ea3900f6d5e71776c5cfabcabee317652e3a19ee";
in
stdenv.mkDerivation {
  pname = "tinycc-boot-hcc";
  inherit version;

  src = fetchurl {
    url = "https://gitlab.com/janneke/tinycc/-/archive/${rev}/tinycc-${rev}.tar.gz";
    sha256 = "sha256-16JBGJATAWP+lPylOi3+lojpdv0SR5pqyxOV2PiVx0A=";
  };

  sourceRoot = "tinycc-${rev}";

  nativeBuildInputs = [ hcc ];

  postPatch = ''
    substituteInPlace include/stddef.h \
      --replace-fail 'void *alloca' 'typedef union { long double ld; long long ll; } max_align_t; void *alloca'

    substituteInPlace x86_64-gen.c \
      --replace-fail 'char _onstack[nb_args], *onstack = _onstack;' 'char *onstack = tcc_malloc(nb_args);' \
      --replace-fail 'abort();' '/* abort(); */' \
      --replace-fail 'g(vtop->c.i & (ll ? 63 : 31));' 'if (ll) g(vtop->c.i & 63); else g(vtop->c.i & 31);'

    substituteInPlace tccelf.c \
      --replace-fail 'fill_got(s1);' '{ fill_got(s1); relocate_plt(s1); }'
  '';

  buildPhase = ''
    runHook preBuild
    export HCC_BACKEND_CC="${stdenv.cc.targetPrefix}cc"
    hcc \
      -o tcc \
      -I . \
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
      tcc.c
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
    runHook postCheck
  '';

  meta = with lib; {
    description = "Bootstrappable tinycc built through the GHC-backed hcc driver";
    homepage = "https://gitlab.com/janneke/tinycc";
    license = licenses.lgpl21Only;
    platforms = [ "x86_64-linux" ];
  };
}
