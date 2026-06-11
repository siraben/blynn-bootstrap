{
  stageRun,
  mlcSrc,
  mlcStage03CoreHandoff,
  mzvmSeedM2,
}:

stageRun {
  pname = "mlc-stage-04-ok";
  nativeBuildInputs = [
    mzvmSeedM2
  ];
  description = "Named byte2 source compiled by the tiny core handoff compiler";
  buildScript = ''
    cp ${mlcSrc}/stages/04-ok.core 04-ok.core
    ${mzvmSeedM2}/bin/mzvm-seed ${mlcStage03CoreHandoff}/share/mlc/stages/03-core-handoff.mzbc < 04-ok.core > 04-ok.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 04-ok.mzbc)"
    test "$actual" = OK
  '';
  installScript = ''
    install -Dm644 04-ok.core "$out/share/mlc/stages/04-ok.core"
    install -Dm644 04-ok.mzbc "$out/share/mlc/stages/04-ok.mzbc"
  '';
}
