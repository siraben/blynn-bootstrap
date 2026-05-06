{ stdenv, lib, src }:

# Builds blynn-compiler's bootstrap chain using the system C compiler.
#
# The chain is deterministic and runs end-to-end through the vendored
# Makefile, ending with `precisely` (a Haskell-subset compiler).
#
# This is the "trusted compiler" path — we use stdenv's cc rather than
# the M2-Planet seed. Swapping in the seed is a follow-up so we can
# reach precisely from a minimal trusted binary, à la live-bootstrap.

stdenv.mkDerivation {
  pname = "blynn-compiler";
  version = "0-unstable-2026-05-06";

  inherit src;

  enableParallelBuilding = false;

  # Targets explicitly so we don't accidentally pick up a different
  # default in the future.
  buildPhase = ''
    runHook preBuild
    make vm pack_blobs precisely
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/blynn-compiler
    cp bin/vm bin/pack_blobs bin/precisely $out/bin/
    cp bin/marginally bin/methodically bin/crossly $out/bin/
    cp bin/raw $out/share/blynn-compiler/
    cp -r generated $out/share/blynn-compiler/generated
    runHook postInstall
  '';

  meta = with lib; {
    description = "Bootstrapping a Haskell-subset compiler from a single C file";
    homepage = "https://github.com/oriansj/blynn-compiler";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
