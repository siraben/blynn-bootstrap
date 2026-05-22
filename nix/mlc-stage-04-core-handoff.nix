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
  description = "Tiny byte-literal compiler produced by the streamed core lambda stage";
  buildScript = ''
    cp ${mlcSrc}/stages/04-core-handoff.core 04-core-handoff.core
    ${mzvmSeedM2}/bin/mzvm-seed ${mlcStage03CoreLambda}/share/mlc/stages/03-core-lambda.mzbc < 04-core-handoff.core > 04-core-handoff.mzbc
    printf '(byte O)' | ${mzvmSeedM2}/bin/mzvm-seed 04-core-handoff.mzbc > 04-byte-output.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 04-byte-output.mzbc)"
    test "$actual" = O

    printf '(byte K)' | ${mzvmSeedM2}/bin/mzvm-seed 04-core-handoff.mzbc > 04-byte-output-k.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 04-byte-output-k.mzbc)"
    test "$actual" = K

    printf '(exit *)' | ${mzvmSeedM2}/bin/mzvm-seed 04-core-handoff.mzbc > 04-exit-output.mzbc
    set +e
    ${mzvmSeedM2}/bin/mzvm-seed 04-exit-output.mzbc
    status="$?"
    set -e
    test "$status" = 42
  '';
  installScript = ''
    install -Dm644 04-core-handoff.core "$out/share/mlc/stages/04-core-handoff.core"
    install -Dm644 04-core-handoff.mzbc "$out/share/mlc/stages/04-core-handoff.mzbc"
    install -Dm644 04-byte-output.mzbc "$out/share/mlc/stages/04-byte-output.mzbc"
    install -Dm644 04-byte-output-k.mzbc "$out/share/mlc/stages/04-byte-output-k.mzbc"
    install -Dm644 04-exit-output.mzbc "$out/share/mlc/stages/04-exit-output.mzbc"
  '';
}
