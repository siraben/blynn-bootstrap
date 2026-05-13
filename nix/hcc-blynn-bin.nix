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

      mkdir -p cbits test
      cp ${src}/cbits/hcc_runtime.c cbits/hcc_runtime.c
      cp ${src}/cbits/hcc_runtime_m2.c cbits/hcc_runtime_m2.c
      cp ${src}/cbits/hcc_m1.c cbits/hcc_m1.c
      cp ${src}/cbits/hcc_m1_arch_*.c cbits/
      cp ${../tests/hcc/pp-smoke.c} test/pp-smoke.c
      cp ${../tests/hcc/parse-smoke.c} test/parse-smoke.c
      cp ${../tests/hcc/scalar-immediate-smoke.c} test/scalar-immediate-smoke.c
      cp ${../tests/hcc/diagnostics/unknown-identifier.c} test/unknown-identifier.c
      cp ${../tests/hcc/diagnostics/unknown-global-initializer.c} test/unknown-global-initializer.c

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

      run_step_shell "hcpp test/pp-smoke.c > pp-smoke.i" "./hcpp test/pp-smoke.c > pp-smoke.i"
      log_file pp-smoke.i
      run_step "hcc1 --check pp-smoke.i" ./hcc1 --check pp-smoke.i
      run_step_shell "hcpp test/parse-smoke.c > parse-smoke.i" "./hcpp test/parse-smoke.c > parse-smoke.i"
      log_file parse-smoke.i
      run_step "hcc1 --check parse-smoke.i" ./hcc1 --check parse-smoke.i
      run_step "hcc1 --m1-ir -o smoke.hccir parse-smoke.i" ./hcc1 --m1-ir -o smoke.hccir parse-smoke.i
      log_file smoke.hccir
      run_step "hcc-m1 smoke.hccir smoke.M1" ./hcc-m1 smoke.hccir smoke.M1
      log_file smoke.M1
      run_step_shell "hcpp test/scalar-immediate-smoke.c > scalar-immediate-smoke.i" "./hcpp test/scalar-immediate-smoke.c > scalar-immediate-smoke.i"
      log_file scalar-immediate-smoke.i
      run_step "hcc1 --m1-ir -o scalar-immediate-smoke.hccir scalar-immediate-smoke.i" ./hcc1 --m1-ir -o scalar-immediate-smoke.hccir scalar-immediate-smoke.i
      log_file scalar-immediate-smoke.hccir

      expect_file_contains() {
        pattern="$1"
        file="$2"
        found=0
        while IFS= read -r line; do
          case "$line" in
            *"$pattern"*) found=1; break ;;
          esac
        done < "$file"
        if test "$found" != 1; then
          echo "$file: expected diagnostic containing: $pattern" >&2
          exit 1
        fi
      }
      expect_hcc1_fail() {
        name="$1"
        pattern="$2"
        src="$3"
        run_step_shell "hcpp $name" "./hcpp \"$src\" > \"$name.i\""
        log_file "$name.i"
        log_step "START expect hcc1 failure $name"
        set +e
        ./hcc1 --m1-ir -o "$name.hccir" "$name.i" 2> "$name.err"
        code="$?"
        set -e
        log_file "$name.err"
        if test "$code" = 0; then
          echo "$name: expected hcc1 failure" >&2
          exit 1
        fi
        expect_file_contains "$pattern" "$name.err"
        log_step "DONE  expect hcc1 failure $name"
      }
      expect_hcc1_fail unknown-identifier "unknown identifier: missing_global" test/unknown-identifier.c
      expect_hcc1_fail unknown-global-initializer "unknown constant: missing_global" test/unknown-global-initializer.c

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
