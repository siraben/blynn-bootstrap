{
  stdenvNoCC,
  lib,
  minimalBootstrap,
  pname,
  buildScript,
  installScript,
  nativeBuildInputs ? [ ],
  version ? "0-unstable-2026-05-06",
  description ? "Blynn bootstrap stage",
}:

stdenvNoCC.mkDerivation {
  inherit pname version;

  dontUnpack = true;

  nativeBuildInputs = [
    minimalBootstrap.stage0-posix.mescc-tools
  ] ++ nativeBuildInputs;

  M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
  M2_OS = minimalBootstrap.stage0-posix.m2libcOS;

  buildPhase = ''
    runHook preBuild

    mkdir -p build
    cd build

    compile_m2() {
      local src=$1
      local out=$2
      shift 2
      echo "blynn-stage: M2-Mesoplanet $src -> $out"
      M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
        -f "$src" "$@" -o "$out"
      chmod 555 "$out"
    }

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
