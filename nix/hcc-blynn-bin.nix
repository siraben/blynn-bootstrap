{
  lib,
  mkDerivation,
  pname,
  generatedC,
  src,
  kaem,
  bootstrapShell,
  scriptEnv,
  runtimeFile,
  top,
  hcppTop ? top,
  hcc1Top ? top,
  shareName ? pname,
  nativeBuildInputs ? [ ],
  m2Arch ? null,
  m2Os ? null,
  description,
  metaPlatforms ? lib.platforms.linux,
}:

let
  nixLib = import ./lib.nix { inherit lib; };
in
mkDerivation (
  {
    inherit pname src nativeBuildInputs;
    version = nixLib.bootstrapVersion;
  }
  // nixLib.scriptOnly
  // {

    buildPhase = ''
      runHook preBuild

      ulimit -s unlimited

      mkdir -p cbits source generated
      cp ${src}/cbits/hcc_runtime.c cbits/hcc_runtime.c
      cp ${src}/cbits/hcc_runtime_m2.c cbits/hcc_runtime_m2.c
      cp ${src}/cbits/hcc_m1.c cbits/hcc_m1.c
      cp ${src}/cbits/hcc_m1_arch_*.c cbits/

      ${nixLib.shellHelpers { name = "hcc-blynn-bin"; }}

      cp ${generatedC}/share/${generatedC.pname}/hcpp-blynn.c hcpp-blynn.c
      cp ${generatedC}/share/${generatedC.pname}/hcc1-blynn.c hcc1-blynn.c
      cp ${generatedC}/share/${generatedC.pname}/hcpp-full.hs hcpp-full.hs
      cp ${generatedC}/share/${generatedC.pname}/hcc1-full.hs hcc1-full.hs
      log_file hcpp-blynn.c
      log_file hcc1-blynn.c

      cp hcpp-blynn.c source/hcpp-blynn.c
      cp hcc1-blynn.c source/hcc1-blynn.c

      cat > hcc-blynn-bin.kaem <<'EOF'
      ${bootstrapShell}/bin/sh ${../scripts/hcc-blynn-bin.sh}
      EOF
      log_step "START portable hcc-blynn-bin script via kaem"
      BOOTSTRAP_LOG_NAME=hcc-blynn-bin \
      BOOTSTRAP_LIB=${../scripts/lib/bootstrap.sh} \
      HCC_BLYNN_C_DIR=source \
      HCC_DIR=${src} \
      HCPP_TOP=${toString hcppTop} \
      HCC1_TOP=${toString hcc1Top} \
      OUT_DIR=generated \
      ${scriptEnv} \
        ${kaem}/bin/kaem --verbose --strict --file hcc-blynn-bin.kaem
      log_step "DONE  portable hcc-blynn-bin script via kaem"
      log_step "compiled hcpp and hcc1"

      chmod u+w hcpp-blynn.c hcc1-blynn.c
      cp generated/artifact/hcpp-blynn.patched.c hcpp-blynn.c
      cp generated/artifact/hcc1-blynn.patched.c hcc1-blynn.c
      cp generated/bin/hcpp hcpp
      cp generated/bin/hcc1 hcc1
      cp generated/bin/hcc-m1 hcc-m1
      chmod 555 hcpp hcc1 hcc-m1

      (
        export HCPP=./hcpp
        export HCC1=./hcc1
        export HCC_M1=./hcc-m1
        export TESTS_DIR=${../tests/hcc}
        export LOG_PREFIX=hcc-blynn-bin-smoke
        . ${../scripts/hcc-compiler-smoke.sh}
      )

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm555 hcpp $out/bin/hcpp
      install -Dm555 hcc1 $out/bin/hcc1
      install -Dm555 hcc-m1 $out/bin/hcc-m1
      install -Dm644 hcpp-blynn.c $out/share/${shareName}/hcpp-blynn.c
      install -Dm644 hcc1-blynn.c $out/share/${shareName}/hcc1-blynn.c
      install -Dm644 hcpp-full.hs $out/share/${shareName}/hcpp-full.hs
      install -Dm644 hcc1-full.hs $out/share/${shareName}/hcc1-full.hs
      install -Dm644 ${runtimeFile} $out/share/${shareName}/hcc-runtime.c
      runHook postInstall
    '';

    meta = {
      inherit description;
      platforms = metaPlatforms;
      license = lib.licenses.gpl3Only;
    };
  }
  // lib.optionalAttrs (m2Arch != null) {
    M2_ARCH = m2Arch;
    M2_OS = m2Os;
  }
)
