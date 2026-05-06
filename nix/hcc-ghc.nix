{
  stdenv,
  lib,
  ghc,
  src,
}:

stdenv.mkDerivation {
  pname = "hcc-ghc";
  version = "0-unstable-2026-05-06";

  inherit src;

  nativeBuildInputs = [ ghc ];

  buildPhase = ''
    runHook preBuild
    mkdir -p build
    ghc -Wall -Werror -i. Main.hs -outputdir build -o hcc
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 hcc $out/bin/hcc
    runHook postInstall
  '';

  meta = with lib; {
    description = "GHC-backed development build of the hcc bootstrap C compiler";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
