{
  stdenv,
  lib,
  blynn-precisely-debug-ghc,
  minimalBootstrap,
  src,
  blynnSrc,
}:

stdenv.mkDerivation {
  pname = "mutable-io-proof";
  version = "0-unstable-2026-05-06";

  inherit src;

  nativeBuildInputs = [
    blynn-precisely-debug-ghc
    minimalBootstrap.stage0-posix.mescc-tools
  ];

  M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
  M2_OS = minimalBootstrap.stage0-posix.m2libcOS;

  buildPhase = ''
    runHook preBuild

    cat \
      ${blynnSrc}/inn/BasePrecisely.hs \
      ${blynnSrc}/inn/System.hs \
      src/Hcc/MutableIO.hs \
      ${../tests/hcc/mutable-io}/Main.hs \
      > mutable-demo.hs

    precisely_up < mutable-demo.hs > mutable-demo.c
    sed -i -E 's/enum\{TOP=[0-9]+\};/enum{TOP=134217728};/' mutable-demo.c

    $CC -O0 mutable-demo.c cbits/hcc_runtime.c -o mutable-demo-gcc
    ./mutable-demo-gcc > gcc.out

    M2-Mesoplanet --no-debug --operating-system "$M2_OS" --architecture "$M2_ARCH" \
      -f mutable-demo.c \
      -f cbits/hcc_runtime_m2.c \
      -o mutable-demo-m2 \
      > m2-build.log 2>&1
    chmod +x mutable-demo-m2
    ./mutable-demo-m2 > m2.out

    cmp gcc.out m2.out
    grep -q '^mutable-io: ok$' m2.out

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/mutable-io-proof
    install -Dm555 mutable-demo-gcc $out/bin/mutable-demo-gcc
    install -Dm555 mutable-demo-m2 $out/bin/mutable-demo-m2
    install -Dm644 mutable-demo.hs $out/share/mutable-io-proof/mutable-demo.hs
    install -Dm644 mutable-demo.c $out/share/mutable-io-proof/mutable-demo.c
    install -Dm644 gcc.out $out/share/mutable-io-proof/gcc.out
    install -Dm644 m2.out $out/share/mutable-io-proof/m2.out
    install -Dm644 m2-build.log $out/share/mutable-io-proof/m2-build.log
    runHook postInstall
  '';

  meta = with lib; {
    description = "Proof that MutableIO compiles through Blynn precisely and M2-Mesoplanet";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
