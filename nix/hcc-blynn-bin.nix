{
  lib,
  mkDerivation,
  pname,
  generatedC,
  src,
  bootstrapShell,
  scriptEnv,
  runtimeFile,
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

      ${nixLib.shellHelpers { name = "hcc-blynn-bin"; }}

      log_file ${generatedC}/share/${generatedC.pname}/hcpp-blynn.c
      log_file ${generatedC}/share/${generatedC.pname}/hcc1-blynn.c

      log_step "START portable hcc-blynn-bin script"
      BOOTSTRAP_LOG_NAME=hcc-blynn-bin \
      BOOTSTRAP_LIB=${../scripts/lib/bootstrap.sh} \
      HCC_BLYNN_C_DIR=${generatedC}/share/${generatedC.pname} \
      HCC_DIR=${src} \
      OUT_DIR=generated \
      ${scriptEnv} \
        ${bootstrapShell}/bin/sh ${../scripts/hcc-blynn-bin.sh}
      log_step "DONE  portable hcc-blynn-bin script"
      log_step "compiled hcpp and hcc1"

      (
        export HCPP=$PWD/generated/bin/hcpp
        export HCC1=$PWD/generated/bin/hcc1
        export HCC_M1=$PWD/generated/bin/hcc-m1
        export TESTS_DIR=${../tests/hcc}
        export LOG_PREFIX=hcc-blynn-bin-smoke
        . ${../scripts/hcc-compiler-smoke.sh}
      )

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm555 generated/bin/hcpp $out/libexec/${shareName}/hcpp
      install -Dm555 generated/bin/hcc1 $out/libexec/${shareName}/hcc1
      install -Dm555 generated/bin/hcc-m1 $out/libexec/${shareName}/hcc-m1
      install_stack_wrapper() {
        name="$1"
        mkdir -p "$out/bin"
        printf '%s\n' \
          '#!/bin/sh' \
          'ulimit -s unlimited 2>/dev/null || true' \
          "exec \"$out/libexec/${shareName}/$name\" \"\$@\"" \
          > "$out/bin/$name"
        chmod 555 "$out/bin/$name"
      }
      install_stack_wrapper hcpp
      install_stack_wrapper hcc1
      install_stack_wrapper hcc-m1
      install -Dm644 generated/artifact/hcpp-blynn.patched.c $out/share/${shareName}/hcpp-blynn.c
      install -Dm644 generated/artifact/hcc1-blynn.patched.c $out/share/${shareName}/hcc1-blynn.c
      install -Dm644 ${generatedC}/share/${generatedC.pname}/hcpp-full.hs $out/share/${shareName}/hcpp-full.hs
      install -Dm644 ${generatedC}/share/${generatedC.pname}/hcc1-full.hs $out/share/${shareName}/hcc1-full.hs
      install -Dm644 ${src}/${runtimeFile} $out/share/${shareName}/hcc-runtime.c
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
