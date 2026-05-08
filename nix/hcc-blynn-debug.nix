{
  stdenv,
  lib,
  blynn-precisely-debug-ghc,
  src,
  blynnSrc,
}:

stdenv.mkDerivation {
  pname = "hcc-blynn-debug";
  version = "0-unstable-2026-05-06";

  inherit src;

  buildPhase = ''
    runHook preBuild

    cat \
      ${blynnSrc}/inn/BasePrecisely.hs \
      ${blynnSrc}/inn/System.hs \
      Hcc/Ast.hs \
      Hcc/Token.hs \
      Hcc/SymbolTable.hs \
      Hcc/FingerTree.hs \
      Hcc/ConstExpr.hs \
      Hcc/Lexer.hs \
      Hcc/Parser.hs \
      Hcc/Preprocessor.hs \
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
      Hcc/RegAlloc.hs \
      Hcc/CodegenM1.hs \
      Hcc/HccSystem.hs \
      Main.hs \
      > hcc-full.hs

    ${blynn-precisely-debug-ghc}/bin/precisely_up < hcc-full.hs > hcc-blynn.c
    sed -i -E 's/enum\{TOP=[0-9]+\};/enum{TOP=536870912};/' hcc-blynn.c
    grep -q 'enum{TOP=536870912};' hcc-blynn.c
    $CC -O2 hcc-blynn.c cbits/hcc_runtime.c -o hcc

    ./hcc --check test/parse-smoke.c
    ./hcc --expand-dump test/pp-smoke.c >/dev/null
    ./hcc -S -o smoke.M1 test/parse-smoke.c

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 hcc $out/bin/hcc
    install -Dm644 hcc-blynn.c $out/share/hcc-blynn-debug/hcc-blynn.c
    install -Dm644 hcc-full.hs $out/share/hcc-blynn-debug/hcc-full.hs
    runHook postInstall
  '';

  meta = with lib; {
    description = "HCC compiled by the GHC-built Blynn precisely debug compiler";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
