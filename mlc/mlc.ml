let rec byte n =
  n - (n / 256) * 256
in
let rec emit_u32 n =
  let _ = write_byte (byte n) in
  let _ = write_byte (byte (n / 256)) in
  let _ = write_byte (byte (n / 65536)) in
  write_byte (byte (n / 16777216))
in
let rec is_digit ch =
  if ch < 48 then 0 else if ch > 57 then 0 else 1
in
let rec read_all state =
  let (buf, pos) = state in
  let ch = read_byte in
  if ch < 0 then pos
  else
    let _ = buf.[pos] <- ch in
    read_all (buf, pos + 1)
in
let rec lex input =
  let (src, pos) = input in
  let ch = src.[pos] in
  if is_digit ch then (1, (ch - 48, pos + 1))
  else if ch == 43 then (2, pos + 1)
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
let rec eval expr =
  let (tag, payload) = expr in
  if tag == 1 then payload
  else if tag == 2 then
    let (lhs, rhs) = payload in
    let left = eval lhs in
    let right = eval rhs in
    (left + right)
  else 88
in
let rec emit_program value =
  let _ = write_byte 77 in
  let _ = write_byte 90 in
  let _ = write_byte 66 in
  let _ = write_byte 67 in
  let _ = emit_u32 1 in
  let _ = emit_u32 15 in
  let _ = emit_u32 3 in
  let _ = emit_u32 0 in
  let _ = write_byte 1 in
  let _ = emit_u32 value in
  let _ = write_byte 14 in
  let _ = emit_u32 1 in
  let _ = emit_u32 1 in
  write_byte 0
in
let source = Bytes.create 1024 in
let _ = read_all (source, 0) in
let expr = parse_expr source in
emit_program (eval expr)
