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
  nativeBuildInputs ? [],
  m2Arch ? null,
  m2Os ? null,
  description,
  metaPlatforms ? lib.platforms.linux,
}:

mkDerivation ({
  inherit pname src nativeBuildInputs;
  version = "0-unstable-2026-05-06";
  dontUnpack = true;
  dontPatch = true;
  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;
  dontPatchELF = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild

    ulimit -s unlimited

    mkdir -p cbits test
    cp ${src}/cbits/hcc_runtime.c cbits/hcc_runtime.c
    cp ${src}/cbits/hcc_runtime_m2.c cbits/hcc_runtime_m2.c
    cp ${src}/cbits/hcc_m1.c cbits/hcc_m1.c
    cp ${../tests/hcc/pp-smoke.c} test/pp-smoke.c
    cp ${../tests/hcc/parse-smoke.c} test/parse-smoke.c

    log_step() {
      printf 'hcc-blynn-bin: %s\n' "$1"
    }

    run_step() {
      label="$1"
      shift
      log_step "START $label"
      "$@"
      log_step "DONE  $label"
    }

    run_step_shell() {
      label="$1"
      command="$2"
      log_step "START $label"
      eval "$command"
      log_step "DONE  $label"
    }

    log_file() {
      file="$1"
      log_step "FILE  $file"
    }

    cp ${generatedC}/share/${generatedC.pname}/hcpp-blynn.c hcpp-blynn.c
    cp ${generatedC}/share/${generatedC.pname}/hcc1-blynn.c hcc1-blynn.c
    cp ${generatedC}/share/${generatedC.pname}/hcpp-full.hs hcpp-full.hs
    cp ${generatedC}/share/${generatedC.pname}/hcc1-full.hs hcc1-full.hs
    log_file hcpp-blynn.c
    log_file hcc1-blynn.c

    log_step "START patch generated RTS hcpp TOP=${toString hcppTop}, hcc1 TOP=${toString hcc1Top}"
    substituteInPlace hcpp-blynn.c --replace-fail 'enum{TOP=16777216};' 'enum{TOP=${toString hcppTop}};'
    substituteInPlace hcc1-blynn.c --replace-fail 'enum{TOP=16777216};' 'enum{TOP=${toString hcc1Top}};'
    log_step "DONE  patch generated RTS hcpp TOP=${toString hcppTop}, hcc1 TOP=${toString hcc1Top}"

    log_step "START compile generated C backend"
    ${compileCommand}
    log_step "DONE  compile generated C backend"
    log_step "compiled hcpp and hcc1"

    run_step_shell "hcpp test/pp-smoke.c > pp-smoke.i" "./hcpp test/pp-smoke.c > pp-smoke.i"
    log_file pp-smoke.i
    run_step "hcc1 --check pp-smoke.i" ./hcc1 --check pp-smoke.i
    run_step_shell "hcpp test/parse-smoke.c > parse-smoke.i" "./hcpp test/parse-smoke.c > parse-smoke.i"
    log_file parse-smoke.i
    run_step "hcc1 --check parse-smoke.i" ./hcc1 --check parse-smoke.i
    run_step "hcc1 --m1-ir -o smoke.hccir parse-smoke.i" ./hcc1 --m1-ir -o smoke.hccir parse-smoke.i
    log_file smoke.hccir
    run_step "hcc-m1 smoke.hccir smoke-c.M1" ./hcc-m1 smoke.hccir smoke-c.M1
    log_file smoke-c.M1

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
} // lib.optionalAttrs (m2Arch != null) {
  M2_ARCH = m2Arch;
  M2_OS = m2Os;
})
