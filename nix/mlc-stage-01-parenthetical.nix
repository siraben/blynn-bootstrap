{
  stageRun,
  mlcSrc,
  mlcInterpSeedM2,
  mzvmSeedM2,
}:

stageRun {
  pname = "mlc-stage-01-parenthetical";
  nativeBuildInputs = [
    mlcInterpSeedM2
    mzvmSeedM2
  ];
  description = "First MLC handoff stage: parenthesized MZBC assembly to bytecode";
  buildScript = ''
    cp ${mlcSrc}/stages/01-parenthetical.ml 01-parenthetical.ml
    cp ${mlcSrc}/stages/02-ok.mzp 02-ok.mzp
    ${mlcInterpSeedM2}/bin/mlc-interp-seed 01-parenthetical.ml < 02-ok.mzp > 02-ok.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-ok.mzbc)"
    test "$actual" = OK
  '';
  installScript = ''
    install -Dm644 01-parenthetical.ml "$out/share/mlc/stages/01-parenthetical.ml"
    install -Dm644 02-ok.mzp "$out/share/mlc/stages/02-ok.mzp"
    install -Dm644 02-ok.mzbc "$out/share/mlc/stages/02-ok.mzbc"
  '';
}
