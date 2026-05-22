{
  stageRun,
  mlcSrc,
  mlcStage02Ml0Compiler,
  mzvmSeedM2,
}:

stageRun {
  pname = "mlc-stage-03-core-lambda";
  nativeBuildInputs = [
    mzvmSeedM2
  ];
  description = "Tiny streamed parenthetical core compiler produced by stage 02";
  buildScript = ''
    cp ${mlcSrc}/stages/03-core-lambda.ml0 03-core-lambda.ml0
    ${mzvmSeedM2}/bin/mzvm-seed ${mlcStage02Ml0Compiler}/share/mlc/stages/02-self.mzbc < 03-core-lambda.ml0 > 03-core-lambda.mzbc

    printf "(15 (write-byte 'O'))" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-byte.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-byte.mzbc)"
    test "$actual" = O

    printf '(29 (write-string "OK"))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-string.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-string.mzbc)"
    test "$actual" = OK

    printf '(22 (write-byte (+ 40 39)))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-add.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-add.mzbc)"
    test "$actual" = O

    printf '(34 (seq (write-byte 79) (write-byte 75)))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-seq.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-seq.mzbc)"
    test "$actual" = OK

    printf '(29 (write-byte (+ (= 1 1) 78)))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-eq.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-eq.mzbc)"
    test "$actual" = O

    printf '(33 (let 40 (write-byte (+ (var 0) 39))))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-let-var.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-let-var.mzbc)"
    test "$actual" = O

    printf '(44 (let 88 (let 40 (write-byte (+ (var 0) 39)))))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-let-shadow.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-let-shadow.mzbc)"
    test "$actual" = O

    printf "(51 (if 14 14 (= 1 1) (write-byte 'O') (write-byte 88)))" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-if-true.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-if-true.mzbc)"
    test "$actual" = O

    printf "(51 (if 14 14 (< 2 1) (write-byte 88) (write-byte 'K')))" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-if-false.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-if-false.mzbc)"
    test "$actual" = K
  '';
  installScript = ''
    install -Dm644 03-core-lambda.ml0 "$out/share/mlc/stages/03-core-lambda.ml0"
    install -Dm644 03-core-lambda.mzbc "$out/share/mlc/stages/03-core-lambda.mzbc"
    install -Dm644 03-core-byte.mzbc "$out/share/mlc/stages/03-core-byte.mzbc"
    install -Dm644 03-core-string.mzbc "$out/share/mlc/stages/03-core-string.mzbc"
    install -Dm644 03-core-add.mzbc "$out/share/mlc/stages/03-core-add.mzbc"
    install -Dm644 03-core-seq.mzbc "$out/share/mlc/stages/03-core-seq.mzbc"
    install -Dm644 03-core-eq.mzbc "$out/share/mlc/stages/03-core-eq.mzbc"
    install -Dm644 03-core-let-var.mzbc "$out/share/mlc/stages/03-core-let-var.mzbc"
    install -Dm644 03-core-let-shadow.mzbc "$out/share/mlc/stages/03-core-let-shadow.mzbc"
    install -Dm644 03-core-if-true.mzbc "$out/share/mlc/stages/03-core-if-true.mzbc"
    install -Dm644 03-core-if-false.mzbc "$out/share/mlc/stages/03-core-if-false.mzbc"
  '';
}
