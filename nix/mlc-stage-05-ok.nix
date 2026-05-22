{
  stageRun,
  mlcSrc,
  mlcStage04CoreHandoff,
  mzvmSeedM2,
}:

stageRun {
  pname = "mlc-stage-05-ok";
  nativeBuildInputs = [
    mzvmSeedM2
  ];
  description = "Named byte2 source compiled by the tiny core handoff compiler";
  buildScript = ''
    cp ${mlcSrc}/stages/05-ok.core 05-ok.core
    ${mzvmSeedM2}/bin/mzvm-seed ${mlcStage04CoreHandoff}/share/mlc/stages/04-core-handoff.mzbc < 05-ok.core > 05-ok.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 05-ok.mzbc)"
    test "$actual" = OK
  '';
  installScript = ''
    install -Dm644 05-ok.core "$out/share/mlc/stages/05-ok.core"
    install -Dm644 05-ok.mzbc "$out/share/mlc/stages/05-ok.mzbc"
  '';
}
