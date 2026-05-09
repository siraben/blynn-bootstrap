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

  dontUnpack = true;
  dontPatch = true;
  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;
  dontFixup = true;
  dontPatchELF = true;

  buildPhase = ''
    runHook preBuild

    log_step() {
      printf 'hcc-blynn-sources: %s\n' "$1"
    }

    log_file() {
      file="$1"
      log_step "FILE  $file"
    }

    log_step "START concatenate hcpp Haskell sources"
    cat \
      ${blynnSrc}/inn/BasePrecisely.hs \
      ${blynnSrc}/inn/System.hs \
      ${src}/Hcc/Token.hs \
      ${src}/Hcc/SymbolTable.hs \
      ${src}/Hcc/ParseLite.hs \
      ${src}/Hcc/ConstExpr.hs \
      ${src}/Hcc/Lexer.hs \
      ${src}/Hcc/Preprocessor.hs \
      ${src}/Hcc/HccSystemCpp.hs \
      ${src}/Hcc/DriverCommonCpp.hs \
      ${src}/Hcc/IncludeExpand.hs \
      ${src}/MainCpp.hs \
      > hcpp-full.hs
    log_file hcpp-full.hs

    log_step "START concatenate hcc1 Haskell sources"
    cat \
      ${blynnSrc}/inn/BasePrecisely.hs \
      ${blynnSrc}/inn/System.hs \
      ${src}/Hcc/Ast.hs \
      ${src}/Hcc/Token.hs \
      ${src}/Hcc/SymbolTable.hs \
      ${src}/Hcc/ScopeMap.hs \
      ${src}/Hcc/IntTable.hs \
      ${src}/Hcc/ParseLite.hs \
      ${src}/Hcc/ConstExpr.hs \
      ${src}/Hcc/Lexer.hs \
      ${src}/Hcc/Parser.hs \
      ${src}/Hcc/Ir.hs \
      ${src}/Hcc/CompileM.hs \
      ${src}/Hcc/LowerCommon.hs \
      ${src}/Hcc/LowerTypes.hs \
      ${src}/Hcc/LowerBuiltins.hs \
      ${src}/Hcc/LowerDataValues.hs \
      ${src}/Hcc/LowerImplicit.hs \
      ${src}/Hcc/LowerLiterals.hs \
      ${src}/Hcc/LowerParams.hs \
      ${src}/Hcc/LowerBootstrap.hs \
      ${src}/Hcc/LowerSwitchHelpers.hs \
      ${src}/Hcc/LowerTypeInfo.hs \
      ${src}/Hcc/Lower.hs \
      ${src}/Hcc/TextBuilder.hs \
      ${src}/Hcc/RegAlloc.hs \
      ${src}/Hcc/CodegenM1.hs \
      ${src}/Hcc/M1Ir.hs \
      ${src}/Hcc/HccSystem.hs \
      ${src}/Hcc/DriverCommon.hs \
      ${src}/MainCc1.hs \
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
