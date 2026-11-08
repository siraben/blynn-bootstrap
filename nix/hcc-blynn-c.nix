{
  lib,
  stdenvNoCC,
  pname,
  precisely,
  blynnCompiler ? "${precisely}/bin/precisely_up",
  sourceBundle,
  commonObjects,
  hcppTop ? 134217728,
  hcc1Top ? 134217728,
  bootstrapShell,
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

    buildPhase = ''
      runHook preBuild

      ${nixLib.shellHelpers { name = "hcc-blynn-c"; }}

      BOOTSTRAP_LOG_NAME=hcc-blynn-c \
      BOOTSTRAP_LIB=${../scripts/lib/bootstrap.sh} \
      HCC_BLYNN_SOURCES_DIR=${sourceBundle}/share/hcc-blynn-sources \
      HCC_BLYNN_OBJECTS_DIR=${commonObjects}/share/${commonObjects.pname} \
      BLYNN_COMPILER=${blynnCompiler} \
      HCPP_TOP=${lib.escapeShellArg (toString hcppTop)} \
      HCC1_TOP=${lib.escapeShellArg (toString hcc1Top)} \
      OUT_DIR=generated \
        ${bootstrapShell}/bin/sh ${../scripts/hcc-blynn-c.sh}

      log_file generated/hcpp-full.hs
      log_file generated/hcc1-full.hs
      log_file generated/hcpp-tail.hs
      log_file generated/hcc1-tail.hs
      log_file generated/hcpp-object-input.hs
      log_file generated/hcc1-object-input.hs
      log_file generated/hcpp-blynn.c
      log_file generated/hcc1-blynn.c

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm644 generated/hcpp-blynn.c $out/share/${shareName}/hcpp-blynn.c
      install -Dm644 generated/hcc1-blynn.c $out/share/${shareName}/hcc1-blynn.c
      install -Dm644 generated/hcpp-full.hs $out/share/${shareName}/hcpp-full.hs
      install -Dm644 generated/hcc1-full.hs $out/share/${shareName}/hcc1-full.hs
      install -Dm644 generated/hcpp-tail.hs $out/share/${shareName}/hcpp-tail.hs
      install -Dm644 generated/hcc1-tail.hs $out/share/${shareName}/hcc1-tail.hs
      install -Dm644 generated/hcpp-object-input.hs $out/share/${shareName}/hcpp-object-input.hs
      install -Dm644 generated/hcc1-object-input.hs $out/share/${shareName}/hcc1-object-input.hs
      runHook postInstall
    '';

    meta = {
      description = "Generated C for HCC from Blynn precisely";
      platforms = lib.platforms.linux;
      license = lib.licenses.gpl3Only;
    };
  }
)
