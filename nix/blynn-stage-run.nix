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
  dontPatch = true;
  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;
  dontFixup = true;
  dontPatchELF = true;

  nativeBuildInputs = [
    minimalBootstrap.stage0-posix.mescc-tools
  ] ++ nativeBuildInputs;

  M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
  M2_OS = minimalBootstrap.stage0-posix.m2libcOS;

  buildPhase = ''
    runHook preBuild

    ulimit -s unlimited

    mkdir -p build
    cd build
    mkdir -p tmp
    export TMPDIR="$PWD/tmp"

    compile_m2() {
      src=$1
      output_file=$2
      shift 2
      echo "blynn-stage: M2-Mesoplanet $src -> $output_file"
      M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
        -f "$src" "$@" -o "$output_file"
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
