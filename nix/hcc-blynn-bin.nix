{
  lib,
  mkDerivation,
  pname,
  generatedC,
  src,
  compileCommand,
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

      mkdir -p cbits
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

      log_step "START patch generated RTS hcpp TOP=${toString hcppTop}, hcc1 TOP=${toString hcc1Top}"
      ${nixLib.patchGeneratedTop "hcpp-blynn.c" hcppTop}
      ${nixLib.patchGeneratedTop "hcc1-blynn.c" hcc1Top}
      log_step "DONE  patch generated RTS hcpp TOP=${toString hcppTop}, hcc1 TOP=${toString hcc1Top}"

      log_step "START compile generated C backend"
      ${compileCommand}
      log_step "DONE  compile generated C backend"
      log_step "compiled hcpp and hcc1"

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
