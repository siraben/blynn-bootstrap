{
  lib,
  stdenvNoCC,
  src,
  blynnSrc,
  pname ? "hcc-blynn-sources",
}:

stdenvNoCC.mkDerivation {
  inherit pname src;
  version = "0-unstable-2026-05-06";

  buildPhase = ''
    runHook preBuild

    log_step() {
      printf 'hcc-blynn-sources: [%s] %s\n' "$(date -u +%H:%M:%S)" "$1"
    }

    log_file() {
      file="$1"
      bytes="$(wc -c < "$file")"
      lines="$(wc -l < "$file")"
      log_step "FILE  $file: $lines lines, $bytes bytes"
    }

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
      Hcc/ScopeMap.hs \
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
