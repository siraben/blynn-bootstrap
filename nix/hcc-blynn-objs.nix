{
  lib,
  minimalBootstrap,
  stdenvNoCC,
  pname,
  precisely,
  sourceBundle,
  shareName ? pname,
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
      minimalBootstrap.stage0-posix.mescc-tools
    ];

    M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
    M2_OS = minimalBootstrap.stage0-posix.m2libcOS;
    M2LIBC_PATH = "${minimalBootstrap.stage0-posix.src}/M2libc";

    buildPhase = ''
      runHook preBuild

      ${nixLib.shellHelpers { name = "hcc-blynn-objs"; }}
      . ${../scripts/lib/bootstrap.sh}

      compile_m2 ${../hcc/support/materialize-object-script.c} materialize-object-script

      mkdir -p source generated
      cp ${sourceBundle}/share/hcc-blynn-sources/hcc-common-full.hs source/hcc-common-full.hs

      BOOTSTRAP_LOG_NAME=hcc-blynn-objs \
      BOOTSTRAP_LIB=${../scripts/lib/bootstrap.sh} \
      HCC_BLYNN_SOURCES_DIR=source \
      MATERIALIZE_OBJECT_SCRIPT=$PWD/materialize-object-script \
      PRECISELY_UP=${precisely}/bin/precisely_up \
      OUT_DIR=generated \
        ${../scripts/hcc-blynn-objs.sh}

      cp generated/hcc-common-full.hs hcc-common-full.hs
      cp generated/common-object-input.hs common-object-input.hs
      cp generated/common-objects.sh common-objects.sh
      mkdir -p common-objects
      cp generated/common-objects/*.ob common-objects/
      log_file hcc-common-full.hs
      log_file common-object-input.hs

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm644 hcc-common-full.hs $out/share/${shareName}/hcc-common-full.hs
      install -Dm644 common-object-input.hs $out/share/${shareName}/common-object-input.hs
      install -Dm644 common-objects.sh $out/share/${shareName}/common-objects.sh
      mkdir -p $out/share/${shareName}/common-objects
      cp common-objects/*.ob $out/share/${shareName}/common-objects/
      runHook postInstall
    '';

    meta = {
      description = "Serialized Blynn object IR for common HCC modules";
      platforms = lib.platforms.linux;
      license = lib.licenses.gpl3Only;
    };
  }
)
