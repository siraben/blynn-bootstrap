{
  lib,
  stdenvNoCC,
  src,
  blynnSrc,
  pname ? "hcc-blynn-sources",
}:

let
  nixLib = import ./lib.nix { inherit lib; };
in
stdenvNoCC.mkDerivation (
  {
    inherit pname src;
    version = nixLib.bootstrapVersion;
  }
  // nixLib.scriptOnly
  // {

    buildPhase = ''
      runHook preBuild

      ${nixLib.shellHelpers { name = "hcc-blynn-sources"; }}

      BOOTSTRAP_LOG_NAME=hcc-blynn-sources \
      BOOTSTRAP_LIB=${../scripts/lib/bootstrap.sh} \
      HCC_DIR=${src} \
      BLYNN_DIR=${blynnSrc} \
      OUT_DIR=. \
        ${../scripts/hcc-blynn-sources.sh}
      log_file hcc-common-full.hs
      log_file hcpp-full.hs
      log_file hcc1-full.hs
      log_file hcpp-tail.hs
      log_file hcc1-tail.hs

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm644 hcc-common-full.hs $out/share/hcc-blynn-sources/hcc-common-full.hs
      install -Dm644 hcpp-full.hs $out/share/hcc-blynn-sources/hcpp-full.hs
      install -Dm644 hcc1-full.hs $out/share/hcc-blynn-sources/hcc1-full.hs
      install -Dm644 hcpp-tail.hs $out/share/hcc-blynn-sources/hcpp-tail.hs
      install -Dm644 hcc1-tail.hs $out/share/hcc-blynn-sources/hcc1-tail.hs
      runHook postInstall
    '';

    meta = {
      description = "Concatenated Blynn-dialect Haskell sources for HCC";
      platforms = lib.platforms.linux;
      license = lib.licenses.gpl3Only;
    };
  }
)
