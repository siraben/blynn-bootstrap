{
  stdenvNoCC,
  lib,
  minimalBootstrap,
  pname,
  buildScript,
  installScript,
  nativeBuildInputs ? [ ],
  m2Mesoplanet ? null,
  version ? "0-unstable-2026-05-06",
  description ? "Blynn bootstrap stage",
}:

let
  nixLib = import ./lib.nix { inherit lib; };
in
stdenvNoCC.mkDerivation (
  {
    inherit pname version;
  }
  // nixLib.scriptOnly
  // {

    nativeBuildInputs = [
      minimalBootstrap.stage0-posix.mescc-tools
    ]
    ++ lib.optional (m2Mesoplanet != null) m2Mesoplanet
    ++ nativeBuildInputs;

    M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
    M2_OS = minimalBootstrap.stage0-posix.m2libcOS;

    buildPhase = ''
      runHook preBuild

      ulimit -s unlimited

      mkdir -p build
      cd build
      mkdir -p tmp
      export TMPDIR="$PWD/tmp"
      ${lib.optionalString (m2Mesoplanet != null) ''
        export M2_MESOPLANET=${m2Mesoplanet}/bin/M2-Mesoplanet
      ''}

      . ${../scripts/lib/bootstrap.sh}

      ${buildScript}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/share/blynn"
      ${installScript}
      runHook postInstall
    '';

    meta = with lib; {
      inherit description;
      homepage = "https://github.com/blynn/compiler";
      license = licenses.gpl3Only;
      platforms = platforms.linux;
    };
  }
)
