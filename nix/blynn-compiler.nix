{
  stdenvNoCC,
  lib,
  minimalBootstrap,
  src,
}:

# Builds blynn-compiler's bootstrap chain using nixpkgs' minimal-bootstrap.
#
# The M2/hex2 build recipe comes from the older siraben/mes-overlay package,
# but the tool inputs come from the current minimal-bootstrap scope so this
# package shares the same seed/toolchain lineage as nixpkgs.

stdenvNoCC.mkDerivation {
  pname = "blynn-compiler";
  version = "0-unstable-2026-05-06";

  inherit src;

  nativeBuildInputs = [ minimalBootstrap.stage0-posix.mescc-tools ];

  M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
  M2_OS = minimalBootstrap.stage0-posix.m2libcOS;

  postPatch = ''
    patchShebangs go.sh
  '';

  buildPhase = ''
    runHook preBuild
    ./go.sh
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
