{
  lib,
  buildPlatform,
  hostPlatform,
  fetchurl,
  bash,
  gcc,
  binutils,
  gnumake,
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
in
bash.runCommand "${pname}-${version}"
  {
    inherit pname version meta;

    nativeBuildInputs = [
      gcc
      binutils
      gnumake
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

    # Avoid impure /bin/sh in helper scripts and runtime shell lookups.
    sed -i 's|/bin/sh|${bash}/bin/bash|' \
      tools/*.sh
    sed -i 's|posix_spawn(&pid, "/bin/sh",|posix_spawnp(\&pid, "sh",|' \
      src/stdio/popen.c src/process/system.c
    sed -i 's|execl("/bin/sh", "sh", "-c",|execlp("sh", "-c",|'\
      src/misc/wordexp.c

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
