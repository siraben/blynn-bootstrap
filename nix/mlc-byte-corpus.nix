{
  stageRun,
  diffutils,
  testsRoot,
  mlcByteSeed,
  mzvmSeedM2,
}:

stageRun {
  pname = "mlc-byte-corpus";
  nativeBuildInputs = [
    diffutils
    mzvmSeedM2
  ];
  description = "Full language corpus for the staged mini-OCaml compiler bytecode";
  buildScript = ''
    cp ${mlcByteSeed}/share/mlc/mlc.byte mlc.byte
    printf 'write_byte (40+39)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled.mzbc)"
    test "$actual" = O
    printf "write_byte 'O'" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-char.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-char.mzbc)"
    test "$actual" = O
    printf '%s' "write_byte (if '\013' == 13 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-decimal-char.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-decimal-char.mzbc)"
    test "$actual" = O
    printf 'write_string "OK"' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-string.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-string.mzbc)"
    test "$actual" = OK
    if printf 'write_byte "OK"' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > bad-write-byte-string.mzbc; then
      exit 1
    else
      :
    fi
    if printf 'write_byte (String.length 79)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > bad-string-length-int.mzbc; then
      exit 1
    else
      :
    fi
    if printf 'let x = 79 in write_byte x.' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > bad-consumed-dot.mzbc; then
      exit 1
    else
      :
    fi
    if printf 'write_byte (Bytes.length "OK")' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > bad-bytes-length-string.mzbc; then
      exit 1
    else
      :
    fi
    printf 'let _ = debug_byte 84 in write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-debug-byte.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-debug-byte.mzbc 2> debug-byte.err)"
    test "$actual" = O
    test "$(cat debug-byte.err)" = T
    printf 'let _ = debug_string "TRACE" in write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-debug-string.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-debug-string.mzbc 2> debug-string.err)"
    test "$actual" = O
    test "$(cat debug-string.err)" = TRACE
    printf 'let _ = debug_int (40 + 2) in write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-debug-int.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-debug-int.mzbc 2> debug-int.err)"
    test "$actual" = O
    test "$(cat debug-int.err)" = 42
    printf 'let _ = debug_printf "n=%%d" (40 + 2) in write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-debug-printf.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-debug-printf.mzbc 2> debug-printf.err)"
    test "$actual" = O
    test "$(cat debug-printf.err)" = n=42
    printf 'let x = 40 in write_byte (x + 39)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-let.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-let.mzbc)"
    test "$actual" = O
    printf 'let x = 40 in let y = 39 in write_byte (x + y)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-let2.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-let2.mzbc)"
    test "$actual" = O
    printf 'let x = 40 in let y = 20 in let z = 19 in write_byte (x + y + z)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-let3.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-let3.mzbc)"
    test "$actual" = O
    printf 'let x = (40 + 39) in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-paren-let.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-paren-let.mzbc)"
    test "$actual" = O
    printf 'let x = 88 in let x = 79 in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-shadow.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-shadow.mzbc)"
    test "$actual" = O
    printf 'let iffy = 79 in write_byte iffy' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-keyword-prefix-if.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-keyword-prefix-if.mzbc)"
    test "$actual" = O
    printf 'let lhs = 79 in write_byte lhs' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-keyword-prefix-let.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-keyword-prefix-let.mzbc)"
    test "$actual" = O
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/keyword-prefix-infix.ml > compiled-keyword-prefix-infix.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-keyword-prefix-infix.mzbc)"
    test "$actual" = O
    printf 'write_byte (80 - 1)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-sub.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-sub.mzbc)"
    test "$actual" = O
    printf 'write_byte (79 * 1)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-mul.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-mul.mzbc)"
    test "$actual" = O
    printf 'write_byte (158 / 2)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-div.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-div.mzbc)"
    test "$actual" = O
    printf "write_byte (if 1 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-true.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-true.mzbc)"
    test "$actual" = O
    printf "write_byte (if 0 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-false.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-false.mzbc)"
    test "$actual" = O
    printf "write_byte (if 40 < 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-lt-true.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-lt-true.mzbc)"
    test "$actual" = O
    printf "write_byte (if 41 < 40 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-lt-false.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-lt-false.mzbc)"
    test "$actual" = O
    printf "write_byte (if 40 == 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-eq-true.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-eq-true.mzbc)"
    test "$actual" = O
    printf "write_byte (if 40 == 41 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-eq-false.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-eq-false.mzbc)"
    test "$actual" = O
    printf "write_byte (if 40 != 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-ne.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-ne.mzbc)"
    test "$actual" = O
    printf "write_byte (if 40 <= 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-le.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-le.mzbc)"
    test "$actual" = O
    printf "write_byte (if 41 > 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-gt.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-gt.mzbc)"
    test "$actual" = O
    printf "write_byte (if 41 >= 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-ge.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-ge.mzbc)"
    test "$actual" = O
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/adt.ml > compiled-adt.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-adt.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/match.ml > compiled-match.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-match.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/wildcard-match.ml > compiled-wildcard-match.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-wildcard-match.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/match-bind-default.ml > compiled-match-bind-default.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-match-bind-default.mzbc)"
    test "$actual" = OK
    if printf 'type maybe_byte = Missing | Present of int\nwrite_byte (match Missing with Present x -> x | Presnt x -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > bad-uppercase-default.mzbc; then
      exit 1
    else
      :
    fi
    if printf 'type letter = A | B | C\nwrite_byte (match B with A -> 88 | other -> 88 | B -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > bad-nonfinal-default.mzbc; then
      exit 1
    else
      :
    fi
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/multi-adt.ml > compiled-multi-adt.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-multi-adt.mzbc)"
    test "$actual" = OK
    printf 'type letter = A | B | C\nwrite_byte (match C with A -> 88 | B -> 88 | C -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-match-three-direct.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-match-three-direct.mzbc)"
    test "$actual" = O
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/match-three.ml > compiled-match-three.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-match-three.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/match-four.ml > compiled-match-four.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-match-four.mzbc)"
    test "$actual" = O
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/match-six.ml > compiled-match-six.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-match-six.mzbc)"
    test "$actual" = O
    printf 'type letter = A | B | C | D | E | F | G\nwrite_byte (match G with A -> 88 | B -> 88 | C -> 88 | D -> 88 | E -> 88 | F -> 88 | G -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-match-seven.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-match-seven.mzbc)"
    test "$actual" = O
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/adt-tuple-payload.ml > compiled-adt-tuple-payload.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-adt-tuple-payload.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/adt-pattern-tuple.ml > compiled-adt-pattern-tuple.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-adt-pattern-tuple.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/adt-pattern-tuple-wildcard.ml > compiled-adt-pattern-tuple-wildcard.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-adt-pattern-tuple-wildcard.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/adt-pattern-nested-tuple.ml > compiled-adt-pattern-nested-tuple.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-adt-pattern-nested-tuple.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/adt-recursion.ml > compiled-adt-recursion.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-adt-recursion.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/cell.ml > compiled-cell.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-cell.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/record.ml > compiled-record.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-record.mzbc)"
    test "$actual" = O
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/record-three.ml > compiled-record-three.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-record-three.mzbc)"
    test "$actual" = O
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/top-level-defs.ml > compiled-top-level-defs.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-top-level-defs.mzbc)"
    test "$actual" = O
    printf 'let rec out ch = write_byte ch in out 79' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-final-call.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-final-call.mzbc)"
    test "$actual" = O
    printf 'let rec id x = x in write_byte (id 40 + 39)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-call-precedence.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-call-precedence.mzbc)"
    test "$actual" = O
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/function-string.ml > compiled-function-string.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-function-string.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/function-and.ml > compiled-function-and.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-function-and.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/function-and-three.ml > compiled-function-and-three.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-function-and-three.mzbc)"
    test "$actual" = OK
    ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${testsRoot}/mlc/read-byte.ml > compiled-read-byte.mzbc
    actual="$(printf O | ${mzvmSeedM2}/bin/mzvm-seed compiled-read-byte.mzbc)"
    test "$actual" = OK
    printf 'let bytes = Bytes.create 3 in let zero = 0 in let _ = bytes.[zero] <- 79 in let _ = bytes.(zero + 1) <- 75 in let _ = bytes.[2] <- 10 in let _ = write_byte bytes.[0] in let _ = write_byte bytes.(1) in write_byte bytes.[2]' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-dynamic-bytes.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-dynamic-bytes.mzbc)"
    test "$actual" = OK
  '';
  installScript = ''
    install -Dm644 mlc.byte "$out/share/mlc/mlc.byte"
    install -Dm644 compiled.mzbc "$out/share/mlc/compiled.mzbc"
    install -Dm644 compiled-char.mzbc "$out/share/mlc/compiled-char.mzbc"
    install -Dm644 compiled-decimal-char.mzbc "$out/share/mlc/compiled-decimal-char.mzbc"
    install -Dm644 compiled-string.mzbc "$out/share/mlc/compiled-string.mzbc"
    install -Dm644 compiled-debug-byte.mzbc "$out/share/mlc/compiled-debug-byte.mzbc"
    install -Dm644 compiled-debug-string.mzbc "$out/share/mlc/compiled-debug-string.mzbc"
    install -Dm644 compiled-let.mzbc "$out/share/mlc/compiled-let.mzbc"
    install -Dm644 compiled-let2.mzbc "$out/share/mlc/compiled-let2.mzbc"
    install -Dm644 compiled-let3.mzbc "$out/share/mlc/compiled-let3.mzbc"
    install -Dm644 compiled-paren-let.mzbc "$out/share/mlc/compiled-paren-let.mzbc"
    install -Dm644 compiled-shadow.mzbc "$out/share/mlc/compiled-shadow.mzbc"
    install -Dm644 compiled-keyword-prefix-if.mzbc "$out/share/mlc/compiled-keyword-prefix-if.mzbc"
    install -Dm644 compiled-keyword-prefix-let.mzbc "$out/share/mlc/compiled-keyword-prefix-let.mzbc"
    install -Dm644 compiled-keyword-prefix-infix.mzbc "$out/share/mlc/compiled-keyword-prefix-infix.mzbc"
    install -Dm644 compiled-sub.mzbc "$out/share/mlc/compiled-sub.mzbc"
    install -Dm644 compiled-mul.mzbc "$out/share/mlc/compiled-mul.mzbc"
    install -Dm644 compiled-div.mzbc "$out/share/mlc/compiled-div.mzbc"
    install -Dm644 compiled-if-true.mzbc "$out/share/mlc/compiled-if-true.mzbc"
    install -Dm644 compiled-if-false.mzbc "$out/share/mlc/compiled-if-false.mzbc"
    install -Dm644 compiled-if-lt-true.mzbc "$out/share/mlc/compiled-if-lt-true.mzbc"
    install -Dm644 compiled-if-lt-false.mzbc "$out/share/mlc/compiled-if-lt-false.mzbc"
    install -Dm644 compiled-if-eq-true.mzbc "$out/share/mlc/compiled-if-eq-true.mzbc"
    install -Dm644 compiled-if-eq-false.mzbc "$out/share/mlc/compiled-if-eq-false.mzbc"
    install -Dm644 compiled-if-ne.mzbc "$out/share/mlc/compiled-if-ne.mzbc"
    install -Dm644 compiled-if-le.mzbc "$out/share/mlc/compiled-if-le.mzbc"
    install -Dm644 compiled-if-gt.mzbc "$out/share/mlc/compiled-if-gt.mzbc"
    install -Dm644 compiled-if-ge.mzbc "$out/share/mlc/compiled-if-ge.mzbc"
    install -Dm644 compiled-adt.mzbc "$out/share/mlc/compiled-adt.mzbc"
    install -Dm644 compiled-match.mzbc "$out/share/mlc/compiled-match.mzbc"
    install -Dm644 compiled-wildcard-match.mzbc "$out/share/mlc/compiled-wildcard-match.mzbc"
    install -Dm644 compiled-match-bind-default.mzbc "$out/share/mlc/compiled-match-bind-default.mzbc"
    install -Dm644 compiled-multi-adt.mzbc "$out/share/mlc/compiled-multi-adt.mzbc"
    install -Dm644 compiled-match-three-direct.mzbc "$out/share/mlc/compiled-match-three-direct.mzbc"
    install -Dm644 compiled-match-three.mzbc "$out/share/mlc/compiled-match-three.mzbc"
    install -Dm644 compiled-match-six.mzbc "$out/share/mlc/compiled-match-six.mzbc"
    install -Dm644 compiled-match-seven.mzbc "$out/share/mlc/compiled-match-seven.mzbc"
    install -Dm644 compiled-adt-tuple-payload.mzbc "$out/share/mlc/compiled-adt-tuple-payload.mzbc"
    install -Dm644 compiled-adt-pattern-tuple.mzbc "$out/share/mlc/compiled-adt-pattern-tuple.mzbc"
    install -Dm644 compiled-adt-pattern-tuple-wildcard.mzbc "$out/share/mlc/compiled-adt-pattern-tuple-wildcard.mzbc"
    install -Dm644 compiled-adt-recursion.mzbc "$out/share/mlc/compiled-adt-recursion.mzbc"
    install -Dm644 compiled-final-call.mzbc "$out/share/mlc/compiled-final-call.mzbc"
    install -Dm644 compiled-call-precedence.mzbc "$out/share/mlc/compiled-call-precedence.mzbc"
    install -Dm644 compiled-function-string.mzbc "$out/share/mlc/compiled-function-string.mzbc"
    install -Dm644 compiled-function-and.mzbc "$out/share/mlc/compiled-function-and.mzbc"
    install -Dm644 compiled-function-and-three.mzbc "$out/share/mlc/compiled-function-and-three.mzbc"
    install -Dm644 compiled-read-byte.mzbc "$out/share/mlc/compiled-read-byte.mzbc"
    install -Dm644 compiled-dynamic-bytes.mzbc "$out/share/mlc/compiled-dynamic-bytes.mzbc"
    install -Dm644 compiled-record-three.mzbc "$out/share/mlc/compiled-record-three.mzbc"
  '';
}
