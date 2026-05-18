(* Bootstrap compiler spine.

   This is still far smaller than the real compiler, but it now follows the
   first compiler-shaped path: lex bytes from a source string, parse tokens
   into an expression ADT, and emit bytecode-side effects from that AST.
*)

type token = TokEof | TokInt of int | TokPlus of int
type parsed = PBad | PExpr of int
type expr = EBad | EByte of int | EAdd of int

let rec is_digit ch =
  if ch < 48 then 0 else if ch > 57 then 0 else 1
in
let rec lex input =
  let (src, pos) = input in
  if pos < String.length src then
    let ch = src.[pos] in
    if is_digit ch then TokInt (ch - 48, pos + 1)
    else if ch == 43 then TokPlus (pos + 1)
    else TokEof
  else TokEof
in
let rec parse_two input =
  let (src, pos) = input in
  match lex (src, pos) with
    TokInt first ->
      let (tens, next) = first in
      (match lex (src, next) with
        TokInt second ->
          let (ones, done_pos) = second in
          PExpr (EByte (tens * 10 + ones), done_pos)
      | TokEof -> PBad)
  | TokEof -> PBad
in
let rec parse_expr src =
  match parse_two (src, 0) with
    PExpr first ->
      let (lhs, pos) = first in
      (match lex (src, pos) with
        TokPlus next ->
          (match parse_two (src, next) with
            PExpr second ->
              let (rhs, done_pos) = second in
              EAdd (lhs, rhs)
          | PBad -> EBad)
      | TokEof -> lhs)
  | PBad -> EBad
in
let rec emit expr =
  match expr with
    EByte value -> value
  | EAdd pair ->
      let (lhs, rhs) = pair in
      emit lhs + emit rhs
  | EBad -> 88
in
let text = "40+39" in
let newline = Bytes.create 1 in
newline.[0] <- 10;
let first = parse_expr text in
let second = parse_expr "75" in
let _ = write_byte (emit first) in
let _ = write_byte (emit second) in
write_byte newline.[0]
