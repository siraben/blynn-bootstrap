{
  stageRun,
  mlcSrc,
  mlcInterpSeedM2,
  mzvmSeedM2,
}:

stageRun {
  pname = "mlc-stage-02-core-lambda";
  nativeBuildInputs = [
    mlcInterpSeedM2
    mzvmSeedM2
  ];
  description = "Tiny streamed parenthetical core compiler run by the C interpreter root";
  buildScript = ''
    cp ${mlcSrc}/stages/02-core-lambda.ml 02-core-lambda.ml
    run_core_lambda() {
      ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-core-lambda.ml
    }

    printf "(20 (write-byte 'O'))" | run_core_lambda > 02-core-byte.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-core-byte.mzbc)"
    test "$actual" = O

    printf '%s' "(20 (write-byte '\079'))" | run_core_lambda > 02-core-byte-escape.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-core-byte-escape.mzbc)"
    test "$actual" = O

    printf '(34 (write-string "OK"))' | run_core_lambda > 02-core-string.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-core-string.mzbc)"
    test "$actual" = OK

    printf '(27 (write-byte (+ 40 39)))' | run_core_lambda > 02-core-add.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-core-add.mzbc)"
    test "$actual" = O

    printf '(39 (seq (write-byte 79) (write-byte 75)))' | run_core_lambda > 02-core-seq.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-core-seq.mzbc)"
    test "$actual" = OK

    printf '%s' "(81 (seq (write-u32 '\079') (write-byte 'K')))" | run_core_lambda > 02-core-write-u32.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed 02-core-write-u32.mzbc > /dev/null

    printf '(34 (write-byte (+ (= 1 1) 78)))' | run_core_lambda > 02-core-eq.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-core-eq.mzbc)"
    test "$actual" = O

    printf '(38 (let 40 (write-byte (+ (var 0) 39))))' | run_core_lambda > 02-core-let-var.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-core-let-var.mzbc)"
    test "$actual" = O

    printf '(49 (let 88 (let 40 (write-byte (+ (var 0) 39)))))' | run_core_lambda > 02-core-let-shadow.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-core-let-shadow.mzbc)"
    test "$actual" = O

    printf "(61 (if 19 19 (= 1 1) (write-byte 'O') (write-byte 88)))" | run_core_lambda > 02-core-if-true.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-core-if-true.mzbc)"
    test "$actual" = O

    printf "(61 (if 19 19 (< 2 1) (write-byte 88) (write-byte 'K')))" | run_core_lambda > 02-core-if-false.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-core-if-false.mzbc)"
    test "$actual" = K

    printf "(49 (app (fun 5 26 (write-byte (+ (var 0) 39))) 40))" | run_core_lambda > 02-core-app-fun.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-core-app-fun.mzbc)"
    test "$actual" = O

    printf '(29 (write-byte (read-byte)))' | run_core_lambda > 02-core-read-byte.mzbc
    actual="$(printf O | ${mzvmSeedM2}/bin/mzvm-seed 02-core-read-byte.mzbc)"
    test "$actual" = O

    printf '(257 (write-byte (read-char)))' | run_core_lambda > 02-core-read-char.mzbc
    actual="$(printf '\047O\047' | ${mzvmSeedM2}/bin/mzvm-seed 02-core-read-char.mzbc)"
    test "$actual" = O

    printf '(257 (write-byte (read-char)))' | run_core_lambda > 02-core-read-char-escape.mzbc
    actual="$(printf '\047\\t\047' | ${mzvmSeedM2}/bin/mzvm-seed 02-core-read-char-escape.mzbc)"
    test "$actual" = "$(printf '\t')"

    printf "(51 (need-byte 'O'))" | run_core_lambda > 02-core-need-byte.mzbc
    actual="$(printf O | ${mzvmSeedM2}/bin/mzvm-seed 02-core-need-byte.mzbc)"
    test "$actual" = ""
    set +e
    printf K | ${mzvmSeedM2}/bin/mzvm-seed 02-core-need-byte.mzbc
    status="$?"
    set -e
    test "$status" = 1

    printf '(120 (seq (need-string "OK") (write-byte 89)))' | run_core_lambda > 02-core-need-string.mzbc
    actual="$(printf OK | ${mzvmSeedM2}/bin/mzvm-seed 02-core-need-string.mzbc)"
    test "$actual" = Y
    set +e
    printf NO | ${mzvmSeedM2}/bin/mzvm-seed 02-core-need-string.mzbc
    status="$?"
    set -e
    test "$status" = 1

    printf '(15 (exit 42))' | run_core_lambda > 02-core-exit.mzbc
    if ${mzvmSeedM2}/bin/mzvm-seed 02-core-exit.mzbc; then
      exit 1
    else
      test "$?" = 42
    fi
  '';
  installScript = ''
    install -Dm644 02-core-lambda.ml "$out/share/mlc/stages/02-core-lambda.ml"
    install -Dm644 02-core-byte.mzbc "$out/share/mlc/stages/02-core-byte.mzbc"
    install -Dm644 02-core-byte-escape.mzbc "$out/share/mlc/stages/02-core-byte-escape.mzbc"
    install -Dm644 02-core-string.mzbc "$out/share/mlc/stages/02-core-string.mzbc"
    install -Dm644 02-core-add.mzbc "$out/share/mlc/stages/02-core-add.mzbc"
    install -Dm644 02-core-seq.mzbc "$out/share/mlc/stages/02-core-seq.mzbc"
    install -Dm644 02-core-write-u32.mzbc "$out/share/mlc/stages/02-core-write-u32.mzbc"
    install -Dm644 02-core-eq.mzbc "$out/share/mlc/stages/02-core-eq.mzbc"
    install -Dm644 02-core-let-var.mzbc "$out/share/mlc/stages/02-core-let-var.mzbc"
    install -Dm644 02-core-let-shadow.mzbc "$out/share/mlc/stages/02-core-let-shadow.mzbc"
    install -Dm644 02-core-if-true.mzbc "$out/share/mlc/stages/02-core-if-true.mzbc"
    install -Dm644 02-core-if-false.mzbc "$out/share/mlc/stages/02-core-if-false.mzbc"
    install -Dm644 02-core-app-fun.mzbc "$out/share/mlc/stages/02-core-app-fun.mzbc"
    install -Dm644 02-core-read-byte.mzbc "$out/share/mlc/stages/02-core-read-byte.mzbc"
    install -Dm644 02-core-read-char.mzbc "$out/share/mlc/stages/02-core-read-char.mzbc"
    install -Dm644 02-core-read-char-escape.mzbc "$out/share/mlc/stages/02-core-read-char-escape.mzbc"
    install -Dm644 02-core-need-byte.mzbc "$out/share/mlc/stages/02-core-need-byte.mzbc"
    install -Dm644 02-core-need-string.mzbc "$out/share/mlc/stages/02-core-need-string.mzbc"
    install -Dm644 02-core-exit.mzbc "$out/share/mlc/stages/02-core-exit.mzbc"
  '';
}
