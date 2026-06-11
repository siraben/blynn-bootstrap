{
  stdenvNoCC,
  lib,
  hcc,
  coreutils,
  diffutils,
  gnused,
  pname ? "hcc-golden-tests",
}:

let
  nixLib = import ./lib.nix { inherit lib; };
in
stdenvNoCC.mkDerivation (
  {
    inherit pname;
    version = nixLib.bootstrapVersion;
  }
  // nixLib.scriptOnly
  // {

    nativeBuildInputs = [
      hcc
      coreutils
      diffutils
      gnused
    ];

    buildPhase = ''
      runHook preBuild

      export HCPP=${hcc}/bin/hcpp
      export HCC1=${hcc}/bin/hcc1
      export HCC_M1=${hcc}/bin/hcc-m1
      sh ${../tests/hcc/golden/run.sh} ${../tests/hcc/golden}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/hcc-golden"
      cp -R ${../tests/hcc/golden}/expected "$out/share/hcc-golden/"
      runHook postInstall
    '';

    meta = with lib; {
      description = "Golden tests for hcc phase boundary text outputs";
      license = licenses.gpl3Only;
      platforms = platforms.linux;
    };
  }
)
