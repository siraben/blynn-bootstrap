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
let rec is_space ch =
  if ch == 32 then 1 else
  if ch == 9 then 1 else
  if ch == 10 then 1 else
  if ch == 13 then 1 else 0
in
let rec read_all state =
  let (buf, pos) = state in
  let ch = read_byte in
  if ch < 0 then pos
  else
    let _ = buf.[pos] <- ch in
    read_all (buf, pos + 1)
in
let rec skip_space input =
  let (src, pos) = input in
  if is_space (src.[pos]) then skip_space (src, pos + 1) else pos
in
let rec parse_number_loop state =
  let (src, pair) = state in
  let (acc, pos) = pair in
  let ch = src.[pos] in
  if is_digit ch then parse_number_loop (src, (acc * 10 + ch - 48, pos + 1))
  else (acc, pos)
in
let rec parse_number input =
  let (src, pos) = input in
  let pos = skip_space (src, pos) in
  let ch = src.[pos] in
  if is_digit ch then parse_number_loop (src, (ch - 48, pos + 1))
  else exit 1
in
let rec parse_atom input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  parse_number (src, pos)
in
let rec parse_expr input =
  let (src, pos) = input in
  let left = parse_atom (src, pos) in
  let (lhs, next0) = left in
  let next = skip_space (src, next0) in
  if src.[next] == 43 then
    let right = parse_expr (src, next + 1) in
    let (rhs, done_pos) = right in
    (lhs + rhs, done_pos)
  else
    left
in
let rec parse_program src =
  let pos = skip_space (src, 0) in
  if src.[pos] == 119 then
    let p = skip_space (src, pos + 10) in
    if src.[p] == 40 then parse_expr (src, p + 1)
    else parse_expr (src, p)
  else
    parse_expr (src, pos)
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
let parsed = parse_program source in
let (value, done_pos) = parsed in
emit_program value
