{
  stageRun,
  mlcSrc,
  mzvmSeedM2,
  mlcByte,
}:

stageRun {
  pname = "mlc-stage-03-ast-compiler";
  nativeBuildInputs = [
    mzvmSeedM2
  ];
  description = "AST-building and type-checking ML successor stage";
  buildScript = ''
        cp ${mlcSrc}/stages/03-ast-compiler.ml 03-ast-compiler.ml
        ${mzvmSeedM2}/bin/mzvm-seed ${mlcByte} < 03-ast-compiler.ml > 03-ast-compiler.mzbc
        printf 'write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-direct.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-direct.mzbc)"
        test "$actual" = O
        printf 'write_byte read_byte' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-read-byte.mzbc
        actual="$(printf O | ${mzvmSeedM2}/bin/mzvm-seed 03-read-byte.mzbc)"
        test "$actual" = O
        printf 'exit 7' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-exit.mzbc
        if ${mzvmSeedM2}/bin/mzvm-seed 03-exit.mzbc; then
          exit 1
        else
          status=$?
          test "$status" = 7
        fi
        printf 'write_string "OK"' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-write-string.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-write-string.mzbc)"
        test "$actual" = OK
        printf 'write_byte (String.length "OK" + 77)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-string-length-literal.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-string-length-literal.mzbc)"
        test "$actual" = O
        printf 'write_byte (String.length "" + 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-empty-string-length-literal.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-empty-string-length-literal.mzbc)"
        test "$actual" = O
        printf 'let s = "OK"\nwrite_byte (String.length s + 77)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-string-binding-length.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-string-binding-length.mzbc)"
        test "$actual" = O
        printf 'let b = Bytes.create 3\nwrite_byte (Bytes.length b + 76)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-bytes-create-length.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-bytes-create-length.mzbc)"
        test "$actual" = O
        printf 'let b = Bytes.create 1 + 1\nb.[0] <- 79; b.[1] <- 75; write_byte b.[0]; write_byte b.[1]' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-bytes-create-expr.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-bytes-create-expr.mzbc)"
        test "$actual" = OK
        printf 'let a = Array.create 2 88\na.(0) <- 79; a.(1) <- 75; write_byte a.(0); write_byte a.(1)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-array-create-index-set.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-array-create-index-set.mzbc)"
        test "$actual" = OK
        printf 'let n = 2\nlet init = 88\nlet a = Array.create n init\na.(0) <- 79; a.(1) <- 75; write_byte a.(0); write_byte a.(1)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-array-create-var.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-array-create-var.mzbc)"
        test "$actual" = OK
        printf 'let s = "OK"\nwrite_byte s.[1]' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-string-index.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-string-index.mzbc)"
        test "$actual" = K
        printf 'let b = Bytes.create 2\nb.[0] <- 79; b.[1] <- 75; write_byte b.[0]; write_byte b.[1]' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-bytes-index-set.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-bytes-index-set.mzbc)"
        test "$actual" = OK
        printf 'let b = Bytes.create 2\nlet i = 1\nb.[i] <- 79; write_byte b.[i]' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-bytes-index-var.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-bytes-index-var.mzbc)"
        test "$actual" = O
        printf 'let b = Bytes.create 3\nlet i = 1\nb.[i + 1] <- 75; b.[0] <- 79; write_byte b.[0]; write_byte b.[i * 2]' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-bytes-index-expr.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-bytes-index-expr.mzbc)"
        test "$actual" = OK
        printf 'let b = Bytes.create 1\nb.[0] <- 40 + 39; write_byte b.[0]' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-bytes-set-expr.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-bytes-set-expr.mzbc)"
        test "$actual" = O
        printf "let b = Bytes.create 1\nb.[0] <- 'O'; write_byte b.[0]" | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-bytes-set-char.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-bytes-set-char.mzbc)"
        test "$actual" = O
        printf 'let c = Cell.create 88\nCell.set c 79; write_byte (Cell.get c)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-cell.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-cell.mzbc)"
        test "$actual" = O
        printf 'let c = Cell.create 0\nCell.set c 40 + 39; write_byte (Cell.get c)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-cell-set-expr.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-cell-set-expr.mzbc)"
        test "$actual" = O
        printf 'let inner = Cell.create 88\nlet c = Cell.create inner\nCell.set inner 79; let got = Cell.get c in write_byte (Cell.get got)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-nested-cell.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-nested-cell.mzbc)"
        test "$actual" = O
        printf 'debug_string "TRACE"; write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-debug-string.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-debug-string.mzbc 2> 03-debug-string.err)"
        test "$actual" = O
        test "$(cat 03-debug-string.err)" = TRACE
        printf 'debug_byte 84; write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-debug-byte.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-debug-byte.mzbc 2> 03-debug-byte.err)"
        test "$actual" = O
        test "$(cat 03-debug-byte.err)" = T
        printf 'debug_int (40 + 2); write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-debug-int.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-debug-int.mzbc 2> 03-debug-int.err)"
        test "$actual" = O
        test "$(cat 03-debug-int.err)" = 42
        printf 'debug_printf "n=%%d" (40 + 2); write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-debug-printf.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-debug-printf.mzbc 2> 03-debug-printf.err)"
        test "$actual" = O
        test "$(cat 03-debug-printf.err)" = n=42
        printf '(); write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-unit.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-unit.mzbc)"
        test "$actual" = O
        printf "write_byte 'O'" | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-char.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-char.mzbc)"
        test "$actual" = O
        cat > 03-escaped-char.ml <<'EOF'
    write_byte (if '\n' == 10 then 79 else 88); write_byte (if '\\' == 92 then 75 else 88)
    EOF
        ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc < 03-escaped-char.ml > 03-escaped-char.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-escaped-char.mzbc)"
        test "$actual" = OK
        printf 'write_byte (40 + 39)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-add.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-add.mzbc)"
        test "$actual" = O
        printf 'write_byte (100 - 20 - 1)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-sub.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-sub.mzbc)"
        test "$actual" = O
        printf 'write_byte (7 * 11 + 2)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-mul.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-mul.mzbc)"
        test "$actual" = O
        printf 'write_byte (158 / 2)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-div.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-div.mzbc)"
        test "$actual" = O
        printf 'write_byte (-1 + 80); write_byte (if !false then 79 else 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-unary.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-unary.mzbc)"
        test "$actual" = OO
        printf "write_byte (if 1 == 1 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-if.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-if.mzbc)"
        test "$actual" = O
        printf "write_byte (if 1 = 1 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-if-ml-eq.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-if-ml-eq.mzbc)"
        test "$actual" = O
        printf "write_byte (if true then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-if-bool.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-if-bool.mzbc)"
        test "$actual" = O
        printf 'write_byte (if 40 != 39 then 79 else 88); write_byte (if 39 < 40 then 79 else 88); write_byte (if 40 <= 40 then 79 else 88); write_byte (if 40 > 39 then 79 else 88); write_byte (if 40 >= 40 then 79 else 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-comparison.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-comparison.mzbc)"
        test "$actual" = OOOOO
        printf 'write_byte (let x = 40 in x + 39)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-let.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-let.mzbc)"
        test "$actual" = O
        printf 'let x = 79 in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-top-let.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-top-let.mzbc)"
        test "$actual" = O
        printf 'let x = 40\nlet y = 39\nwrite_byte (x + y)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-top-defs.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-top-defs.mzbc)"
        test "$actual" = O
        printf 'let rec dec n = if n = 0 then 79 else dec (n - 1)\nwrite_byte (dec 3)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-let-rec-direct.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-let-rec-direct.mzbc)"
        test "$actual" = O
        printf 'let seed = 3\nlet rec dec n = if n = 0 then 79 else dec (n - 1)\nwrite_byte (dec seed)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-let-rec-after-let.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-let-rec-after-let.mzbc)"
        test "$actual" = O
        printf 'let rec id n = n\nlet rec out n = if n = 0 then id 79 else out (n - 1)\nwrite_byte (out 2)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-let-rec-nested-call.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-let-rec-nested-call.mzbc)"
        test "$actual" = O
        printf 'type byte = Byte of int | Empty\nwrite_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-leading-type.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-leading-type.mzbc)"
        test "$actual" = O
        printf 'type left = L | LL of int\ntype right = R | RR of int\nlet x = 79\nwrite_byte x' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-leading-types.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-leading-types.mzbc)"
        test "$actual" = O
        printf 'let (x, y) = (40, 39) in write_byte (x + y)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-pair-let.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-pair-let.mzbc)"
        test "$actual" = O
        printf 'let (x, y) = (40, 39)\nwrite_byte (x + y)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-top-pair-def.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-top-pair-def.mzbc)"
        test "$actual" = O
        printf 'write_byte 79; write_byte 75; write_byte 10' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-sequence.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-sequence.mzbc)"
        test "$actual" = OK
        if printf '40 + 39' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-top-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte 79 garbage' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-trailing.mzbc; then
          exit 1
        fi
        if printf 'write_byte (if 1 then 79 else 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-cond-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (if true then 79 else write_byte 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-branch-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (true - 1)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-arithmetic-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (!1)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-unary-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (if true = 1 then 79 else 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-ml-eq-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (if true < false then 79 else 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-comparison-type-error.mzbc; then
          exit 1
        fi
        if printf 'let (x, y) = 79 in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-pair-type-error.mzbc; then
          exit 1
        fi
        if printf 'let x = true\nwrite_byte x' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-top-def-type-error.mzbc; then
          exit 1
        fi
        if printf 'let rec bad n = true\nwrite_byte (bad 0)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-let-rec-return-type-error.mzbc; then
          exit 1
        fi
        if printf 'let rec id n = n\nwrite_byte (id "x")' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-let-rec-arg-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (missing 1)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-direct-call-name-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (String.length 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-string-length-literal-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte "OK"' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-string-write-byte-type-error.mzbc; then
          exit 1
        fi
        if printf 'exit "OK"' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-exit-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (exit 1)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-exit-result-type-error.mzbc; then
          exit 1
        fi
        if printf 'let s = 79\nwrite_byte (String.length s)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-string-length-var-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (Bytes.create 3)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-bytes-create-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (Bytes.length "OK")' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-bytes-length-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (Array.create 1 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-array-create-type-error.mzbc; then
          exit 1
        fi
        if printf 'let a = Array.create 1 "x"\nwrite_byte a.(0)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-array-index-type-error.mzbc; then
          exit 1
        fi
        if printf 'let a = Array.create 1 79\na.(0) <- "x"' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-array-set-type-error.mzbc; then
          exit 1
        fi
        if printf 'let c = Cell.create (Cell.create 79)\nCell.set c (Cell.create "x")' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-nested-cell-set-type-error.mzbc; then
          exit 1
        fi
        if printf 'let a = Array.create 1 (Cell.create 79)\na.(0) <- Cell.create "x"' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-nested-array-set-type-error.mzbc; then
          exit 1
        fi
        if printf 'let s = "OK"\ns.[0] <- 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-string-index-set-type-error.mzbc; then
          exit 1
        fi
        if printf 'let b = Bytes.create 1\nb.["x"] <- 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-bytes-index-type-error.mzbc; then
          exit 1
        fi
        if printf 'write_byte (Cell.create 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-cell-create-type-error.mzbc; then
          exit 1
        fi
        if printf 'let c = Cell.create 79\nCell.set c "x"' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-cell-set-type-error.mzbc; then
          exit 1
        fi
        if printf 'Cell.get 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-cell-get-type-error.mzbc; then
          exit 1
        fi
        if printf '79; write_byte 75' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-sequence-type-error.mzbc; then
          exit 1
        fi
  '';
  installScript = ''
    install -Dm644 03-ast-compiler.ml "$out/share/mlc/stages/03-ast-compiler.ml"
    install -Dm644 03-ast-compiler.mzbc "$out/share/mlc/stages/03-ast-compiler.mzbc"
    install -Dm644 03-direct.mzbc "$out/share/mlc/stages/03-direct.mzbc"
    install -Dm644 03-read-byte.mzbc "$out/share/mlc/stages/03-read-byte.mzbc"
    install -Dm644 03-exit.mzbc "$out/share/mlc/stages/03-exit.mzbc"
    install -Dm644 03-write-string.mzbc "$out/share/mlc/stages/03-write-string.mzbc"
    install -Dm644 03-string-length-literal.mzbc "$out/share/mlc/stages/03-string-length-literal.mzbc"
    install -Dm644 03-empty-string-length-literal.mzbc "$out/share/mlc/stages/03-empty-string-length-literal.mzbc"
    install -Dm644 03-string-binding-length.mzbc "$out/share/mlc/stages/03-string-binding-length.mzbc"
    install -Dm644 03-bytes-create-length.mzbc "$out/share/mlc/stages/03-bytes-create-length.mzbc"
    install -Dm644 03-bytes-create-expr.mzbc "$out/share/mlc/stages/03-bytes-create-expr.mzbc"
    install -Dm644 03-array-create-index-set.mzbc "$out/share/mlc/stages/03-array-create-index-set.mzbc"
    install -Dm644 03-array-create-var.mzbc "$out/share/mlc/stages/03-array-create-var.mzbc"
    install -Dm644 03-string-index.mzbc "$out/share/mlc/stages/03-string-index.mzbc"
    install -Dm644 03-bytes-index-set.mzbc "$out/share/mlc/stages/03-bytes-index-set.mzbc"
    install -Dm644 03-bytes-index-var.mzbc "$out/share/mlc/stages/03-bytes-index-var.mzbc"
    install -Dm644 03-bytes-index-expr.mzbc "$out/share/mlc/stages/03-bytes-index-expr.mzbc"
    install -Dm644 03-bytes-set-expr.mzbc "$out/share/mlc/stages/03-bytes-set-expr.mzbc"
    install -Dm644 03-bytes-set-char.mzbc "$out/share/mlc/stages/03-bytes-set-char.mzbc"
    install -Dm644 03-cell.mzbc "$out/share/mlc/stages/03-cell.mzbc"
    install -Dm644 03-cell-set-expr.mzbc "$out/share/mlc/stages/03-cell-set-expr.mzbc"
    install -Dm644 03-nested-cell.mzbc "$out/share/mlc/stages/03-nested-cell.mzbc"
    install -Dm644 03-debug-string.mzbc "$out/share/mlc/stages/03-debug-string.mzbc"
    install -Dm644 03-debug-byte.mzbc "$out/share/mlc/stages/03-debug-byte.mzbc"
    install -Dm644 03-debug-int.mzbc "$out/share/mlc/stages/03-debug-int.mzbc"
    install -Dm644 03-debug-printf.mzbc "$out/share/mlc/stages/03-debug-printf.mzbc"
    install -Dm644 03-unit.mzbc "$out/share/mlc/stages/03-unit.mzbc"
    install -Dm644 03-char.mzbc "$out/share/mlc/stages/03-char.mzbc"
    install -Dm644 03-escaped-char.mzbc "$out/share/mlc/stages/03-escaped-char.mzbc"
    install -Dm644 03-add.mzbc "$out/share/mlc/stages/03-add.mzbc"
    install -Dm644 03-sub.mzbc "$out/share/mlc/stages/03-sub.mzbc"
    install -Dm644 03-mul.mzbc "$out/share/mlc/stages/03-mul.mzbc"
    install -Dm644 03-div.mzbc "$out/share/mlc/stages/03-div.mzbc"
    install -Dm644 03-unary.mzbc "$out/share/mlc/stages/03-unary.mzbc"
    install -Dm644 03-if.mzbc "$out/share/mlc/stages/03-if.mzbc"
    install -Dm644 03-if-ml-eq.mzbc "$out/share/mlc/stages/03-if-ml-eq.mzbc"
    install -Dm644 03-if-bool.mzbc "$out/share/mlc/stages/03-if-bool.mzbc"
    install -Dm644 03-comparison.mzbc "$out/share/mlc/stages/03-comparison.mzbc"
    install -Dm644 03-let.mzbc "$out/share/mlc/stages/03-let.mzbc"
    install -Dm644 03-top-let.mzbc "$out/share/mlc/stages/03-top-let.mzbc"
    install -Dm644 03-top-defs.mzbc "$out/share/mlc/stages/03-top-defs.mzbc"
    install -Dm644 03-let-rec-direct.mzbc "$out/share/mlc/stages/03-let-rec-direct.mzbc"
    install -Dm644 03-let-rec-after-let.mzbc "$out/share/mlc/stages/03-let-rec-after-let.mzbc"
    install -Dm644 03-let-rec-nested-call.mzbc "$out/share/mlc/stages/03-let-rec-nested-call.mzbc"
    install -Dm644 03-leading-type.mzbc "$out/share/mlc/stages/03-leading-type.mzbc"
    install -Dm644 03-leading-types.mzbc "$out/share/mlc/stages/03-leading-types.mzbc"
    install -Dm644 03-pair-let.mzbc "$out/share/mlc/stages/03-pair-let.mzbc"
    install -Dm644 03-top-pair-def.mzbc "$out/share/mlc/stages/03-top-pair-def.mzbc"
    install -Dm644 03-sequence.mzbc "$out/share/mlc/stages/03-sequence.mzbc"
  '';
}
