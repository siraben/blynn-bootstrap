(* Bootstrap compiler spine.

   This file is intentionally written in the seed core language: conditionals,
   let/let-rec, tuples, integers, strings/bytes, and direct calls. Full
   mini-OCaml pattern matching belongs in the compiler implemented here, not in
   the initial C seed parser.
*)

let rec is_digit ch =
  if ch < 48 then 0 else if ch > 57 then 0 else 1
in
let rec lex input =
  let (src, pos) = input in
  if pos < String.length src then
    let ch = src.[pos] in
    if is_digit ch then (1, (ch - 48, pos + 1))
    else if ch == 43 then (2, pos + 1)
    else (0, 0)
  else (0, 0)
in
let rec parse_two input =
  let (src, pos) = input in
  let first = lex (src, pos) in
  let (first_tag, first_payload) = first in
  if first_tag == 1 then
    let (tens, next) = first_payload in
    let second = lex (src, next) in
    let (second_tag, second_payload) = second in
    if second_tag == 1 then
      let (ones, done_pos) = second_payload in
      (1, ((1, tens * 10 + ones), done_pos))
    else (0, 0)
  else (0, 0)
in
let rec parse_expr src =
  let first = parse_two (src, 0) in
  let (first_tag, first_payload) = first in
  if first_tag == 1 then
    let (lhs, pos) = first_payload in
    let op = lex (src, pos) in
    let (op_tag, op_payload) = op in
    if op_tag == 2 then
      let second = parse_two (src, op_payload) in
      let (second_tag, second_payload) = second in
      if second_tag == 1 then
        let (rhs, done_pos) = second_payload in
        (2, (lhs, rhs))
      else (0, 0)
    else lhs
  else (0, 0)
in
let rec emit expr =
  let (tag, payload) = expr in
  if tag == 1 then payload
  else if tag == 2 then
    let (lhs, rhs) = payload in
    emit lhs + emit rhs
  else 88
in
let text = "40+39" in
let newline = Bytes.create 1 in
newline.[0] <- 10;
let first = parse_expr text in
let second = parse_expr "75" in
let _ = write_byte (emit first) in
let _ = write_byte (emit second) in
write_byte newline.[0]
