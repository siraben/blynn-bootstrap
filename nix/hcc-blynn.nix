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
  dontPatch = true;
  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;
  dontPatchELF = true;
  dontFixup = true;

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
      src/Hcc/TypesToken.hs \
      src/Hcc/SymbolTable.hs \
      src/Hcc/ParseLite.hs \
      src/Hcc/ConstExpr.hs \
      src/Hcc/Lexer.hs \
      src/Hcc/Preprocessor.hs \
      src/Hcc/HccSystem.hs \
      src/Hcc/DriverCommon.hs \
      src/Hcc/IncludeExpand.hs \
      src/MainCpp.hs \
      > hcpp-full.hs
    log_file hcpp-full.hs

    log_step "START concatenate hcc1 Haskell sources"
    cat \
      ${blynnSrc}/inn/BasePrecisely.hs \
      ${blynnSrc}/inn/System.hs \
      src/Hcc/TypesAst.hs \
      src/Hcc/TypesToken.hs \
      src/Hcc/SymbolTable.hs \
      src/Hcc/IntTable.hs \
      src/Hcc/ScopeMap.hs \
      src/Hcc/ParseLite.hs \
      src/Hcc/ConstExpr.hs \
      src/Hcc/Lexer.hs \
      src/Hcc/Parser.hs \
      src/Hcc/TypesIr.hs \
      src/Hcc/CompileM.hs \
      src/Hcc/LowerCommon.hs \
      src/Hcc/TypesLower.hs \
      src/Hcc/LowerBuiltins.hs \
      src/Hcc/LowerDataValues.hs \
      src/Hcc/LowerImplicit.hs \
      src/Hcc/LowerLiterals.hs \
      src/Hcc/LowerParams.hs \
      src/Hcc/LowerBootstrap.hs \
      src/Hcc/LowerSwitchHelpers.hs \
      src/Hcc/LowerTypeInfo.hs \
      src/Hcc/Lower.hs \
      src/Hcc/M1Ir.hs \
      src/Hcc/HccSystem.hs \
      src/Hcc/DriverCommon.hs \
      src/MainCc1.hs \
      > hcc1-full.hs
    log_file hcc1-full.hs

    log_step "precisely_up translates concatenated Blynn-dialect Haskell to C; hcc1 is the long stage"
    run_step_shell "precisely_up hcpp-full.hs -> hcpp-blynn.c" "${precisely}/bin/precisely_up < hcpp-full.hs > hcpp-blynn.c"
    log_file hcpp-blynn.c
    run_step_shell "precisely_up hcc1-full.hs -> hcc1-blynn.c" "${precisely}/bin/precisely_up < hcc1-full.hs > hcc1-blynn.c"
    log_file hcc1-blynn.c

    log_step "START patch generated RTS hcpp TOP=${toString hcppTop}, hcc1 TOP=${toString hcc1Top}"
    substituteInPlace hcpp-blynn.c --replace-fail 'enum{TOP=16777216};' 'enum{TOP=${toString hcppTop}};'
    substituteInPlace hcc1-blynn.c --replace-fail 'enum{TOP=16777216};' 'enum{TOP=${toString hcc1Top}};'
    log_step "DONE  patch generated RTS hcpp TOP=${toString hcppTop}, hcc1 TOP=${toString hcc1Top}"

    log_step "START compile generated C backend"
    ${compileCommand}
    log_step "DONE  compile generated C backend"
    ls -l hcpp hcc1

    run_step_shell "hcpp pp-smoke.c > pp-smoke.i" "./hcpp ${../tests/hcc/pp-smoke.c} > pp-smoke.i"
    log_file pp-smoke.i
    run_step "hcc1 --check pp-smoke.i" ./hcc1 --check pp-smoke.i
    run_step_shell "hcpp parse-smoke.c > parse-smoke.i" "./hcpp ${../tests/hcc/parse-smoke.c} > parse-smoke.i"
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
