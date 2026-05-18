{
  stageRun,
  mlcSrc,
  mlcInterpSeedM2,
}:

stageRun {
  pname = "mlc-stage-00-core";
  nativeBuildInputs = [
    mlcInterpSeedM2
  ];
  description = "First named MLC core-language bootstrap stage";
  buildScript = ''
    cp ${mlcSrc}/stages/00-core.ml 00-core.ml
    actual="$(${mlcInterpSeedM2}/bin/mlc-interp-seed 00-core.ml)"
    test "$actual" = OOK
    ${mlcInterpSeedM2}/bin/mlc-interp-seed 00-core.ml > 00-core.out
  '';
  installScript = ''
    install -Dm644 00-core.ml "$out/share/mlc/stages/00-core.ml"
    install -Dm644 00-core.out "$out/share/mlc/stages/00-core.out"
  '';
}
