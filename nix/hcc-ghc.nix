{
  stdenv,
  lib,
  ghc,
  src,
  pname ? "hcc-host-ghc-native",
  extraGhcFlags ? [ ],
  description ? "GHC-backed development build of the hcc bootstrap C compiler",
}:

let
  nixLib = import ./lib.nix { inherit lib; };
  ghcFlags = lib.concatStringsSep " " (
    [
      "-O0"
      "-Wall"
      "-Werror"
      "-XNoImplicitPrelude"
      "-XForeignFunctionInterface"
    ]
    ++ extraGhcFlags
  );
in
stdenv.mkDerivation (
  {
    inherit pname;
    version = nixLib.bootstrapVersion;

    inherit src;
  }
  // nixLib.skipPatchConfigure
  // {

    nativeBuildInputs = [ ghc ];

    buildPhase = ''
      runHook preBuild
      mkdir -p build/hcpp build/hcc1
      ghc ${ghcFlags} \
        -isrc -isrc/Hcc src/MainCpp.hs cbits/hcc_runtime.c -outputdir build/hcpp -o hcpp
      ghc ${ghcFlags} \
        -isrc -isrc/Hcc src/MainCc1.hs cbits/hcc_runtime.c -outputdir build/hcc1 -o hcc1
      cc -O2 -Wall -Werror cbits/hcc_m1.c -o hcc-m1
      ./hcpp ${../tests/hcc/pp-smoke.c} > pp-smoke.i
      ./hcc1 --check pp-smoke.i
      ./hcpp ${../tests/hcc/parse-smoke.c} > parse-smoke.i
      ./hcc1 --check parse-smoke.i
      ./hcc1 --m1-ir -o smoke.hccir parse-smoke.i
      ./hcc-m1 smoke.hccir smoke-c.M1
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
      inherit description;
      license = licenses.gpl3Only;
      platforms = platforms.linux;
    };
  }
)
