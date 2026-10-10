{ stdenvNoCC, lib, runtimeShell, generatedC, compiler, hccSrc }:

stdenvNoCC.mkDerivation {
  pname = "hcc-ghc-precisely-grammar-gcc-debug";
  version = "0-unstable-2026-05-06";
  dontUnpack = true;
  dontConfigure = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    ulimit -s unlimited
    # This is the isolated GHC/RTSPrecisely generator output, not faithful
    # crossly C. Heap and external-allocation options are emitted by the
    # generator itself. Compile it verbatim: no generated-C substitutions.
    for name in hcpp hcc1; do
      cp ${generatedC}/share/${generatedC.pname}/$name-blynn.c $name-blynn.c
      ${compiler}/bin/m2-planet-grammar-gcc-debug \
        -f $name-blynn.c -f ${hccSrc}/cbits/hcc_runtime_m2.c -o $name
    done
    ${compiler}/bin/m2-planet-grammar-gcc-debug \
      -f ${hccSrc}/cbits/hcc_m1.c -o hcc-m1
    (
      export HCPP=./hcpp HCC1=./hcc1 HCC_M1=./hcc-m1
      export TESTS_DIR=${../tests/hcc} LOG_PREFIX=hcc-grammar-debug-smoke
      . ${../scripts/hcc-compiler-smoke.sh}
    )
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/libexec" "$out/share/hcc-grammar-debug"
    for name in hcpp hcc1 hcc-m1; do
      install -m555 "$name" "$out/libexec/$name"
      printf '%s\n' '#!${runtimeShell}' 'ulimit -s unlimited' \
        "exec \"$out/libexec/$name\" \"\$@\"" > "$out/bin/$name"
      chmod 555 "$out/bin/$name"
    done
    cp hcpp-blynn.c hcc1-blynn.c "$out/share/hcc-grammar-debug/"
    runHook postInstall
  '';

  passthru = { inherit generatedC compiler; };
  meta = {
    description = "HCC via host-GHC Precisely and the host-GCC M2 grammar fork (debug only)";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
