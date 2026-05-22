{
  stageRun,
  mlcSrc,
  mlcStage03CoreLambda,
  mzvmSeedM2,
}:

stageRun {
  pname = "mlc-stage-04-core-handoff";
  nativeBuildInputs = [
    mzvmSeedM2
  ];
  description = "First explicit source compiled by the streamed core lambda stage";
  buildScript = ''
    cp ${mlcSrc}/stages/04-core-handoff.core 04-core-handoff.core
    ${mzvmSeedM2}/bin/mzvm-seed ${mlcStage03CoreLambda}/share/mlc/stages/03-core-lambda.mzbc < 04-core-handoff.core > 04-core-handoff.mzbc
    actual="$(printf K | ${mzvmSeedM2}/bin/mzvm-seed 04-core-handoff.mzbc)"
    test "$actual" = OK
  '';
  installScript = ''
    install -Dm644 04-core-handoff.core "$out/share/mlc/stages/04-core-handoff.core"
    install -Dm644 04-core-handoff.mzbc "$out/share/mlc/stages/04-core-handoff.mzbc"
  '';
}
