{
  lib,
  stdenvNoCC,
  pname,
  precisely,
  sourceBundle,
  commonObjects,
  hcppTop ? 134217728,
  hcc1Top ? 134217728,
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

      mkdir -p source generated
      cp ${sourceBundle}/share/hcc-blynn-sources/hcpp-full.hs source/hcpp-full.hs
      cp ${sourceBundle}/share/hcc-blynn-sources/hcc1-full.hs source/hcc1-full.hs
      cp ${sourceBundle}/share/hcc-blynn-sources/hcpp-tail.hs source/hcpp-tail.hs
      cp ${sourceBundle}/share/hcc-blynn-sources/hcc1-tail.hs source/hcc1-tail.hs

      BOOTSTRAP_LOG_NAME=hcc-blynn-c \
      BOOTSTRAP_LIB=${../scripts/lib/bootstrap.sh} \
      HCC_BLYNN_SOURCES_DIR=source \
      HCC_BLYNN_OBJECTS_DIR=${commonObjects}/share/${commonObjects.pname} \
      PRECISELY_UP=${precisely}/bin/precisely_up \
      HCPP_TOP=${toString hcppTop} \
      HCC1_TOP=${toString hcc1Top} \
      OUT_DIR=generated \
        ${../scripts/hcc-blynn-c.sh}

      cp generated/hcpp-full.hs hcpp-full.hs
      cp generated/hcc1-full.hs hcc1-full.hs
      cp generated/hcpp-tail.hs hcpp-tail.hs
      cp generated/hcc1-tail.hs hcc1-tail.hs
      cp generated/hcpp-blynn.c hcpp-blynn.c
      cp generated/hcc1-blynn.c hcc1-blynn.c
      cp generated/hcpp-object-input.hs hcpp-object-input.hs
      cp generated/hcc1-object-input.hs hcc1-object-input.hs
      log_file hcpp-full.hs
      log_file hcc1-full.hs
      log_file hcpp-tail.hs
      log_file hcc1-tail.hs
      log_file hcpp-object-input.hs
      log_file hcc1-object-input.hs
      log_file hcpp-blynn.c
      log_file hcc1-blynn.c

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm644 hcpp-blynn.c $out/share/${shareName}/hcpp-blynn.c
      install -Dm644 hcc1-blynn.c $out/share/${shareName}/hcc1-blynn.c
      install -Dm644 hcpp-full.hs $out/share/${shareName}/hcpp-full.hs
      install -Dm644 hcc1-full.hs $out/share/${shareName}/hcc1-full.hs
      install -Dm644 hcpp-tail.hs $out/share/${shareName}/hcpp-tail.hs
      install -Dm644 hcc1-tail.hs $out/share/${shareName}/hcc1-tail.hs
      install -Dm644 hcpp-object-input.hs $out/share/${shareName}/hcpp-object-input.hs
      install -Dm644 hcc1-object-input.hs $out/share/${shareName}/hcc1-object-input.hs
      runHook postInstall
    '';

    meta = {
      description = "Generated C for HCC from Blynn precisely";
      platforms = lib.platforms.linux;
      license = lib.licenses.gpl3Only;
    };
  }
)
