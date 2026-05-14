{
  lib,
  stdenvNoCC,
  src,
  blynnSrc,
  kaem,
  bootstrapShell,
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

      cat > hcc-blynn-sources.kaem <<'EOF'
      ${bootstrapShell}/bin/sh ${../scripts/hcc-blynn-sources.sh}
      EOF
      BOOTSTRAP_LOG_NAME=hcc-blynn-sources \
      BOOTSTRAP_LIB=${../scripts/lib/bootstrap.sh} \
      HCC_DIR=${src} \
      BLYNN_DIR=${blynnSrc} \
      OUT_DIR=. \
        ${kaem}/bin/kaem --verbose --strict --file hcc-blynn-sources.kaem
      log_file hcpp-full.hs
      log_file hcc1-full.hs

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm644 hcpp-full.hs $out/share/hcc-blynn-sources/hcpp-full.hs
      install -Dm644 hcc1-full.hs $out/share/hcc-blynn-sources/hcc1-full.hs
      runHook postInstall
    '';

    meta = {
      description = "Concatenated Blynn-dialect Haskell sources for HCC";
      platforms = lib.platforms.linux;
      license = lib.licenses.gpl3Only;
    };
  }
)
