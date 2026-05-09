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

  dontPatch = true;
  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;

  nativeBuildInputs = [ ghc ];

  buildPhase = ''
    runHook preBuild
    mkdir -p build/hcpp build/hcc1
    ghc -O0 -Wall -Werror -XNoImplicitPrelude -XForeignFunctionInterface \
      -isrc -isrc/Hcc src/MainCpp.hs cbits/hcc_runtime.c -outputdir build/hcpp -o hcpp
    ghc -O0 -Wall -Werror -XNoImplicitPrelude -XForeignFunctionInterface \
      -isrc -isrc/Hcc src/MainCc1.hs cbits/hcc_runtime.c -outputdir build/hcc1 -o hcc1
    cc -O2 -Wall -Werror cbits/hcc_m1.c -o hcc-m1
    ./hcpp ${../tests/hcc/pp-smoke.c} > pp-smoke.i
    ./hcc1 --check pp-smoke.i
    ./hcpp ${../tests/hcc/parse-smoke.c} > parse-smoke.i
    ./hcc1 --check parse-smoke.i
    ./hcc1 -S -o smoke.M1 parse-smoke.i
    ./hcc1 --m1-ir -o smoke.hccir parse-smoke.i
    ./hcc-m1 smoke.hccir smoke-c.M1
    cmp smoke.M1 smoke-c.M1
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 hcpp $out/bin/hcpp
    install -Dm555 hcc1 $out/bin/hcc1
    install -Dm555 hcc-m1 $out/bin/hcc-m1
    runHook postInstall
  '';

  meta = with lib; {
    description = "GHC-backed development build of the hcc bootstrap C compiler";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
