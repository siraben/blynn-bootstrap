{
  stageRun,
  minimalBootstrap,
  mlcSrc,
  scriptsRoot,
}:

stageRun {
  pname = "mlc-interp-seed-m2";
  nativeBuildInputs = [
    minimalBootstrap.stage0-posix.mescc-tools
  ];
  description = "M2-Planet-built tree-walking mini-OCaml bootstrap interpreter";
  buildScript = ''
    . ${scriptsRoot}/lib/bootstrap.sh
    cp ${mlcSrc}/mlc-interp-seed.c mlc-interp-seed.c
    cp ${mlcSrc}/stages/00-core.ml 00-core.ml
    compile_m2 mlc-interp-seed.c mlc-interp-seed
    actual="$(./mlc-interp-seed 00-core.ml)"
    test "$actual" = OOK
    ./mlc-interp-seed 00-core.ml > 00-core.out
  '';
  installScript = ''
    install -Dm755 mlc-interp-seed "$out/bin/mlc-interp-seed"
    install -Dm644 mlc-interp-seed.c "$out/share/mlc/mlc-interp-seed.c"
    install -Dm644 00-core.ml "$out/share/mlc/stages/00-core.ml"
    install -Dm644 00-core.out "$out/share/mlc/stages/00-core.out"
  '';
}
