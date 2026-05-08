{
  lib,
  mkDerivation,
  pname,
  precisely,
  src,
  blynnSrc,
  compileCommand,
  runtimeFile,
  top,
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

  buildPhase = ''
    runHook preBuild

    ulimit -s unlimited

    log_step() {
      printf 'hcc-blynn: [%s] %s\n' "$(date -u +%H:%M:%S)" "$1"
    }

    run_step() {
      label="$1"
      shift
      log_step "START $label"
      start="$(date +%s)"
      "$@"
      end="$(date +%s)"
      log_step "DONE  $label ($((end - start))s)"
    }

    run_step_shell() {
      label="$1"
      command="$2"
      log_step "START $label"
      start="$(date +%s)"
      eval "$command"
      end="$(date +%s)"
      log_step "DONE  $label ($((end - start))s)"
    }

    log_file() {
      file="$1"
      bytes="$(wc -c < "$file")"
      lines="$(wc -l < "$file")"
      log_step "FILE  $file: $lines lines, $bytes bytes"
    }

    log_step "build inputs: precisely=${precisely} backend=${pname}"
    log_step "stack: ulimit -s unlimited"

    log_step "START concatenate hcpp Haskell sources"
    cat \
      ${blynnSrc}/inn/BasePrecisely.hs \
      ${blynnSrc}/inn/System.hs \
      Hcc/Token.hs \
      Hcc/SymbolTable.hs \
      Hcc/ParseLite.hs \
      Hcc/ConstExpr.hs \
      Hcc/Lexer.hs \
      Hcc/Preprocessor.hs \
      Hcc/HccSystemCpp.hs \
      Hcc/DriverCommonCpp.hs \
      Hcc/IncludeExpand.hs \
      MainCpp.hs \
      > hcpp-full.hs
    log_file hcpp-full.hs

    log_step "START concatenate hcc1 Haskell sources"
    cat \
      ${blynnSrc}/inn/BasePrecisely.hs \
      ${blynnSrc}/inn/System.hs \
      Hcc/Ast.hs \
      Hcc/Token.hs \
      Hcc/SymbolTable.hs \
      Hcc/IntTable.hs \
      Hcc/ParseLite.hs \
      Hcc/ConstExpr.hs \
      Hcc/Lexer.hs \
      Hcc/Parser.hs \
      Hcc/Ir.hs \
      Hcc/CompileM.hs \
      Hcc/LowerCommon.hs \
      Hcc/LowerTypes.hs \
      Hcc/LowerBuiltins.hs \
      Hcc/LowerDataValues.hs \
      Hcc/LowerImplicit.hs \
      Hcc/LowerLiterals.hs \
      Hcc/LowerParams.hs \
      Hcc/LowerBootstrap.hs \
      Hcc/LowerSwitchHelpers.hs \
      Hcc/LowerTypeInfo.hs \
      Hcc/Lower.hs \
      Hcc/TextBuilder.hs \
      Hcc/RegAlloc.hs \
      Hcc/CodegenM1.hs \
      Hcc/HccSystem.hs \
      Hcc/DriverCommon.hs \
      MainCc1.hs \
      > hcc1-full.hs
    log_file hcc1-full.hs

    log_step "precisely_up translates concatenated Blynn-dialect Haskell to C; hcc1 is the long stage"
    run_step_shell "precisely_up hcpp-full.hs -> hcpp-blynn.c" "${precisely}/bin/precisely_up < hcpp-full.hs > hcpp-blynn.c"
    log_file hcpp-blynn.c
    run_step_shell "precisely_up hcc1-full.hs -> hcc1-blynn.c" "${precisely}/bin/precisely_up < hcc1-full.hs > hcc1-blynn.c"
    log_file hcc1-blynn.c

    log_step "START patch generated RTS TOP=${toString top}"
    sed -i -E 's/enum\{TOP=[0-9]+\};/enum{TOP=${toString top}};/' hcpp-blynn.c hcc1-blynn.c
    grep -q 'enum{TOP=${toString top}};' hcpp-blynn.c
    grep -q 'enum{TOP=${toString top}};' hcc1-blynn.c
    log_step "DONE  patch generated RTS TOP=${toString top}"

    log_step "START compile generated C backend"
    ${compileCommand}
    log_step "DONE  compile generated C backend"
    ls -l hcpp hcc1

    run_step_shell "hcpp test/pp-smoke.c > pp-smoke.i" "./hcpp test/pp-smoke.c > pp-smoke.i"
    log_file pp-smoke.i
    run_step "hcc1 --check pp-smoke.i" ./hcc1 --check pp-smoke.i
    run_step_shell "hcpp test/parse-smoke.c > parse-smoke.i" "./hcpp test/parse-smoke.c > parse-smoke.i"
    log_file parse-smoke.i
    run_step "hcc1 --check parse-smoke.i" ./hcc1 --check parse-smoke.i
    run_step "hcc1 -S -o smoke.M1 parse-smoke.i" ./hcc1 -S -o smoke.M1 parse-smoke.i
    log_file smoke.M1

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 hcpp $out/bin/hcpp
    install -Dm555 hcc1 $out/bin/hcc1
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
