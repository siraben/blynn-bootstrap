{
  lib,
  buildPlatform,
  hostPlatform,
  fetchurl,
  bash,
  gcc,
  binutils,
  gnumake,
  gnupatch,
  gnugrep,
  gnused,
  gnutar,
  gzip,
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

  patches = [
    ../../patches/upstreams/musl-runtime-shell-path.patch
  ];
in
bash.runCommand "${pname}-${version}"
  {
    inherit pname version meta;

    nativeBuildInputs = [
      gcc
      binutils
      gnumake
      gnupatch
      gnused
      gnugrep
      gnutar
      gzip
    ];

    passthru.tests.hello-world =
      result:
      bash.runCommand "${pname}-simple-program-${version}"
        {
          nativeBuildInputs = [
            gcc
            binutils
            result
          ];
        }
        ''
          cat <<EOF >> test.c
          #include <stdio.h>
          int main() {
            printf("Hello World!\n");
            return 0;
          }
          EOF
          musl-gcc -o test test.c
          ./test
          mkdir $out
        '';
  }
  ''
    tar xzf ${src}
    cd musl-${version}

    ${lib.concatMapStringsSep "\n" (f: "patch -Np0 -i ${f}") patches}

    # Avoid impure /bin/sh in helper scripts.
    sed -i 's|/bin/sh|${bash}/bin/bash|' \
      tools/*.sh

    bash ./configure \
      --prefix=$out \
      --build=${buildPlatform.config} \
      --host=${hostPlatform.config} \
      --syslibdir=$out/lib \
      --enable-wrapper

    make -j $NIX_BUILD_CORES
    make -j $NIX_BUILD_CORES install
    sed -i 's|/bin/sh|${bash}/bin/bash|' $out/bin/*
    ln -s ../lib/libc.so $out/bin/ldd
  ''
