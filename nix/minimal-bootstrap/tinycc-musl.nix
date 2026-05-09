{
  lib,
  stdenvNoCC,
  fetchurl,
  bash,
  tinycc,
  musl,
  buildPlatform,
  hccTinyccVaList ? false,
}:
let
  pname = "tinycc-musl";
  version = "unstable-2025-12-03";
  rev = "cb41cbfe717e4c00d7bb70035cda5ee5f0ff9341";

  src = fetchurl {
    url = "https://repo.or.cz/tinycc.git/snapshot/${rev}.tar.gz";
    hash = "sha256-MRuqq3TKcfIahtUWdhAcYhqDiGPkAjS8UTMsDE+/jGU=";
  };

  tccTarget =
    {
      i686-linux = "I386";
      x86_64-linux = "X86_64";
    }
    .${buildPlatform.system};

  patches = [
    ../../vendor/nixpkgs-minimal-bootstrap/tinycc/static-link.patch
    ../patches/upstreams/tinycc-musl-hcc-bootstrap.patch
  ];

  meta = {
    description = "Small, fast, and embeddable C compiler and interpreter";
    homepage = "https://repo.or.cz/w/tinycc.git";
    license = lib.licenses.lgpl21Only;
    teams = [ lib.teams.minimal-bootstrap ];
    platforms = [
      "i686-linux"
      "x86_64-linux"
    ];
  };

  tinycc-musl = stdenvNoCC.mkDerivation {
    inherit pname version src patches meta;
    patchFlags = [ "-p0" ];
    dontConfigure = true;
    dontFixup = true;
    dontUpdateAutotoolsGnuConfigScripts = true;

    nativeBuildInputs = [
      tinycc.compiler
    ];

    buildPhase = ''
        runHook preBuild
        set +x

        touch config.h
        hcc_va_list_flags="${lib.optionalString hccTinyccVaList "-D__HCC_TCC_VA_LIST"}"

        # The source tree's include/stdarg.h is part of TinyCC's x86_64 va_arg
        # support. With an HCC-built bootstrap compiler, the musl stdarg shim is
        # good enough to build the first tcc, but the self-rebuilt tcc needs the
        # TinyCC declarations to avoid generating a broken compiler.
        ln -s ${musl}/lib/libtcc1.a ./libtcc1.a

        tcc \
          -B ${tinycc.libs}/lib \
          -DC2STR \
          -o c2str \
          conftest.c
        ./c2str include/tccdefs.h tccdefs_.h

        tcc -v \
          -static \
          -o tcc-musl \
          $hcc_va_list_flags \
          -D TCC_TARGET_${tccTarget}=1 \
          -D CONFIG_TCCDIR=\"\" \
          -D CONFIG_TCC_CRTPREFIX=\"{B}\" \
          -D CONFIG_TCC_ELFINTERP=\"/musl/loader\" \
          -D CONFIG_TCC_LIBPATHS=\"{B}\" \
          -D CONFIG_TCC_SYSINCLUDEPATHS=\"${musl}/include\" \
          -D TCC_LIBGCC=\"libc.a\" \
          -D TCC_LIBTCC1=\"libtcc1.a\" \
          -D CONFIG_TCC_STATIC=1 \
          -D CONFIG_USE_LIBGCC=1 \
          -D TCC_VERSION=\"0.9.27\" \
          -D ONE_SOURCE=1 \
          -D TCC_MUSL=1 \
          -D CONFIG_TCC_PREDEFS=1 \
          -D CONFIG_TCC_SEMLOCK=0 \
          -D CONFIG_TCC_BACKTRACE=0 \
          -B . \
          -B ${tinycc.libs}/lib \
          tcc.c

        rm -f libtcc1.a
        tcc -c -D HAVE_CONFIG_H=1 lib/libtcc1.c
        if [ -n "$hcc_va_list_flags" ]; then
          tcc -c -D HAVE_CONFIG_H=1 -D TCC_TARGET_${tccTarget}=1 lib/va_list.c
          tcc -ar cr libtcc1.a libtcc1.o va_list.o
        else
          tcc -ar cr libtcc1.a libtcc1.o
        fi

        ./tcc-musl \
          -v \
          -static \
          -o tcc-musl \
          -D TCC_TARGET_${tccTarget}=1 \
          -D CONFIG_TCCDIR=\"\" \
          -D CONFIG_TCC_CRTPREFIX=\"{B}\" \
          -D CONFIG_TCC_ELFINTERP=\"/musl/loader\" \
          -D CONFIG_TCC_LIBPATHS=\"{B}\" \
          -D CONFIG_TCC_SYSINCLUDEPATHS=\"${musl}/include\" \
          -D TCC_LIBGCC=\"libc.a\" \
          -D TCC_LIBTCC1=\"libtcc1.a\" \
          -D CONFIG_TCC_STATIC=1 \
          -D CONFIG_USE_LIBGCC=1 \
          -D TCC_VERSION=\"0.9.27\" \
          -D ONE_SOURCE=1 \
          -D TCC_MUSL=1 \
          -D CONFIG_TCC_PREDEFS=1 \
          -D CONFIG_TCC_SEMLOCK=0 \
          -D CONFIG_TCC_BACKTRACE=0 \
          -B . \
          -B ${musl}/lib \
          tcc.c

        rm -f libtcc1.a
        ./tcc-musl -c -D HAVE_CONFIG_H=1 lib/libtcc1.c
        ./tcc-musl -c -D HAVE_CONFIG_H=1 lib/alloca.S
        if [ -n "$hcc_va_list_flags" ]; then
          tcc -c -D HAVE_CONFIG_H=1 -D TCC_TARGET_${tccTarget}=1 lib/va_list.c
          ./tcc-musl -ar cr libtcc1.a libtcc1.o alloca.o va_list.o
        else
          ./tcc-musl -ar cr libtcc1.a libtcc1.o alloca.o
        fi

        runHook postBuild
      '';

    installPhase = ''
        runHook preInstall
        install -D tcc-musl $out/bin/tcc
        install -Dm444 libtcc1.a $out/lib/libtcc1.a
        runHook postInstall
      '';
  };
in
{
  compiler = bash.runCommand "${pname}-${version}-compiler" {
    inherit pname version meta;
    passthru.tests.hello-world =
      result:
      bash.runCommand "${pname}-simple-program-${version}" { } ''
        cat <<EOF >> test.c
        #include <stdio.h>
        int main() {
          printf("Hello World!\n");
          return 0;
        }
        EOF
        ${result}/bin/tcc -v -static -B${musl}/lib -o test test.c
        ./test
        mkdir $out
      '';
    passthru.tinycc-musl = tinycc-musl;
  } "install -D ${tinycc-musl}/bin/tcc $out/bin/tcc";

  libs =
    bash.runCommand "${pname}-${version}-libs"
      {
        inherit pname version meta;
      }
      ''
        mkdir $out
        cp -r ${musl}/* $out
        chmod +w $out/lib/libtcc1.a
        cp ${tinycc-musl}/lib/libtcc1.a $out/lib/libtcc1.a
      '';
}
