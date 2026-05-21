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
        printf 'type point = { x: int; y: int }\nlet p = { x = 40; y = 39 }\nwrite_byte (p.x + p.y)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-record-two.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-record-two.mzbc)"
        test "$actual" = O
        printf 'type triple = { a: int; b: int; c: int }\nlet t = { a = 40; b = 35; c = 4 }\nwrite_byte (t.a + t.b + t.c)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-record-three.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-record-three.mzbc)"
        test "$actual" = O
        printf 'type flagged = { yes: bool; value: int }\nlet f = { yes = true; value = 79 }\nwrite_byte (if f.yes then f.value else 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-record-bool-field.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-record-bool-field.mzbc)"
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
        printf 'let rec even n = if n = 0 then 79 else odd (n - 1)\nand odd n = if n = 0 then 88 else even (n - 1)\nin\nwrite_byte (even 4); write_byte (odd 3)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-let-rec-and.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-let-rec-and.mzbc)"
        test "$actual" = OO
        printf 'let rec first n = if n = 0 then 79 else second (n - 1)\nand second n = if n = 0 then 88 else third (n - 1)\nand third n = if n = 0 then 75 else first (n - 1)\nin\nwrite_byte (first 3); write_byte (third 0)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-let-rec-and-three.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-let-rec-and-three.mzbc)"
        test "$actual" = OK
        printf 'type byte = Byte of int | Empty\nwrite_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-leading-type.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-leading-type.mzbc)"
        test "$actual" = O
        printf 'type left = L | LL of int\ntype right = R | RR of int\nlet x = 79\nwrite_byte x' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-leading-types.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-leading-types.mzbc)"
        test "$actual" = O
        printf 'type maybe = None | Some of int\ntype box = Box of maybe | Empty\nwrite_byte (match Box (Some 79) with | Box value -> (match value with | Some ch -> ch | None -> 88) | Empty -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-cross-adt-payload.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-cross-adt-payload.mzbc)"
        test "$actual" = O
        printf 'type byte = Byte of int | Empty\nlet x = Byte 79\nwrite_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-unary-ctor.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-unary-ctor.mzbc)"
        test "$actual" = O
        printf 'type byte = Byte of int | Empty\nlet x = Empty\nwrite_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-nullary-ctor.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-nullary-ctor.mzbc)"
        test "$actual" = O
        printf "type flag = Yes | No\nwrite_byte (match Yes with | Yes -> 'O' | No -> 'X')" | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-yes.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-yes.mzbc)"
        test "$actual" = O
        printf "type flag = Yes | No\nwrite_byte (match No with | Yes -> 'X' | No -> 'O')" | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-no.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-no.mzbc)"
        test "$actual" = O
        printf "type flag = Yes | No\nlet y = 'O' in write_byte (match No with | Yes -> 'X' | No -> y)" | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-env.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-env.mzbc)"
        test "$actual" = O
        printf 'type letter = A | B | C\nwrite_byte (match C with | A -> 88 | B -> 88 | C -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-three.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-three.mzbc)"
        test "$actual" = O
        printf 'type byte = Byte of int | Empty | Other\nwrite_byte (match Byte 79 with | Empty -> 88 | Byte x -> x | _ -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-three-payload.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-three-payload.mzbc)"
        test "$actual" = O
        printf 'type letter = A | B | C | D\nwrite_byte (match D with | A -> 88 | B -> 88 | C -> 88 | D -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-four.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-four.mzbc)"
        test "$actual" = O
        printf 'type letter = A | B of int | C | D of int | E | F of int\nwrite_byte (match F 79 with | A -> 88 | B x -> x | C -> 88 | D y -> y | E -> 88 | F z -> z)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-six-payload.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-six-payload.mzbc)"
        test "$actual" = O
        printf 'type letter = A | B | C | D | E | F | G\nwrite_byte (match G with | A -> 88 | B -> 88 | C -> 88 | D -> 88 | E -> 88 | F -> 88 | G -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-seven.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-seven.mzbc)"
        test "$actual" = O
        printf 'type byte = Byte of int | Empty\nwrite_byte (match Byte 79 with | Byte x -> x | Empty -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-payload-first.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-payload-first.mzbc)"
        test "$actual" = O
        printf 'type byte = Empty | Byte of int\nwrite_byte (match Byte 79 with | Empty -> 88 | Byte x -> x)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-payload-second.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-payload-second.mzbc)"
        test "$actual" = O
        printf 'type byte = Empty | Byte of int\nlet y = 1 in write_byte (match Byte 78 with | Empty -> 88 | Byte x -> x + y)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-payload-env.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-payload-env.mzbc)"
        test "$actual" = O
        printf 'type byte = Byte of int | Empty | Other\nwrite_byte (match Other with | Byte x -> x | _ -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-wildcard.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-wildcard.mzbc)"
        test "$actual" = O
        printf 'type byte = Byte of int | Empty\nwrite_byte (match Empty with | Byte x -> x | other -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-default-var.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-default-var.mzbc)"
        test "$actual" = O
        printf 'type pair = Pair of int * int | Empty\nwrite_byte (match Pair (40, 39) with | Pair (x, y) -> x + y | Empty -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-tuple-first.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-tuple-first.mzbc)"
        test "$actual" = O
        printf 'type pair = Empty | Pair of int * int\nwrite_byte (match Pair (40, 39) with | Empty -> 88 | Pair (x, y) -> x + y)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-tuple-second.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-tuple-second.mzbc)"
        test "$actual" = O
        printf 'type pair = Empty | Pair of int * int\nlet z = 1 in write_byte (match Pair (39, 39) with | Empty -> 88 | Pair (x, y) -> x + y + z)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-tuple-env.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-tuple-env.mzbc)"
        test "$actual" = O
        printf 'type pair = Pair of int * int | Empty\nwrite_byte (match Pair (40, 39) with | Pair (_, y) -> y + 40 | Empty -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-tuple-wildcard-left.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-tuple-wildcard-left.mzbc)"
        test "$actual" = O
        printf 'type pair = Pair of int * int | Empty\nwrite_byte (match Pair (40, 39) with | Pair (x, _) -> x + 39 | Empty -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-tuple-wildcard-right.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-tuple-wildcard-right.mzbc)"
        test "$actual" = O
        printf 'type byte = Byte of int | Empty\nwrite_byte (match Byte 88 with | Byte _ -> 79 | Empty -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-payload-wildcard.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-payload-wildcard.mzbc)"
        test "$actual" = O
        printf 'type expr = ELeft of (int * int) * int | ERight of int * (int * int) | EBad\nlet left = match ELeft ((40, 88), 39) with | ELeft pair -> let (nested, rhs) = pair in let (lhs, _) = nested in lhs + rhs | _ -> 88\nlet right = match ERight (40, (88, 35)) with | ERight pair -> let (lhs, nested) = pair in let (_, rhs) = nested in lhs + rhs | _ -> 88\nwrite_byte left; write_byte right' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-nested-pair-payload.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-nested-pair-payload.mzbc)"
        test "$actual" = OK
        printf 'type expr = ELeft of (int * int) * int | EBad\nwrite_byte (match ELeft ((40, 88), 39) with | ELeft ((lhs, _), rhs) -> lhs + rhs | EBad -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-nested-tuple-left.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-nested-tuple-left.mzbc)"
        test "$actual" = O
        printf 'type expr = ERight of int * (int * int) | EBad\nwrite_byte (match ERight (40, (88, 39)) with | ERight (lhs, (_, rhs)) -> lhs + rhs | EBad -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-nested-tuple-right.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-adt-match-nested-tuple-right.mzbc)"
        test "$actual" = O
        printf 'let (x, y) = (40, 39) in write_byte (x + y)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-pair-let.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-pair-let.mzbc)"
        test "$actual" = O
        printf 'let (_, y) = (88, 79) in write_byte y' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-pair-let-wildcard-left.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-pair-let-wildcard-left.mzbc)"
        test "$actual" = O
        printf 'let (x, _) = (79, 88) in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-pair-let-wildcard-right.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-pair-let-wildcard-right.mzbc)"
        test "$actual" = O
        printf 'let _ = write_byte 79 in write_byte 75' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-let-wildcard.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-let-wildcard.mzbc)"
        test "$actual" = OK
        printf 'let (x, y) = (40, 39)\nwrite_byte (x + y)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-top-pair-def.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-top-pair-def.mzbc)"
        test "$actual" = O
        printf 'let _ = write_byte 79\nwrite_byte 75' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-top-let-wildcard.mzbc
        actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-top-let-wildcard.mzbc)"
        test "$actual" = OK
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
        if printf 'let _ = 79 in write_byte _' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-let-wildcard-not-bound-error.mzbc; then
          exit 1
        fi
        if printf 'let (_, y) = (40, 39) in write_byte _' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-pair-let-wildcard-not-bound-error.mzbc; then
          exit 1
        fi
        if printf 'let x = true\nwrite_byte x' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-top-def-type-error.mzbc; then
          exit 1
        fi
        if printf 'type point = { x: int; y: int }\nlet p = { x = true; y = 39 }\nwrite_byte p.y' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-record-field-type-error.mzbc; then
          exit 1
        fi
        if printf 'type left = { x: int; y: int }\ntype right = { a: int; b: int }\nlet p = { x = 40; b = 39 }\nwrite_byte p.x' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-record-mixed-fields-error.mzbc; then
          exit 1
        fi
        if printf 'type point = { x: int; y: int }\nlet p = { x = 40; y = 39 }\nwrite_byte p.z' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-record-unknown-field-error.mzbc; then
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
        if printf 'type byte = Byte of int | Empty\nwrite_byte (Byte 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-write-byte-type-error.mzbc; then
          exit 1
        fi
        if printf 'type byte = Byte of int | Empty\nlet x = Byte "x"\nwrite_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-payload-type-error.mzbc; then
          exit 1
        fi
        if printf 'type box = Box of missing | Empty\nwrite_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-unknown-payload-type-error.mzbc; then
          exit 1
        fi
        if printf 'type flag = Yes | No\nwrite_byte (match Yes with | Yes -> 79 | No -> true)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-branch-type-error.mzbc; then
          exit 1
        fi
        if printf "type byte = Byte of int | Empty\nwrite_byte (match Empty with | Byte -> 'X' | Empty -> 'O')" | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-unary-pattern-error.mzbc; then
          exit 1
        fi
        if printf 'type byte = Byte of int | Empty\nwrite_byte (match Byte 79 with | Byte -> 88 | Empty -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-missing-payload-error.mzbc; then
          exit 1
        fi
        if printf 'type flag = Yes | No\nwrite_byte (match Yes with | Yes x -> x | No -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-extra-payload-error.mzbc; then
          exit 1
        fi
        if printf 'type byte = Byte of int | Empty\nwrite_byte (match 79 with | Byte x -> x | Empty -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-scrutinee-type-error.mzbc; then
          exit 1
        fi
        if printf 'type byte = Byte of int | Empty\nwrite_byte (match Empty with | Byte x -> x | other -> other)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-default-result-type-error.mzbc; then
          exit 1
        fi
        if printf 'type byte = Byte of int | Empty\nwrite_byte (match Empty with | Byte x -> x | other y -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-default-extra-bind-error.mzbc; then
          exit 1
        fi
        if printf 'type letter = A | B | C\nwrite_byte (match B with | A -> 88 | other -> 79 | B -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-nonfinal-default-error.mzbc; then
          exit 1
        fi
        if printf 'type byte = Byte of int | Empty\nwrite_byte (match Empty with | Byte x -> x | Missing -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-unknown-ctor-error.mzbc; then
          exit 1
        fi
        if printf 'type byte = Byte of int | Empty\nwrite_byte (match Byte 79 with | Byte (x, y) -> x | Empty -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-tuple-on-int-error.mzbc; then
          exit 1
        fi
        if printf 'type pair = Pair of int * int | Empty\nlet p = (40,39) in let v = Pair p in write_byte (match v with | Pair x -> x | Empty -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-pair-missing-tuple-error.mzbc; then
          exit 1
        fi
        if printf 'type pair = Pair of int * int | Empty\nwrite_byte (match Pair (40, 39) with | Pair ((x, y), z) -> x | Empty -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-nested-left-on-flat-error.mzbc; then
          exit 1
        fi
        if printf 'type pair = Pair of int * int | Empty\nwrite_byte (match Pair (40, 39) with | Pair (x, (y, z)) -> x | Empty -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-nested-right-on-flat-error.mzbc; then
          exit 1
        fi
        if printf 'type pair = Pair of int * int | Empty\nlet v = Pair 79 in write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-pair-payload-type-error.mzbc; then
          exit 1
        fi
        if printf 'type expr = ELeft of (int * int) * int | EBad\nlet v = ELeft (40, 39) in write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-nested-pair-payload-type-error.mzbc; then
          exit 1
        fi
        if printf 'type pair = Pair of int * int | Empty\nwrite_byte (match Pair (40, 39) with | Pair (_, y) -> _ | Empty -> 88)' | ${mzvmSeedM2}/bin/mzvm-seed 03-ast-compiler.mzbc > 03-adt-match-wildcard-not-bound-error.mzbc; then
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
    install -Dm644 03-record-two.mzbc "$out/share/mlc/stages/03-record-two.mzbc"
    install -Dm644 03-record-three.mzbc "$out/share/mlc/stages/03-record-three.mzbc"
    install -Dm644 03-record-bool-field.mzbc "$out/share/mlc/stages/03-record-bool-field.mzbc"
    install -Dm644 03-let-rec-direct.mzbc "$out/share/mlc/stages/03-let-rec-direct.mzbc"
    install -Dm644 03-let-rec-after-let.mzbc "$out/share/mlc/stages/03-let-rec-after-let.mzbc"
    install -Dm644 03-let-rec-nested-call.mzbc "$out/share/mlc/stages/03-let-rec-nested-call.mzbc"
    install -Dm644 03-let-rec-and.mzbc "$out/share/mlc/stages/03-let-rec-and.mzbc"
    install -Dm644 03-let-rec-and-three.mzbc "$out/share/mlc/stages/03-let-rec-and-three.mzbc"
    install -Dm644 03-leading-type.mzbc "$out/share/mlc/stages/03-leading-type.mzbc"
    install -Dm644 03-leading-types.mzbc "$out/share/mlc/stages/03-leading-types.mzbc"
    install -Dm644 03-cross-adt-payload.mzbc "$out/share/mlc/stages/03-cross-adt-payload.mzbc"
    install -Dm644 03-adt-unary-ctor.mzbc "$out/share/mlc/stages/03-adt-unary-ctor.mzbc"
    install -Dm644 03-adt-nullary-ctor.mzbc "$out/share/mlc/stages/03-adt-nullary-ctor.mzbc"
    install -Dm644 03-adt-match-yes.mzbc "$out/share/mlc/stages/03-adt-match-yes.mzbc"
    install -Dm644 03-adt-match-no.mzbc "$out/share/mlc/stages/03-adt-match-no.mzbc"
    install -Dm644 03-adt-match-env.mzbc "$out/share/mlc/stages/03-adt-match-env.mzbc"
    install -Dm644 03-adt-match-three.mzbc "$out/share/mlc/stages/03-adt-match-three.mzbc"
    install -Dm644 03-adt-match-three-payload.mzbc "$out/share/mlc/stages/03-adt-match-three-payload.mzbc"
    install -Dm644 03-adt-match-four.mzbc "$out/share/mlc/stages/03-adt-match-four.mzbc"
    install -Dm644 03-adt-match-six-payload.mzbc "$out/share/mlc/stages/03-adt-match-six-payload.mzbc"
    install -Dm644 03-adt-match-seven.mzbc "$out/share/mlc/stages/03-adt-match-seven.mzbc"
    install -Dm644 03-adt-match-payload-first.mzbc "$out/share/mlc/stages/03-adt-match-payload-first.mzbc"
    install -Dm644 03-adt-match-payload-second.mzbc "$out/share/mlc/stages/03-adt-match-payload-second.mzbc"
    install -Dm644 03-adt-match-payload-env.mzbc "$out/share/mlc/stages/03-adt-match-payload-env.mzbc"
    install -Dm644 03-adt-match-wildcard.mzbc "$out/share/mlc/stages/03-adt-match-wildcard.mzbc"
    install -Dm644 03-adt-match-default-var.mzbc "$out/share/mlc/stages/03-adt-match-default-var.mzbc"
    install -Dm644 03-adt-match-tuple-first.mzbc "$out/share/mlc/stages/03-adt-match-tuple-first.mzbc"
    install -Dm644 03-adt-match-tuple-second.mzbc "$out/share/mlc/stages/03-adt-match-tuple-second.mzbc"
    install -Dm644 03-adt-match-tuple-env.mzbc "$out/share/mlc/stages/03-adt-match-tuple-env.mzbc"
    install -Dm644 03-adt-match-tuple-wildcard-left.mzbc "$out/share/mlc/stages/03-adt-match-tuple-wildcard-left.mzbc"
    install -Dm644 03-adt-match-tuple-wildcard-right.mzbc "$out/share/mlc/stages/03-adt-match-tuple-wildcard-right.mzbc"
    install -Dm644 03-adt-match-payload-wildcard.mzbc "$out/share/mlc/stages/03-adt-match-payload-wildcard.mzbc"
    install -Dm644 03-adt-nested-pair-payload.mzbc "$out/share/mlc/stages/03-adt-nested-pair-payload.mzbc"
    install -Dm644 03-adt-match-nested-tuple-left.mzbc "$out/share/mlc/stages/03-adt-match-nested-tuple-left.mzbc"
    install -Dm644 03-adt-match-nested-tuple-right.mzbc "$out/share/mlc/stages/03-adt-match-nested-tuple-right.mzbc"
    install -Dm644 03-pair-let.mzbc "$out/share/mlc/stages/03-pair-let.mzbc"
    install -Dm644 03-pair-let-wildcard-left.mzbc "$out/share/mlc/stages/03-pair-let-wildcard-left.mzbc"
    install -Dm644 03-pair-let-wildcard-right.mzbc "$out/share/mlc/stages/03-pair-let-wildcard-right.mzbc"
    install -Dm644 03-let-wildcard.mzbc "$out/share/mlc/stages/03-let-wildcard.mzbc"
    install -Dm644 03-top-pair-def.mzbc "$out/share/mlc/stages/03-top-pair-def.mzbc"
    install -Dm644 03-top-let-wildcard.mzbc "$out/share/mlc/stages/03-top-let-wildcard.mzbc"
    install -Dm644 03-sequence.mzbc "$out/share/mlc/stages/03-sequence.mzbc"
  '';
}
