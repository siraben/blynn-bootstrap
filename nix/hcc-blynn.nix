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

    echo "hcc-blynn: concatenate hcpp Haskell sources"
    cat \
      ${blynnSrc}/inn/BasePrecisely.hs \
      ${blynnSrc}/inn/System.hs \
      Hcc/Token.hs \
      Hcc/SymbolTable.hs \
      Hcc/ParseLite.hs \
      Hcc/ConstExpr.hs \
      Hcc/Lexer.hs \
      Hcc/Preprocessor.hs \
      Hcc/HccSystem.hs \
      Hcc/DriverCommon.hs \
      Hcc/IncludeExpand.hs \
      MainCpp.hs \
      > hcpp-full.hs

    echo "hcc-blynn: concatenate hcc1 Haskell sources"
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
      Hcc/RegAlloc.hs \
      Hcc/CodegenM1.hs \
      Hcc/HccSystem.hs \
      Hcc/DriverCommon.hs \
      MainCc1.hs \
      > hcc1-full.hs

    echo "hcc-blynn: precisely_up hcpp-full.hs -> hcpp-blynn.c"
    ${precisely}/bin/precisely_up < hcpp-full.hs > hcpp-blynn.c
    echo "hcc-blynn: precisely_up hcc1-full.hs -> hcc1-blynn.c"
    ${precisely}/bin/precisely_up < hcc1-full.hs > hcc1-blynn.c
    echo "hcc-blynn: patch generated RTS TOP=${toString top}"
    sed -i -E 's/enum\{TOP=[0-9]+\};/enum{TOP=${toString top}};/' hcpp-blynn.c hcc1-blynn.c
    grep -q 'enum{TOP=${toString top}};' hcpp-blynn.c
    grep -q 'enum{TOP=${toString top}};' hcc1-blynn.c

    echo "hcc-blynn: compile generated C backend"
    ${compileCommand}

    echo "hcc-blynn: run hcpp smoke"
    ./hcpp test/pp-smoke.c > pp-smoke.i
    echo "hcc-blynn: run hcc1 preprocessor smoke check"
    ./hcc1 --check pp-smoke.i
    echo "hcc-blynn: run hcpp parse smoke"
    ./hcpp test/parse-smoke.c > parse-smoke.i
    echo "hcc-blynn: run hcc1 parse smoke check"
    ./hcc1 --check parse-smoke.i
    echo "hcc-blynn: run hcc1 M1 smoke codegen"
    ./hcc1 -S -o smoke.M1 parse-smoke.i

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
