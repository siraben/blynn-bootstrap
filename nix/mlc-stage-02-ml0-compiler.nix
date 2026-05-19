{
  stageRun,
  mlcSrc,
  testsMlc,
  mlcInterpSeedM2,
  mzvmSeedM2,
}:

stageRun {
  pname = "mlc-stage-02-ml0-compiler";
  nativeBuildInputs = [
    mlcInterpSeedM2
    mzvmSeedM2
  ];
  description = "First MLC stage that compiles an ML source subset to MZBC";
  buildScript = ''
    ulimit -s unlimited || true
    cp ${mlcSrc}/stages/02-ml0-compiler.ml 02-ml0-compiler.ml
    cp ${mlcSrc}/stages/03-ok.ml0 03-ok.ml0
    cp ${mlcSrc}/stages/03-char-string.ml0 03-char-string.ml0
    ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < 03-ok.ml0 > 03-ok.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-ok.mzbc)"
    test "$actual" = OK
    ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < 03-char-string.ml0 > 03-char-string.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-char-string.mzbc)"
    test "$actual" = OK
    printf 'let f = fun x -> write_byte x in f 79' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > closure.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed closure.mzbc > closure.out
    printf 'let f = fun x -> let f2 = fun y -> write_byte (x + y) in f2 39 in f 40' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > closure-capture.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed closure-capture.mzbc > closure-capture.out
    printf 'let f = fun x -> write_byte x in let elsewhere = 79 in let thenable = 75 in let input = 10 in let _ = f elsewhere in let _ = f thenable in f input' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > closure-lookahead.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed closure-lookahead.mzbc > closure-lookahead.out
    printf 'let rec k x = x in let rec apply f = fun x -> f x in write_byte (apply k 79)' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > function-value.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed function-value.mzbc > function-value.out
    printf 'let x = 79 in let rec f y = write_byte (x + y) in f 0' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > letrec-capture.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed letrec-capture.mzbc > letrec-capture.out
    printf 'let rec f ch = if ch = 79 then write_byte ch else write_byte 88 in f 79' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > single-eq.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed single-eq.mzbc > single-eq.out
    printf '%s' "write_byte (if '\013' = 13 then 'O' else 'X')" | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > decimal-char-stage02.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed decimal-char-stage02.mzbc > decimal-char-stage02.out
    printf 'write_byte -1' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > negative-immediate.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed negative-immediate.mzbc > negative-immediate.out
    for name in ok arithmetic conditional comparison let-binding sequence negative identifiers keyword-prefix-infix string string-value length exit tuple bytes array dynamic-create dynamic-index function function-tuple function-nested function-string; do
      ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < ${testsMlc}/$name.ml > $name.mzbc
      ${mzvmSeedM2}/bin/mzvm-seed $name.mzbc > $name.out
    done
    ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < ${testsMlc}/read-byte.ml > read-byte.mzbc
    printf O | ${mzvmSeedM2}/bin/mzvm-seed read-byte.mzbc > read-byte.out
    ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < ${mlcSrc}/mlc.ml > mlc-stage.mzbc
    printf 'write_byte (40+39)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-compiled.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-compiled.mzbc > mlc-stage.out
    printf "write_byte 'O'" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-char.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-char.mzbc > mlc-stage-char.out
    printf '%s' "write_byte (if '\013' == 13 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-decimal-char.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-decimal-char.mzbc > mlc-stage-decimal-char.out
    printf 'write_string "OK"' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-string.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-string.mzbc > mlc-stage-string.out
    printf 'let x = 40 in write_byte (x + 39)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-let.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-let.mzbc > mlc-stage-let.out
    printf 'let x = 40 in let y = 39 in write_byte (x + y)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-let2.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-let2.mzbc > mlc-stage-let2.out
    printf 'let x = 40 in let y = 20 in let z = 19 in write_byte (x + y + z)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-let3.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-let3.mzbc > mlc-stage-let3.out
    printf 'let x = (40 + 39) in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-paren-let.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-paren-let.mzbc > mlc-stage-paren-let.out
    printf 'let x = 88 in let x = 79 in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-shadow.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-shadow.mzbc > mlc-stage-shadow.out
    printf 'write_byte (80 - 1)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-sub.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-sub.mzbc > mlc-stage-sub.out
    printf 'write_byte (79 * 1)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-mul.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-mul.mzbc > mlc-stage-mul.out
    printf 'write_byte (158 / 2)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-div.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-div.mzbc > mlc-stage-div.out
    printf "write_byte (if 1 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-true.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-true.mzbc > mlc-stage-if-true.out
    printf "write_byte (if 0 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-false.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-false.mzbc > mlc-stage-if-false.out
    printf "write_byte (if 40 < 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-lt-true.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-lt-true.mzbc > mlc-stage-if-lt-true.out
    printf "write_byte (if 41 < 40 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-lt-false.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-lt-false.mzbc > mlc-stage-if-lt-false.out
    printf "write_byte (if 40 == 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-eq-true.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-eq-true.mzbc > mlc-stage-if-eq-true.out
    printf "write_byte (if 40 == 41 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-eq-false.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-eq-false.mzbc > mlc-stage-if-eq-false.out
    printf "write_byte (if 40 != 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-ne.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-ne.mzbc > mlc-stage-if-ne.out
    printf "write_byte (if 40 <= 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-le.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-le.mzbc > mlc-stage-if-le.out
    printf "write_byte (if 41 > 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-gt.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-gt.mzbc > mlc-stage-if-gt.out
    printf "write_byte (if 41 >= 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-ge.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-ge.mzbc > mlc-stage-if-ge.out
    ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < 02-ml0-compiler.ml > 02-self.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed 02-self.mzbc < 02-ml0-compiler.ml > 02-self-again.mzbc
    printf 'write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 02-self-again.mzbc > 02-self-smoke.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed 02-self-smoke.mzbc > 02-self-smoke.out
    ${mzvmSeedM2}/bin/mzvm-seed 02-self.mzbc < ${mlcSrc}/mlc.ml > mlc-stage-from-02-self.mzbc
    printf 'write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-from-02-self.mzbc > mlc-stage-from-02-self-smoke.mzbc
    ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-from-02-self-smoke.mzbc > mlc-stage-from-02-self-smoke.out
    test "$(cat ok.out)" = OK
    test "$(cat arithmetic.out)" = H-
    test "$(cat conditional.out)" = OK
    test "$(cat comparison.out)" = "OK
OK"
    test "$(cat let-binding.out)" = OK
    test "$(cat closure.out)" = O
    test "$(cat closure-capture.out)" = O
    test "$(cat closure-lookahead.out)" = "OK"
    test "$(cat function-value.out)" = O
    test "$(cat letrec-capture.out)" = O
    test "$(cat single-eq.out)" = O
    test "$(cat decimal-char-stage02.out)" = O
    printf '\377' > negative-immediate.expected
    test "$(cat negative-immediate.out)" = "$(cat negative-immediate.expected)"
    test "$(cat sequence.out)" = OK
    test "$(cat negative.out)" = OK
    test "$(cat identifiers.out)" = O
    test "$(cat keyword-prefix-infix.out)" = O
    test "$(cat string.out)" = "O	K"
    test "$(cat string-value.out)" = OK
    test "$(cat length.out)" = OK
    test "$(cat exit.out)" = OK
    test "$(cat tuple.out)" = OK
    test "$(cat bytes.out)" = OK
    test "$(cat array.out)" = OK
    test "$(cat dynamic-create.out)" = OK
    test "$(cat dynamic-index.out)" = OK
    test "$(cat function.out)" = OK
    test "$(cat function-tuple.out)" = OK
    test "$(cat function-nested.out)" = OK
    test "$(cat function-string.out)" = OK
    test "$(cat read-byte.out)" = OK
    test "$(cat mlc-stage.out)" = O
    test "$(cat mlc-stage-char.out)" = O
    test "$(cat mlc-stage-decimal-char.out)" = O
    test "$(cat mlc-stage-string.out)" = OK
    test "$(cat mlc-stage-let.out)" = O
    test "$(cat mlc-stage-let2.out)" = O
    test "$(cat mlc-stage-let3.out)" = O
    test "$(cat mlc-stage-paren-let.out)" = O
    test "$(cat mlc-stage-shadow.out)" = O
    test "$(cat mlc-stage-sub.out)" = O
    test "$(cat mlc-stage-mul.out)" = O
    test "$(cat mlc-stage-div.out)" = O
    test "$(cat mlc-stage-if-true.out)" = O
    test "$(cat mlc-stage-if-false.out)" = O
    test "$(cat mlc-stage-if-lt-true.out)" = O
    test "$(cat mlc-stage-if-lt-false.out)" = O
    test "$(cat mlc-stage-if-eq-true.out)" = O
    test "$(cat mlc-stage-if-eq-false.out)" = O
    test "$(cat mlc-stage-if-ne.out)" = O
    test "$(cat mlc-stage-if-le.out)" = O
    test "$(cat mlc-stage-if-gt.out)" = O
    test "$(cat mlc-stage-if-ge.out)" = O
    test "$(cat 02-self-smoke.out)" = O
    test "$(cat mlc-stage-from-02-self-smoke.out)" = O
  '';
  installScript = ''
    install -Dm644 02-ml0-compiler.ml "$out/share/mlc/stages/02-ml0-compiler.ml"
    install -Dm644 03-ok.ml0 "$out/share/mlc/stages/03-ok.ml0"
    install -Dm644 03-char-string.ml0 "$out/share/mlc/stages/03-char-string.ml0"
    install -Dm644 03-ok.mzbc "$out/share/mlc/stages/03-ok.mzbc"
    install -Dm644 03-char-string.mzbc "$out/share/mlc/stages/03-char-string.mzbc"
    install -Dm644 closure.mzbc "$out/share/mlc/stages/closure.mzbc"
    install -Dm644 closure.out "$out/share/mlc/stages/closure.out"
    install -Dm644 closure-capture.mzbc "$out/share/mlc/stages/closure-capture.mzbc"
    install -Dm644 closure-capture.out "$out/share/mlc/stages/closure-capture.out"
    install -Dm644 closure-lookahead.mzbc "$out/share/mlc/stages/closure-lookahead.mzbc"
    install -Dm644 closure-lookahead.out "$out/share/mlc/stages/closure-lookahead.out"
    install -Dm644 function-value.mzbc "$out/share/mlc/stages/function-value.mzbc"
    install -Dm644 function-value.out "$out/share/mlc/stages/function-value.out"
    install -Dm644 letrec-capture.mzbc "$out/share/mlc/stages/letrec-capture.mzbc"
    install -Dm644 letrec-capture.out "$out/share/mlc/stages/letrec-capture.out"
    install -Dm644 single-eq.mzbc "$out/share/mlc/stages/single-eq.mzbc"
    install -Dm644 single-eq.out "$out/share/mlc/stages/single-eq.out"
    install -Dm644 decimal-char-stage02.mzbc "$out/share/mlc/stages/decimal-char-stage02.mzbc"
    install -Dm644 decimal-char-stage02.out "$out/share/mlc/stages/decimal-char-stage02.out"
    install -Dm644 negative-immediate.mzbc "$out/share/mlc/stages/negative-immediate.mzbc"
    install -Dm644 negative-immediate.out "$out/share/mlc/stages/negative-immediate.out"
    install -Dm644 02-self.mzbc "$out/share/mlc/stages/02-self.mzbc"
    install -Dm644 02-self-again.mzbc "$out/share/mlc/stages/02-self-again.mzbc"
    install -Dm644 02-self-smoke.mzbc "$out/share/mlc/stages/02-self-smoke.mzbc"
    install -Dm644 02-self-smoke.out "$out/share/mlc/stages/02-self-smoke.out"
    install -Dm644 mlc-stage-from-02-self.mzbc "$out/share/mlc/stages/mlc-stage-from-02-self.mzbc"
    install -Dm644 mlc-stage-from-02-self-smoke.mzbc "$out/share/mlc/stages/mlc-stage-from-02-self-smoke.mzbc"
    install -Dm644 mlc-stage-from-02-self-smoke.out "$out/share/mlc/stages/mlc-stage-from-02-self-smoke.out"
    install -Dm644 string-value.mzbc "$out/share/mlc/stages/string-value.mzbc"
    install -Dm644 length.mzbc "$out/share/mlc/stages/length.mzbc"
    install -Dm644 keyword-prefix-infix.mzbc "$out/share/mlc/stages/keyword-prefix-infix.mzbc"
    install -Dm644 read-byte.mzbc "$out/share/mlc/stages/read-byte.mzbc"
    install -Dm644 exit.mzbc "$out/share/mlc/stages/exit.mzbc"
    install -Dm644 tuple.mzbc "$out/share/mlc/stages/tuple.mzbc"
    install -Dm644 bytes.mzbc "$out/share/mlc/stages/bytes.mzbc"
    install -Dm644 array.mzbc "$out/share/mlc/stages/array.mzbc"
    install -Dm644 dynamic-create.mzbc "$out/share/mlc/stages/dynamic-create.mzbc"
    install -Dm644 dynamic-index.mzbc "$out/share/mlc/stages/dynamic-index.mzbc"
    install -Dm644 function.mzbc "$out/share/mlc/stages/function.mzbc"
    install -Dm644 function-tuple.mzbc "$out/share/mlc/stages/function-tuple.mzbc"
    install -Dm644 function-nested.mzbc "$out/share/mlc/stages/function-nested.mzbc"
    install -Dm644 function-string.mzbc "$out/share/mlc/stages/function-string.mzbc"
    install -Dm644 mlc-stage.mzbc "$out/share/mlc/stages/mlc-stage.mzbc"
    install -Dm644 mlc-stage-compiled.mzbc "$out/share/mlc/stages/mlc-stage-compiled.mzbc"
    install -Dm644 mlc-stage.out "$out/share/mlc/stages/mlc-stage.out"
    install -Dm644 mlc-stage-char.mzbc "$out/share/mlc/stages/mlc-stage-char.mzbc"
    install -Dm644 mlc-stage-char.out "$out/share/mlc/stages/mlc-stage-char.out"
    install -Dm644 mlc-stage-decimal-char.mzbc "$out/share/mlc/stages/mlc-stage-decimal-char.mzbc"
    install -Dm644 mlc-stage-decimal-char.out "$out/share/mlc/stages/mlc-stage-decimal-char.out"
    install -Dm644 mlc-stage-string.mzbc "$out/share/mlc/stages/mlc-stage-string.mzbc"
    install -Dm644 mlc-stage-string.out "$out/share/mlc/stages/mlc-stage-string.out"
    install -Dm644 mlc-stage-let.mzbc "$out/share/mlc/stages/mlc-stage-let.mzbc"
    install -Dm644 mlc-stage-let.out "$out/share/mlc/stages/mlc-stage-let.out"
    install -Dm644 mlc-stage-let2.mzbc "$out/share/mlc/stages/mlc-stage-let2.mzbc"
    install -Dm644 mlc-stage-let2.out "$out/share/mlc/stages/mlc-stage-let2.out"
    install -Dm644 mlc-stage-let3.mzbc "$out/share/mlc/stages/mlc-stage-let3.mzbc"
    install -Dm644 mlc-stage-let3.out "$out/share/mlc/stages/mlc-stage-let3.out"
    install -Dm644 mlc-stage-paren-let.mzbc "$out/share/mlc/stages/mlc-stage-paren-let.mzbc"
    install -Dm644 mlc-stage-paren-let.out "$out/share/mlc/stages/mlc-stage-paren-let.out"
    install -Dm644 mlc-stage-shadow.mzbc "$out/share/mlc/stages/mlc-stage-shadow.mzbc"
    install -Dm644 mlc-stage-shadow.out "$out/share/mlc/stages/mlc-stage-shadow.out"
    install -Dm644 mlc-stage-sub.mzbc "$out/share/mlc/stages/mlc-stage-sub.mzbc"
    install -Dm644 mlc-stage-sub.out "$out/share/mlc/stages/mlc-stage-sub.out"
    install -Dm644 mlc-stage-mul.mzbc "$out/share/mlc/stages/mlc-stage-mul.mzbc"
    install -Dm644 mlc-stage-mul.out "$out/share/mlc/stages/mlc-stage-mul.out"
    install -Dm644 mlc-stage-div.mzbc "$out/share/mlc/stages/mlc-stage-div.mzbc"
    install -Dm644 mlc-stage-div.out "$out/share/mlc/stages/mlc-stage-div.out"
    install -Dm644 mlc-stage-if-true.mzbc "$out/share/mlc/stages/mlc-stage-if-true.mzbc"
    install -Dm644 mlc-stage-if-true.out "$out/share/mlc/stages/mlc-stage-if-true.out"
    install -Dm644 mlc-stage-if-false.mzbc "$out/share/mlc/stages/mlc-stage-if-false.mzbc"
    install -Dm644 mlc-stage-if-false.out "$out/share/mlc/stages/mlc-stage-if-false.out"
    install -Dm644 mlc-stage-if-lt-true.mzbc "$out/share/mlc/stages/mlc-stage-if-lt-true.mzbc"
    install -Dm644 mlc-stage-if-lt-true.out "$out/share/mlc/stages/mlc-stage-if-lt-true.out"
    install -Dm644 mlc-stage-if-lt-false.mzbc "$out/share/mlc/stages/mlc-stage-if-lt-false.mzbc"
    install -Dm644 mlc-stage-if-lt-false.out "$out/share/mlc/stages/mlc-stage-if-lt-false.out"
    install -Dm644 mlc-stage-if-eq-true.mzbc "$out/share/mlc/stages/mlc-stage-if-eq-true.mzbc"
    install -Dm644 mlc-stage-if-eq-true.out "$out/share/mlc/stages/mlc-stage-if-eq-true.out"
    install -Dm644 mlc-stage-if-eq-false.mzbc "$out/share/mlc/stages/mlc-stage-if-eq-false.mzbc"
    install -Dm644 mlc-stage-if-eq-false.out "$out/share/mlc/stages/mlc-stage-if-eq-false.out"
    install -Dm644 mlc-stage-if-ne.mzbc "$out/share/mlc/stages/mlc-stage-if-ne.mzbc"
    install -Dm644 mlc-stage-if-ne.out "$out/share/mlc/stages/mlc-stage-if-ne.out"
    install -Dm644 mlc-stage-if-le.mzbc "$out/share/mlc/stages/mlc-stage-if-le.mzbc"
    install -Dm644 mlc-stage-if-le.out "$out/share/mlc/stages/mlc-stage-if-le.out"
    install -Dm644 mlc-stage-if-gt.mzbc "$out/share/mlc/stages/mlc-stage-if-gt.mzbc"
    install -Dm644 mlc-stage-if-gt.out "$out/share/mlc/stages/mlc-stage-if-gt.out"
    install -Dm644 mlc-stage-if-ge.mzbc "$out/share/mlc/stages/mlc-stage-if-ge.mzbc"
    install -Dm644 mlc-stage-if-ge.out "$out/share/mlc/stages/mlc-stage-if-ge.out"
  '';
}
