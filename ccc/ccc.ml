let rec is_space ch =
  if ch == 32 then 1 else
  if ch == 10 then 1 else
  if ch == 9 then 1 else
  if ch == 13 then 1 else 0
in
let rec skip_block_comment state =
  let (src, pos) = state in
  if (src.[pos] == 42) * (src.[pos + 1] == 47) then pos + 2 else skip_block_comment (src, pos + 1)
in
let rec skip_line_comment state =
  let (src, pos) = state in
  if src.[pos] == 10 then pos + 1 else
  if src.[pos] == 0 then pos else skip_line_comment (src, pos + 1)
in
let rec skip_space state =
  let (src, pos) = state in
  if is_space (src.[pos]) then skip_space (src, pos + 1) else
  if src.[pos] == 47 then
    if src.[pos + 1] == 42 then skip_space (src, skip_block_comment (src, pos + 2)) else
    if src.[pos + 1] == 47 then skip_space (src, skip_line_comment (src, pos + 2)) else pos
  else
    pos
in
let rec is_digit ch =
  if ch < 48 then 0 else if ch < 58 then 1 else 0
in
let rec is_alpha ch =
  if ch == 95 then 1 else
  if ch < 65 then 0 else
  if ch < 91 then 1 else
  if ch < 97 then 0 else
  if ch < 123 then 1 else 0
in
let rec is_ident ch =
  if is_alpha ch then 1 else is_digit ch
in
let rec ident_hash n =
  n - ((n / 1000000007) * 1000000007)
in
let rec parse_ident_loop state =
  let (src, pair) = state in
  let (pos, acc) = pair in
  let ch = src.[pos] in
  if is_ident ch then parse_ident_loop (src, (pos + 1, ident_hash ((acc * 131) + ch))) else (acc, pos)
in
let rec parse_ident state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let ch = src.[pos] in
  if is_alpha ch then parse_ident_loop (src, (pos + 1, ch)) else exit 1
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
let rec empty_funcs unit =
  let _ = unit in
  (0 - 1, (0, (0, 0)))
in
let rec extend_func state =
  let (name, pair) = state in
  let (kind, pair2) = pair in
  let (value, old) = pair2 in
  (name, (kind, (value, old)))
in
let rec apply_func state =
  let (funcs, pair) = state in
  let (name, arg) = pair in
  let (head, rest) = funcs in
  let (kind, rest2) = rest in
  let (value, tail) = rest2 in
  if head == name then if kind == 0 then value else arg else
  if head < 0 then exit 1 else apply_func (tail, (name, arg))
in
let rec parse_expr_value state =
  let (src, pair) = state in
  let (pos0, funcs) = pair in
  let pos = skip_space (src, pos0) in
  if is_digit (src.[pos]) then parse_number (src, pos) else
    let ident = parse_ident (src, pos) in
    let (name, name_end) = ident in
    let p0 = expect_ch (src, (name_end, 40)) in
    let p1 = skip_space (src, p0) in
    if src.[p1] == 41 then (apply_func (funcs, (name, 0)), p1 + 1) else
      let arg = parse_expr_value (src, (p1, funcs)) in
      let (arg_value, arg_end) = arg in
      let p2 = expect_ch (src, (arg_end, 41)) in
      (apply_func (funcs, (name, arg_value)), p2)
in
let rec parse_func_return state =
  let (src, pair) = state in
  let (pos0, param) = pair in
  let p0 = expect_return (src, pos0) in
  let p1 = skip_space (src, p0) in
  if is_digit (src.[p1]) then
    let parsed = parse_number (src, p1) in
    let (value, value_end) = parsed in
    let p2 = expect_ch (src, (value_end, 59)) in
    ((0, value), p2)
  else
    let ident = parse_ident (src, p1) in
    let (name, name_end) = ident in
    let p2 = expect_ch (src, (name_end, 59)) in
    if name == param then ((1, 0), p2) else exit 1
in
let rec parse_params state =
  let (src, pos0) = state in
  let p0 = expect_ch (src, (pos0, 40)) in
  let p1 = skip_space (src, p0) in
  if src.[p1] == 41 then (0 - 1, p1 + 1) else
    let p2 = expect_int (src, p1) in
    let param = parse_ident (src, p2) in
    let (param_name, param_end) = param in
    let p3 = expect_ch (src, (param_end, 41)) in
    (param_name, p3)
in
let rec parse_program_loop state =
  let (src, pair) = state in
  let (pos0, funcs) = pair in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 0 then exit 1 else
    let p0 = expect_int (src, pos) in
    let name_parsed = parse_ident (src, p0) in
    let (name, name_end) = name_parsed in
    let params = parse_params (src, name_end) in
    let (param, p1) = params in
    let p2 = expect_ch (src, (p1, 123)) in
    if name == 246720401 then
      let p3 = expect_return (src, p2) in
      let value = parse_expr_value (src, (p3, funcs)) in
      let (code, p4) = value in
      let p5 = expect_ch (src, (p4, 59)) in
      let _ = expect_ch (src, (p5, 125)) in
      code
    else
      let ret = parse_func_return (src, (p2, param)) in
      let (func_value, p3) = ret in
      let (kind, value) = func_value in
      let p4 = expect_ch (src, (p3, 125)) in
      parse_program_loop (src, (p4, extend_func (name, (kind, (value, funcs)))))
in
let rec parse_program src =
  parse_program_loop (src, (0, empty_funcs 0))
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
