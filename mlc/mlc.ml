(* Bootstrap compiler spine.

   This is still far smaller than the real compiler, but it now follows the
   first compiler-shaped path: lex bytes from a source string, parse tokens
   into an expression ADT, and emit bytecode-side effects from that AST.
*)

type token = TokEof | TokInt of int
type expr = EBad | EByte of int

let rec is_digit ch =
  if ch < 48 then 0 else if ch > 57 then 0 else 1
in
let rec lex input =
  let (src, pos) = input in
  let ch = src.[pos] in
  if is_digit ch then TokInt (ch - 48) else TokEof
in
let rec parse_ones input =
  let (src, tens) = input in
  match lex (src, 1) with
    TokInt ones -> EByte (tens * 10 + ones)
  | _ -> EBad
in
let rec parse_byte src =
  match lex (src, 0) with
    TokInt tens -> parse_ones (src, tens)
  | _ -> EBad
in
let rec emit expr =
  match expr with
    EByte value -> value
  | _ -> 88
in
let text = "79" in
let newline = Bytes.create 1 in
newline.[0] <- 10;
let first = parse_ones (text, 7) in
let second = parse_ones ("75", 7) in
let _ = write_byte (emit first) in
let _ = write_byte (emit second) in
write_byte newline.[0]
