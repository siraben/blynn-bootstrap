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

    cat \
      ${blynnSrc}/inn/BasePrecisely.hs \
      ${blynnSrc}/inn/System.hs \
      Hcc/Ast.hs \
      Hcc/Token.hs \
      Hcc/SymbolTable.hs \
      Hcc/FingerTree.hs \
      Hcc/ParseLite.hs \
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

    ${precisely}/bin/precisely_up < hcc-full.hs > hcc-blynn.c
    sed -i -E 's/enum\{TOP=[0-9]+\};/enum{TOP=${toString top}};/' hcc-blynn.c
    grep -q 'enum{TOP=${toString top}};' hcc-blynn.c

    ${compileCommand}

    ./hcc --check test/parse-smoke.c
    ./hcc --expand-dump test/pp-smoke.c >/dev/null
    ./hcc -S -o smoke.M1 test/parse-smoke.c

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 hcc $out/bin/hcc
    install -Dm644 hcc-blynn.c $out/share/${shareName}/hcc-blynn.c
    install -Dm644 hcc-full.hs $out/share/${shareName}/hcc-full.hs
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
