{
  lib,
  buildPlatform,
  hostPlatform,
  fetchurl,
  bash,
  tinycc,
  gnumake,
  gnugrep,
  gnused,
}:
let
  common = import ./common.nix { inherit lib; };
  pname = "gnutar-musl";
  version = "1.12";
  meta = common.mkMeta {
    description = "GNU implementation of the tar archiver, built against musl";
    homepage = "https://www.gnu.org/software/tar/";
    mainProgram = "tar";
  };

  src = fetchurl {
    url = "mirror://gnu/tar/tar-${version}.tar.gz";
    hash = "sha256-xsN+iIsTbM76uQPFEUn0t71lnWnUrqISRfYQU6V6pgo=";
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
    chmod +x install-sh missing mkinstalldirs

    touch aclocal.m4 configure config.h.in \
      Makefile.in doc/Makefile.in intl/Makefile.in lib/Makefile.in \
      po/Makefile.in scripts/Makefile.in src/Makefile.in tests/Makefile.in

    export CC="tcc -B ${tinycc.libs}/lib"
    export LD=tcc
    export ac_cv_sizeof_unsigned_long=4
    export ac_cv_sizeof_long_long=8
    export ac_cv_header_netdb_h=no
    bash ./configure \
      --prefix=$out \
      --build=${buildPlatform.config} \
      --host=${hostPlatform.config} \
      --disable-dependency-tracking \
      --disable-nls

    make AR="tcc -ar"
    make install
  ''
