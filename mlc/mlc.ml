let rec byte n =
  n - (n / 256) * 256
in
let rec emit_u32 n =
  let _ = write_byte (byte n) in
  let _ = write_byte (byte (n / 256)) in
  let _ = write_byte (byte (n / 65536)) in
  write_byte (byte (n / 16777216))
in
let rec emit_header code_len =
  let _ = write_byte 77 in
  let _ = write_byte 90 in
  let _ = write_byte 66 in
  let _ = write_byte 67 in
  let _ = emit_u32 1 in
  let _ = emit_u32 code_len in
  let _ = emit_u32 3 in
  emit_u32 0
in
let rec emit_write_const value =
  let _ = write_byte 1 in
  let _ = emit_u32 value in
  let _ = write_byte 14 in
  let _ = emit_u32 1 in
  emit_u32 1
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
let rec parse_char input =
  let (src, pos) = input in
  let ch = src.[pos + 1] in
  (ch, pos + 3)
in
let rec parse_atom input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 39 then parse_char (src, pos)
  else parse_number (src, pos)
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
let rec parse_string_len state =
  let (src, pair) = state in
  let (pos, count) = pair in
  if src.[pos] == 34 then count
  else parse_string_len (src, (pos + 1, count + 1))
in
let rec emit_string_loop input =
  let (src, pos) = input in
  if src.[pos] == 34 then write_byte 0
  else
    let _ = emit_write_const (src.[pos]) in
    emit_string_loop (src, pos + 1)
in
let rec emit_byte_program value =
  let _ = emit_header 15 in
  let _ = emit_write_const value in
  write_byte 0
in
let rec emit_string_program input =
  let (src, pos) = input in
  let len = parse_string_len (src, (pos, 0)) in
  let _ = emit_header (len * 14 + 1) in
  emit_string_loop (src, pos)
in
let rec compile_program src =
  let pos = skip_space (src, 0) in
  if src.[pos + 6] == 115 then
    let p0 = skip_space (src, pos + 12) in
    if src.[p0] == 34 then emit_string_program (src, p0 + 1)
    else exit 1
  else
    let parsed = parse_program src in
    let (value, done_pos) = parsed in
    emit_byte_program value
in
let source = Bytes.create 1024 in
let _ = read_all (source, 0) in
compile_program source
