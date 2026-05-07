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
    ./hcc --lex-dump test/lexer-smoke.c >/dev/null
    ./hcc --pp-dump test/pp-smoke.c >/dev/null
    ./hcc --parse-dump test/parse-smoke.c >/dev/null
    ./hcc --check test/parse-smoke.c
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
