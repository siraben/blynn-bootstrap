{
  lib,
  buildPlatform,
  hostPlatform,
  fetchurl,
  bash,
  tinycc,
  gnumake,
  gnused,
  gnugrep,
}:
let
  common = import ./common.nix { inherit lib; };
  pname = "gnutar";
  version = "1.12";
  meta = common.mkMeta {
    description = "GNU implementation of the tar archiver";
    homepage = "https://www.gnu.org/software/tar/";
    mainProgram = "tar";
  };

  src = fetchurl {
    url = "mirror://gnu/tar/tar-${version}.tar.gz";
    sha256 = "02m6gajm647n8l9a5bnld6fnbgdpyi4i3i83p7xcwv0kif47xhy6";
  };
in
bash.runCommand "${pname}-${version}"
  {
    inherit pname version meta;

    nativeBuildInputs = [
      tinycc.compiler
      gnumake
      gnused
      gnugrep
    ];

    passthru.tests.get-version = common.mkVersionTest bash pname version "tar";
  }
  ''
    ungz --file ${src} --output tar.tar
    untar --file tar.tar
    rm tar.tar
    cd tar-${version}

    touch aclocal.m4 configure config.h.in \
      Makefile.in doc/Makefile.in intl/Makefile.in lib/Makefile.in \
      po/Makefile.in scripts/Makefile.in src/Makefile.in tests/Makefile.in

    export CC="tcc -B ${tinycc.libs}/lib"
    bash ./configure \
      --build=${buildPlatform.config} \
      --host=${hostPlatform.config} \
      --disable-dependency-tracking \
      --disable-nls \
      --prefix=$out

    make AR="tcc -ar"
    make install
  ''
