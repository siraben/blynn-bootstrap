{
  stageRun,
  mlcSrc,
  mlcInterpSeedM2,
  mlcStage02CoreLambda,
  mzvmSeedM2,
}:

stageRun {
  pname = "mlc-stage-03-core-handoff";
  nativeBuildInputs = [
    mlcInterpSeedM2
    mzvmSeedM2
  ];
  description = "Tiny byte-literal compiler produced by the streamed core lambda stage";
  buildScript = ''
    cp ${mlcSrc}/stages/03-core-handoff.core 03-core-handoff.core
    ${mlcInterpSeedM2}/bin/mlc-interp-seed ${mlcStage02CoreLambda}/share/mlc/stages/02-core-lambda.ml < 03-core-handoff.core > 03-core-handoff.mzbc
    printf "(byte 'O')" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-handoff.mzbc > 03-byte-output.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-byte-output.mzbc)"
    test "$actual" = O

    printf "(byte 'K')" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-handoff.mzbc > 03-byte-output-k.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-byte-output-k.mzbc)"
    test "$actual" = K

    printf "(exit '*')" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-handoff.mzbc > 03-exit-output.mzbc
    set +e
    ${mzvmSeedM2}/bin/mzvm-seed 03-exit-output.mzbc
    status="$?"
    set -e
    test "$status" = 42

    printf "(debug 'D')" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-handoff.mzbc > 03-debug-output.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-debug-output.mzbc 2>&1)"
    test "$actual" = D

    printf "%s" "(byte '\t')" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-handoff.mzbc > 03-byte-tab.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-byte-tab.mzbc)"
    test "$actual" = "$(printf '\t')"

    printf "(byte2 'O' 'K')" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-handoff.mzbc > 03-byte2-output.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-byte2-output.mzbc)"
    test "$actual" = OK
  '';
  installScript = ''
    install -Dm644 03-core-handoff.core "$out/share/mlc/stages/03-core-handoff.core"
    install -Dm644 03-core-handoff.mzbc "$out/share/mlc/stages/03-core-handoff.mzbc"
    install -Dm644 03-byte-output.mzbc "$out/share/mlc/stages/03-byte-output.mzbc"
    install -Dm644 03-byte-output-k.mzbc "$out/share/mlc/stages/03-byte-output-k.mzbc"
    install -Dm644 03-exit-output.mzbc "$out/share/mlc/stages/03-exit-output.mzbc"
    install -Dm644 03-debug-output.mzbc "$out/share/mlc/stages/03-debug-output.mzbc"
    install -Dm644 03-byte-tab.mzbc "$out/share/mlc/stages/03-byte-tab.mzbc"
    install -Dm644 03-byte2-output.mzbc "$out/share/mlc/stages/03-byte2-output.mzbc"
  '';
}
