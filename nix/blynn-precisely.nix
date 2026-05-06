{
  stdenvNoCC,
  lib,
  blynn-compiler,
  minimalBootstrap,
  src,
}:

# Builds the upstream blynn/compiler party→precisely chain on top of
# orians' methodically. Result: an upstream-flavoured `precisely` capable
# of compiling the modular inn/ Haskell sources.
#
# The chain (per upstream's Makefile):
#   methodically(party.hs)  -> party.c    -> party
#   party(...inn+party.hs)  -> multiparty.c -> multiparty
#   multiparty(...)         -> party1.c     -> party1
#   party1(...)             -> party2.c     -> party2
#   party2(...)             -> crossly.c    -> crossly_up
#   crossly_up(...)         -> crossly1.c   -> crossly1
#   crossly1(...)           -> precisely.c  -> precisely_up
#
# `party.c` is post-processed once to swap methodically's argc==3 file
# convention for stdin/stdout, since upstream's `party` binary expects
# `cat ... | party > out`. From `party` onwards each binary emits its
# own main and the patch isn't needed.

stdenvNoCC.mkDerivation {
  pname = "blynn-precisely";
  version = "0-unstable-2026-05-06";

  inherit src;

  nativeBuildInputs = [
    blynn-compiler
    minimalBootstrap.stage0-posix.mescc-tools
  ];

  enableParallelBuilding = false;

  M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
  M2_OS = minimalBootstrap.stage0-posix.m2libcOS;

  buildPhase = ''
    runHook preBuild
    export METHODICALLY=${blynn-compiler}/bin/methodically
    export UPSTREAM_DIR=$PWD
    bash ./build-party-chain.sh
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/blynn-precisely
    cp party multiparty party1 party2 crossly_up crossly1 precisely_up $out/bin/
    cp party.c multiparty.c party1.c party2.c crossly_up.c crossly1.c precisely_up.c \
      $out/share/blynn-precisely/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Upstream blynn/compiler party→precisely chain, bootstrapped via orians' methodically";
    homepage = "https://github.com/blynn/compiler";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
