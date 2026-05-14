{
  stdenv,
  lib,
  microhs,
  src,
  pname ? "hcc-host-microhs-native",
  extraCFlags ? [ ],
  description ? "MicroHs-backed development build of the hcc bootstrap C compiler",
}:

let
  nixLib = import ./lib.nix { inherit lib; };
  cFlags = lib.concatStringsSep " " (
    [
      "-O2"
      "-U_FORTIFY_SOURCE"
      "-Wall"
      "-Werror"
    ]
    ++ extraCFlags
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

    nativeBuildInputs = [ microhs ];
    hardeningDisable = [ "fortify" ];

    buildPhase = ''
      runHook preBuild
      export MHSDIR=${microhs}/lib/mhs

      mhs -isrc -isrc/Hcc src/MainCpp.hs \
        -optc -DSTACK_SIZE=1000000 \
        -optc -Wno-error=implicit-function-declaration \
        -optl cbits/hcc_runtime.c \
        -o hcpp
      mhs -isrc -isrc/Hcc src/MainCc1.hs \
        -optc -DSTACK_SIZE=1000000 \
        -optc -Wno-error=implicit-function-declaration \
        -optl cbits/hcc_runtime.c \
        -o hcc1
      cc ${cFlags} cbits/hcc_m1.c -o hcc-m1
      (
        export HCPP=./hcpp
        export HCC1=./hcc1
        export HCC_M1=./hcc-m1
        export TESTS_DIR=${../tests/hcc}
        . ${../scripts/hcc-compiler-smoke.sh}
      )
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
