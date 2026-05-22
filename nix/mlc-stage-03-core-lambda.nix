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

    printf "(20 (write-byte 'O'))" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-byte.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-byte.mzbc)"
    test "$actual" = O

    printf '%s' "(20 (write-byte '\079'))" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-byte-escape.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-byte-escape.mzbc)"
    test "$actual" = O

    printf '(34 (write-string "OK"))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-string.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-string.mzbc)"
    test "$actual" = OK

    printf '(27 (write-byte (+ 40 39)))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-add.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-add.mzbc)"
    test "$actual" = O

    printf '(39 (seq (write-byte 79) (write-byte 75)))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-seq.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-seq.mzbc)"
    test "$actual" = OK

    printf '(34 (write-byte (+ (= 1 1) 78)))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-eq.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-eq.mzbc)"
    test "$actual" = O

    printf '(38 (let 40 (write-byte (+ (var 0) 39))))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-let-var.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-let-var.mzbc)"
    test "$actual" = O

    printf '(49 (let 88 (let 40 (write-byte (+ (var 0) 39)))))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-let-shadow.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-let-shadow.mzbc)"
    test "$actual" = O

    printf "(61 (if 19 19 (= 1 1) (write-byte 'O') (write-byte 88)))" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-if-true.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-if-true.mzbc)"
    test "$actual" = O

    printf "(61 (if 19 19 (< 2 1) (write-byte 88) (write-byte 'K')))" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-if-false.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-if-false.mzbc)"
    test "$actual" = K

    printf "(49 (app (fun 5 26 (write-byte (+ (var 0) 39))) 40))" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-app-fun.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-core-app-fun.mzbc)"
    test "$actual" = O

    printf '(29 (write-byte (read-byte)))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-read-byte.mzbc
    actual="$(printf O | ${mzvmSeedM2}/bin/mzvm-seed 03-core-read-byte.mzbc)"
    test "$actual" = O

    printf "(51 (need-byte 'O'))" | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-need-byte.mzbc
    actual="$(printf O | ${mzvmSeedM2}/bin/mzvm-seed 03-core-need-byte.mzbc)"
    test "$actual" = ""
    set +e
    printf K | ${mzvmSeedM2}/bin/mzvm-seed 03-core-need-byte.mzbc
    status="$?"
    set -e
    test "$status" = 1

    printf '(15 (exit 42))' | ${mzvmSeedM2}/bin/mzvm-seed 03-core-lambda.mzbc > 03-core-exit.mzbc
    if ${mzvmSeedM2}/bin/mzvm-seed 03-core-exit.mzbc; then
      exit 1
    else
      test "$?" = 42
    fi
  '';
  installScript = ''
    install -Dm644 03-core-lambda.ml0 "$out/share/mlc/stages/03-core-lambda.ml0"
    install -Dm644 03-core-lambda.mzbc "$out/share/mlc/stages/03-core-lambda.mzbc"
    install -Dm644 03-core-byte.mzbc "$out/share/mlc/stages/03-core-byte.mzbc"
    install -Dm644 03-core-byte-escape.mzbc "$out/share/mlc/stages/03-core-byte-escape.mzbc"
    install -Dm644 03-core-string.mzbc "$out/share/mlc/stages/03-core-string.mzbc"
    install -Dm644 03-core-add.mzbc "$out/share/mlc/stages/03-core-add.mzbc"
    install -Dm644 03-core-seq.mzbc "$out/share/mlc/stages/03-core-seq.mzbc"
    install -Dm644 03-core-eq.mzbc "$out/share/mlc/stages/03-core-eq.mzbc"
    install -Dm644 03-core-let-var.mzbc "$out/share/mlc/stages/03-core-let-var.mzbc"
    install -Dm644 03-core-let-shadow.mzbc "$out/share/mlc/stages/03-core-let-shadow.mzbc"
    install -Dm644 03-core-if-true.mzbc "$out/share/mlc/stages/03-core-if-true.mzbc"
    install -Dm644 03-core-if-false.mzbc "$out/share/mlc/stages/03-core-if-false.mzbc"
    install -Dm644 03-core-app-fun.mzbc "$out/share/mlc/stages/03-core-app-fun.mzbc"
    install -Dm644 03-core-read-byte.mzbc "$out/share/mlc/stages/03-core-read-byte.mzbc"
    install -Dm644 03-core-need-byte.mzbc "$out/share/mlc/stages/03-core-need-byte.mzbc"
    install -Dm644 03-core-exit.mzbc "$out/share/mlc/stages/03-core-exit.mzbc"
  '';
}
