let rec is_space ch =
  if ch == 32 then 1 else
  if ch == 10 then 1 else
  if ch == 9 then 1 else
  if ch == 13 then 1 else 0
in
let rec skip_space state =
  let (src, pos) = state in
  if is_space (src.[pos]) then skip_space (src, pos + 1) else pos
in
let rec is_digit ch =
  if ch < 48 then 0 else if ch < 58 then 1 else 0
in
let rec expect_int state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if (src.[pos] == 105) * (src.[pos + 1] == 110) * (src.[pos + 2] == 116) then pos + 3 else exit 1
in
let rec expect_main state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if (src.[pos] == 109) * (src.[pos + 1] == 97) * (src.[pos + 2] == 105) * (src.[pos + 3] == 110) then pos + 4 else exit 1
in
let rec expect_return state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if (src.[pos] == 114) * (src.[pos + 1] == 101) * (src.[pos + 2] == 116) * (src.[pos + 3] == 117) then
    if (src.[pos + 4] == 114) * (src.[pos + 5] == 110) then pos + 6 else exit 1
  else
    exit 1
in
let rec expect_ch state =
  let (src, pair) = state in
  let (pos0, ch) = pair in
  let pos = skip_space (src, pos0) in
  if src.[pos] == ch then pos + 1 else exit 1
in
let rec parse_number_loop state =
  let (src, pair) = state in
  let (pos, acc) = pair in
  let ch = src.[pos] in
  if is_digit ch then parse_number_loop (src, (pos + 1, (((acc * 10) + ch) - 48))) else (acc, pos)
in
let rec parse_number state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if is_digit (src.[pos]) then parse_number_loop (src, (pos, 0)) else exit 1
in
let rec parse_program src =
  let p0 = expect_int (src, 0) in
  let p1 = expect_main (src, p0) in
  let p2 = expect_ch (src, (p1, 40)) in
  let p3 = expect_ch (src, (p2, 41)) in
  let p4 = expect_ch (src, (p3, 123)) in
  let p5 = expect_return (src, p4) in
  let parsed = parse_number (src, p5) in
  let (code, p6) = parsed in
  let p7 = expect_ch (src, (p6, 59)) in
  let _ = expect_ch (src, (p7, 125)) in
  code
in
let rec read_all state =
  let (src, pos) = state in
  let ch = read_byte in
  if ch < 0 then pos else
    let _ = src.[pos] <- ch in
    read_all (src, pos + 1)
in
let rec emit_prefix unit =
  let _ = unit in
  let _ = write_byte 68 in
  let _ = write_byte 69 in
  let _ = write_byte 70 in
  let _ = write_byte 73 in
  let _ = write_byte 78 in
  let _ = write_byte 69 in
  let _ = write_byte 32 in
  let _ = write_byte 76 in
  let _ = write_byte 79 in
  let _ = write_byte 65 in
  let _ = write_byte 68 in
  let _ = write_byte 73 in
  let _ = write_byte 51 in
  let _ = write_byte 50 in
  let _ = write_byte 95 in
  let _ = write_byte 82 in
  let _ = write_byte 68 in
  let _ = write_byte 73 in
  let _ = write_byte 32 in
  let _ = write_byte 52 in
  let _ = write_byte 56 in
  let _ = write_byte 67 in
  let _ = write_byte 55 in
  let _ = write_byte 67 in
  let _ = write_byte 55 in
  let _ = write_byte 10 in
  let _ = write_byte 68 in
  let _ = write_byte 69 in
  let _ = write_byte 70 in
  let _ = write_byte 73 in
  let _ = write_byte 78 in
  let _ = write_byte 69 in
  let _ = write_byte 32 in
  let _ = write_byte 76 in
  let _ = write_byte 79 in
  let _ = write_byte 65 in
  let _ = write_byte 68 in
  let _ = write_byte 73 in
  let _ = write_byte 51 in
  let _ = write_byte 50 in
  let _ = write_byte 95 in
  let _ = write_byte 82 in
  let _ = write_byte 65 in
  let _ = write_byte 88 in
  let _ = write_byte 32 in
  let _ = write_byte 52 in
  let _ = write_byte 56 in
  let _ = write_byte 67 in
  let _ = write_byte 55 in
  let _ = write_byte 67 in
  let _ = write_byte 48 in
  let _ = write_byte 10 in
  let _ = write_byte 68 in
  let _ = write_byte 69 in
  let _ = write_byte 70 in
  let _ = write_byte 73 in
  let _ = write_byte 78 in
  let _ = write_byte 69 in
  let _ = write_byte 32 in
  let _ = write_byte 83 in
  let _ = write_byte 89 in
  let _ = write_byte 83 in
  let _ = write_byte 67 in
  let _ = write_byte 65 in
  let _ = write_byte 76 in
  let _ = write_byte 76 in
  let _ = write_byte 32 in
  let _ = write_byte 48 in
  let _ = write_byte 70 in
  let _ = write_byte 48 in
  let _ = write_byte 53 in
  let _ = write_byte 10 in
  let _ = write_byte 10 in
  let _ = write_byte 58 in
  let _ = write_byte 95 in
  let _ = write_byte 115 in
  let _ = write_byte 116 in
  let _ = write_byte 97 in
  let _ = write_byte 114 in
  let _ = write_byte 116 in
  let _ = write_byte 10 in
  let _ = write_byte 9 in
  let _ = write_byte 76 in
  let _ = write_byte 79 in
  let _ = write_byte 65 in
  let _ = write_byte 68 in
  let _ = write_byte 73 in
  let _ = write_byte 51 in
  let _ = write_byte 50 in
  let _ = write_byte 95 in
  let _ = write_byte 82 in
  let _ = write_byte 68 in
  let _ = write_byte 73 in
  let _ = write_byte 32 in
  write_byte 37
in
let rec emit_suffix unit =
  let _ = unit in
  let _ = write_byte 10 in
  let _ = write_byte 9 in
  let _ = write_byte 76 in
  let _ = write_byte 79 in
  let _ = write_byte 65 in
  let _ = write_byte 68 in
  let _ = write_byte 73 in
  let _ = write_byte 51 in
  let _ = write_byte 50 in
  let _ = write_byte 95 in
  let _ = write_byte 82 in
  let _ = write_byte 65 in
  let _ = write_byte 88 in
  let _ = write_byte 32 in
  let _ = write_byte 37 in
  let _ = write_byte 54 in
  let _ = write_byte 48 in
  let _ = write_byte 10 in
  let _ = write_byte 9 in
  let _ = write_byte 83 in
  let _ = write_byte 89 in
  let _ = write_byte 83 in
  let _ = write_byte 67 in
  let _ = write_byte 65 in
  let _ = write_byte 76 in
  let _ = write_byte 76 in
  write_byte 10
in
let rec emit_uint n =
  if n < 10 then write_byte (n + 48) else
    let _ = emit_uint (n / 10) in
    write_byte ((n - ((n / 10) * 10)) + 48)
in
let rec emit_m1 code =
  let _ = emit_prefix 0 in
  let _ = emit_uint code in
  emit_suffix 0
in
let source = Bytes.create 65536 in
let _ = read_all (source, 0) in
emit_m1 (parse_program source)
