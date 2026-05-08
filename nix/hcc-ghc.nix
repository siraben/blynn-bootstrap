{
  stdenv,
  lib,
  ghc,
  src,
  pname ? "hcc-host-ghc-native",
}:

stdenv.mkDerivation {
  inherit pname;
  version = "0-unstable-2026-05-06";

  inherit src;

  nativeBuildInputs = [ ghc ];

  buildPhase = ''
    runHook preBuild
    mkdir -p build
    ghc -O0 -Wall -Werror -XNoImplicitPrelude -XForeignFunctionInterface \
      -i. -iHcc Main.hs cbits/hcc_runtime.c -outputdir build -o hcc
    ./hcc --check test/parse-smoke.c
    ./hcc --expand-dump test/pp-smoke.c >/dev/null
    ./hcc -S -o smoke.M1 test/parse-smoke.c
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
