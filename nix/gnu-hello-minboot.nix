{
  stdenvNoCC,
  buildPlatform,
  hostPlatform,
  bootstrap,
  pname ? "gnu-hello-minboot",
}:

stdenvNoCC.mkDerivation {
  inherit pname;
  version = "2.12.3";

  dontUnpack = true;
  dontConfigure = true;
  dontPatch = true;
  dontFixup = true;
  dontPatchELF = true;
  dontUpdateAutotoolsGnuConfigScripts = true;

  src = builtins.fetchurl {
    url = "mirror://gnu/hello/hello-2.12.3.tar.gz";
    sha256 = "183a6rxnhixiyykd7qis0y9g9cfqhpkk872a245y3zl28can0pqd";
  };

  nativeBuildInputs = [
    bootstrap.bash
    bootstrap.binutils
    bootstrap.coreutils-musl
    bootstrap.diffutils
    bootstrap.findutils
    bootstrap.gawk
    bootstrap.gcc-glibc
    bootstrap.gnugrep
    bootstrap.gnumake
    bootstrap.gnused
    bootstrap.gnutar
    bootstrap.gzip
    bootstrap.xz
  ];

  buildPhase = ''
    runHook preBuild

    export PATH="${bootstrap.coreutils-musl}/bin:${bootstrap.gnused}/bin:${bootstrap.gnugrep}/bin:${bootstrap.gawk}/bin:${bootstrap.findutils}/bin:${bootstrap.gnumake}/bin:${bootstrap.gnutar}/bin:${bootstrap.gzip}/bin:${bootstrap.xz}/bin:$PATH"
    export CONFIG_SHELL="${bootstrap.bash}/bin/bash"
    export SHELL="$CONFIG_SHELL"
    tar xzf "$src"
    find hello-2.12.3 -exec chmod 755 {} ';'
    cd hello-2.12.3
    export CC="${bootstrap.gcc-glibc}/bin/gcc"
    export AR="${bootstrap.binutils}/bin/ar"
    export RANLIB="${bootstrap.binutils}/bin/ranlib"
    export LD="${bootstrap.binutils}/bin/ld"
    ./configure \
      --prefix="$out" \
      --build="${buildPlatform.config}" \
      --host="${hostPlatform.config}" \
      --disable-nls
    make

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    make install
    "$out/bin/hello" --version

    runHook postInstall
  '';
}
