{
  stdenv,
  lib,
  ghc,
  src,
  pname ? "hcc-profile-host-ghc-native",
}:

stdenv.mkDerivation {
  inherit pname;
  version = "0-unstable-2026-05-06";

  inherit src;

  nativeBuildInputs = [ ghc ];

  buildPhase = ''
    runHook preBuild
    mkdir -p build/hcpp build/hcc1
    ghc -O0 -prof -fprof-auto -rtsopts -Wall -Werror \
      -XNoImplicitPrelude -XForeignFunctionInterface \
      -i. -iHcc MainCpp.hs cbits/hcc_runtime.c -outputdir build/hcpp -o hcpp
    ghc -O0 -prof -fprof-auto -rtsopts -Wall -Werror \
      -XNoImplicitPrelude -XForeignFunctionInterface \
      -i. -iHcc MainCc1.hs cbits/hcc_runtime.c -outputdir build/hcc1 -o hcc1
    ./hcpp test/pp-smoke.c > pp-smoke.i
    ./hcc1 --check pp-smoke.i
    ./hcpp test/parse-smoke.c > parse-smoke.i
    ./hcc1 --check parse-smoke.i
    ./hcc1 -S -o smoke.M1 parse-smoke.i
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 hcpp $out/bin/hcpp
    install -Dm555 hcc1 $out/bin/hcc1
    runHook postInstall
  '';

  meta = with lib; {
    description = "Profiling build of the GHC-backed hcc bootstrap C compiler";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
