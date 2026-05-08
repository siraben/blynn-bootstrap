{
  stdenvNoCC,
  lib,
  blynn-precisely,
  minimalBootstrap,
  src,
  blynnSrc,
}:

stdenvNoCC.mkDerivation {
  pname = "hcc-blynn-stage0";
  version = "0-unstable-2026-05-06";

  inherit src;

  nativeBuildInputs = [
    minimalBootstrap.stage0-posix.mescc-tools
  ];

  M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
  M2_OS = minimalBootstrap.stage0-posix.m2libcOS;

  buildPhase = ''
    runHook preBuild

    ulimit -s unlimited

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

    ${blynn-precisely}/bin/precisely_up < hcc-full.hs > hcc-blynn.c
    sed -i -E 's/enum\{TOP=[0-9]+\};/enum{TOP=134217728};/' hcc-blynn.c
    grep -q 'enum{TOP=134217728};' hcc-blynn.c

    M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
      -f hcc-blynn.c \
      -f cbits/hcc_runtime_m2.c \
      -o hcc
    chmod 555 hcc

    ./hcc --lex-dump test/lexer-smoke.c >/dev/null
    ./hcc --pp-dump test/pp-smoke.c >/dev/null
    ./hcc --parse-dump test/parse-smoke.c >/dev/null
    ./hcc --check test/parse-smoke.c
    ./hcc -S -o smoke.M1 test/parse-smoke.c

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 hcc $out/bin/hcc
    install -Dm644 hcc-blynn.c $out/share/hcc-blynn-stage0/hcc-blynn.c
    install -Dm644 hcc-full.hs $out/share/hcc-blynn-stage0/hcc-full.hs
    runHook postInstall
  '';

  meta = with lib; {
    description = "HCC compiled by the stage0-built Blynn precisely and M2-Mesoplanet";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
