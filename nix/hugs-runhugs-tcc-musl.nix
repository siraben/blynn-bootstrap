{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  tinyccMusl,
  gcc,
  gnumake,
  gnused,
  coreutils,
  pname ? "hugs98-runhugs-tcc-musl",
}:

let
  version = "2006-09";
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchFromGitHub {
    owner = "augustss";
    repo = "hugs98-plus-Sep2006";
    rev = "1f7b60e05b12df00d715d535bb01c189bc1b9b3c";
    hash = "sha256-g6/4kmdWKGDIu5PXVfP8O6Fl3v4bstXWAVkoxZiS6qo=";
  };

  nativeBuildInputs = [
    tinyccMusl.compiler
    gcc
    gnumake
    gnused
    coreutils
  ];

  dontFixup = true;
  dontPatchELF = true;
  dontUpdateAutotoolsGnuConfigScripts = true;

  postPatch = ''
    find -type f -exec sed -i 's@/bin/cp@cp@' {} +

    # Keep the checked-in Bison output; this bootstrap level should not need
    # a parser generator.
    touch src/parser.c

    sed -i \
      -e 's|extern int execvpe.*|extern int execvpe(const char *name, char *const argv[], char *const envp[]);|' \
      -e 's|^execvpe(char \*name, char \*const argv\[\], char \*\*envp)|execvpe(const char *name, char *const argv[], char *const envp[])|' \
      packages/base/include/HsBase.h \
      packages/base/cbits/execvpe.c
  '';

  configurePhase = ''
    runHook preConfigure

    unset STRIP
    export CC="${tinyccMusl.compiler}/bin/tcc -B ${tinyccMusl.libs}/lib -I ${tinyccMusl.libs}/include"
    export CFLAGS="-Wno-error=implicit-int -Wno-error=implicit-function-declaration"

    ./configure \
      --prefix="$out" \
      --enable-char-encoding=utf8 \
      --disable-path-canonicalization \
      --disable-timer \
      --disable-profiling \
      --disable-stack-dumps \
      --enable-large-banner \
      --disable-internal-prims \
      --disable-debug \
      --disable-tag \
      --disable-lint \
      --disable-only98 \
      --enable-ffi \
      --enable-pthreads

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    make install

    runHook postInstall
  '';

  passthru = {
    isHugs = true;
    nativeCompiler = tinyccMusl.compiler;
    nativeLibc = tinyccMusl.libs;
    notes = ''
      Native runhugs built by HCC-built TinyCC against bootstrapped musl.
      This follows the nixpkgs Hugs configure profile and does not carry Hugs
      source patches.
    '';
  };

  meta = {
    mainProgram = "runhugs";
    homepage = "https://www.haskell.org/hugs";
    description = "Bootstrap runhugs built by HCC-built TinyCC against musl";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
  };
}
