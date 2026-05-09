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
      ${src}/src/Hcc/TypesToken.hs \
      ${src}/src/Hcc/SymbolTable.hs \
      ${src}/src/Hcc/ParseLite.hs \
      ${src}/src/Hcc/ConstExpr.hs \
      ${src}/src/Hcc/Lexer.hs \
      ${src}/src/Hcc/Preprocessor.hs \
      ${src}/src/Hcc/HccSystem.hs \
      ${src}/src/Hcc/DriverCommon.hs \
      ${src}/src/Hcc/IncludeExpand.hs \
      ${src}/src/MainCpp.hs \
      > hcpp-full.hs
    log_file hcpp-full.hs

    log_step "START concatenate hcc1 Haskell sources"
    cat \
      ${blynnSrc}/inn/BasePrecisely.hs \
      ${blynnSrc}/inn/System.hs \
      ${src}/src/Hcc/TypesAst.hs \
      ${src}/src/Hcc/TypesToken.hs \
      ${src}/src/Hcc/SymbolTable.hs \
      ${src}/src/Hcc/IntTable.hs \
      ${src}/src/Hcc/ScopeMap.hs \
      ${src}/src/Hcc/ParseLite.hs \
      ${src}/src/Hcc/ConstExpr.hs \
      ${src}/src/Hcc/Lexer.hs \
      ${src}/src/Hcc/Parser.hs \
      ${src}/src/Hcc/TypesIr.hs \
      ${src}/src/Hcc/CompileM.hs \
      ${src}/src/Hcc/LowerCommon.hs \
      ${src}/src/Hcc/TypesLower.hs \
      ${src}/src/Hcc/LowerBuiltins.hs \
      ${src}/src/Hcc/LowerDataValues.hs \
      ${src}/src/Hcc/LowerImplicit.hs \
      ${src}/src/Hcc/LowerLiterals.hs \
      ${src}/src/Hcc/LowerParams.hs \
      ${src}/src/Hcc/LowerBootstrap.hs \
      ${src}/src/Hcc/LowerSwitchHelpers.hs \
      ${src}/src/Hcc/LowerTypeInfo.hs \
      ${src}/src/Hcc/Lower.hs \
      ${src}/src/Hcc/M1Ir.hs \
      ${src}/src/Hcc/HccSystem.hs \
      ${src}/src/Hcc/DriverCommon.hs \
      ${src}/src/MainCc1.hs \
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
