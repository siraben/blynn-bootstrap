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
let rec emit_u32_if state =
  let (emit, n) = state in
  if emit == 1 then emit_u32 n else 0
in
let rec emit_byte_if state =
  let (emit, value) = state in
  if emit == 1 then write_byte value else 0
in
let rec emit_const state =
  let (emit, value) = state in
  let _ = emit_byte_if (emit, 1) in
  let _ = emit_u32_if (emit, value) in
  5
in
let rec emit_push emit =
  let _ = emit_byte_if (emit, 2) in
  1
in
let rec emit_pop1 emit =
  let _ = emit_byte_if (emit, 3) in
  let _ = emit_u32_if (emit, 1) in
  5
in
let rec emit_acc state =
  let (emit, depth) = state in
  let _ = emit_byte_if (emit, 4) in
  let _ = emit_u32_if (emit, depth) in
  5
in
let rec emit_add emit =
  let _ = emit_byte_if (emit, 5) in
  1
in
let rec emit_lt emit =
  let _ = emit_byte_if (emit, 10) in
  1
in
let rec emit_call_write_byte emit =
  let _ = emit_byte_if (emit, 14) in
  let _ = emit_u32_if (emit, 1) in
  let _ = emit_u32_if (emit, 1) in
  9
in
let rec emit_branch state =
  let (emit, offset) = state in
  let _ = emit_byte_if (emit, 11) in
  let _ = emit_u32_if (emit, offset) in
  5
in
let rec emit_branch_if_not state =
  let (emit, offset) = state in
  let _ = emit_byte_if (emit, 13) in
  let _ = emit_u32_if (emit, offset) in
  5
in
let rec is_digit ch =
  if ch < 48 then 0 else if ch > 57 then 0 else 1
in
let rec is_ident ch =
  if 48 <= ch then
    if ch <= 57 then 1 else
    if 65 <= ch then
      if ch <= 90 then 1 else
      if ch == 95 then 1 else
      if 97 <= ch then if ch <= 122 then 1 else 0 else 0
    else
      if ch == 95 then 1 else 0
  else
    0
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
let rec parse_ident_loop state =
  let (src, pair) = state in
  let (acc, pos) = pair in
  let ch = src.[pos] in
  if is_ident ch then parse_ident_loop (src, (acc * 131 + ch, pos + 1))
  else (acc, pos)
in
let rec parse_ident input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  let ch = src.[pos] in
  if is_ident ch then parse_ident_loop (src, (ch, pos + 1))
  else exit 1
in
let rec parse_char input =
  let (src, pos) = input in
  let ch = src.[pos + 1] in
  (ch, pos + 3)
in
let rec shift_env env =
  let (name, depth) = env in
  (name, depth + 1)
in
let rec compile_simple_atom input =
  let (src, pair) = input in
  let (pos0, pair2) = pair in
  let (env, emit) = pair2 in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 39 then
    let parsed = parse_char (src, pos) in
    let (value, done_pos) = parsed in
    let len = emit_const (emit, value) in
    (len, done_pos)
  else if is_digit (src.[pos]) then
    let parsed = parse_number (src, pos) in
    let (value, done_pos) = parsed in
    let len = emit_const (emit, value) in
    (len, done_pos)
  else
    let ident = parse_ident (src, pos) in
    let (name, done_pos) = ident in
    let (env_name, depth) = env in
    if name == env_name then
      let len = emit_acc (emit, depth) in
      (len, done_pos)
    else
      exit 1
in
let rec compile_simple_expr input =
  let (src, pair) = input in
  let (pos, pair2) = pair in
  let (env, emit) = pair2 in
  let left = compile_simple_atom (src, (pos, (env, emit))) in
  let (left_len, next0) = left in
  let next = skip_space (src, next0) in
  if src.[next] == 43 then
    let push_len = emit_push emit in
    let right = compile_simple_expr (src, (next + 1, (shift_env env, emit))) in
    let (right_len, done_pos) = right in
    let add_len = emit_add emit in
    (left_len + push_len + right_len + add_len, done_pos)
  else if src.[next] == 60 then
    let push_len = emit_push emit in
    let right = compile_simple_expr (src, (next + 1, (shift_env env, emit))) in
    let (right_len, done_pos) = right in
    let lt_len = emit_lt emit in
    (left_len + push_len + right_len + lt_len, done_pos)
  else
    left
in
let rec compile_if input =
  let (src, pair) = input in
  let (pos, pair2) = pair in
  let (env, emit) = pair2 in
  let cond0 = compile_simple_expr (src, (pos + 2, (env, 0))) in
  let (cond_len, cond_end) = cond0 in
  let then_pos = skip_space (src, cond_end) in
  if src.[then_pos] == 116 then
    let then0 = compile_simple_expr (src, (then_pos + 4, (env, 0))) in
    let (then_len, then_end) = then0 in
    let else_pos = skip_space (src, then_end) in
    if src.[else_pos] == 101 then
      let else0 = compile_simple_expr (src, (else_pos + 4, (env, 0))) in
      let (else_len, else_end) = else0 in
      let _ = if emit == 1 then compile_simple_expr (src, (pos + 2, (env, 1))) else (0, 0) in
      let _ = emit_branch_if_not (emit, then_len + 5) in
      let _ = if emit == 1 then compile_simple_expr (src, (then_pos + 4, (env, 1))) else (0, 0) in
      let _ = emit_branch (emit, else_len) in
      let _ = if emit == 1 then compile_simple_expr (src, (else_pos + 4, (env, 1))) else (0, 0) in
      (cond_len + 5 + then_len + 5 + else_len, else_end)
    else
      exit 1
  else
    exit 1
in
let rec compile_atom input =
  let (src, pair) = input in
  let (pos0, pair2) = pair in
  let (env, emit) = pair2 in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 105 then compile_if (src, (pos, (env, emit)))
  else compile_simple_atom (src, (pos, (env, emit)))
in
let rec compile_expr input =
  let (src, pair) = input in
  let (pos, pair2) = pair in
  let (env, emit) = pair2 in
  let left = compile_atom (src, (pos, (env, emit))) in
  let (left_len, next0) = left in
  let next = skip_space (src, next0) in
  if src.[next] == 43 then
    let push_len = emit_push emit in
    let right = compile_expr (src, (next + 1, (shift_env env, emit))) in
    let (right_len, done_pos) = right in
    let add_len = emit_add emit in
    (left_len + push_len + right_len + add_len, done_pos)
  else if src.[next] == 60 then
    let push_len = emit_push emit in
    let right = compile_expr (src, (next + 1, (shift_env env, emit))) in
    let (right_len, done_pos) = right in
    let lt_len = emit_lt emit in
    (left_len + push_len + right_len + lt_len, done_pos)
  else
    left
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
let rec emit_string_program input =
  let (src, pos) = input in
  let len = parse_string_len (src, (pos, 0)) in
  let _ = emit_header (len * 14 + 1) in
  emit_string_loop (src, pos)
in
let rec compile_write_byte input =
  let (src, pair) = input in
  let (pos, emit) = pair in
  let p = skip_space (src, pos + 10) in
  let expr_pos = if src.[p] == 40 then p + 1 else p in
  let expr = compile_expr (src, (expr_pos, ((0 - 1, 0), emit))) in
  let (expr_len, done_pos) = expr in
  let call_len = emit_call_write_byte emit in
  expr_len + call_len
in
let rec compile_let_write_byte input =
  let (src, emit) = input in
  let binding = parse_ident (src, 3) in
  let (name, name_end) = binding in
  let eq_pos = skip_space (src, name_end) in
  if src.[eq_pos] == 61 then
    let rhs = compile_expr (src, (eq_pos + 1, ((0 - 1, 0), emit))) in
    let (rhs_len, rhs_end) = rhs in
    let in_pos = skip_space (src, rhs_end) in
    if src.[in_pos] == 105 then
      let body_pos = skip_space (src, in_pos + 2) in
      let push_len = emit_push emit in
      let p = skip_space (src, body_pos + 10) in
      let expr_pos = if src.[p] == 40 then p + 1 else p in
      let body = compile_expr (src, (expr_pos, ((name, 0), emit))) in
      let (body_len, body_end) = body in
      let call_len = emit_call_write_byte emit in
      let pop_len = emit_pop1 emit in
      rhs_len + push_len + body_len + call_len + pop_len
    else
      exit 1
  else
    exit 1
in
let rec compile_byte_code input =
  let (src, emit) = input in
  let pos = skip_space (src, 0) in
  if src.[pos] == 108 then compile_let_write_byte (src, emit)
  else compile_write_byte (src, (pos, emit))
in
let rec emit_byte_source src =
  let code_len = compile_byte_code (src, 0) in
  let _ = emit_header (code_len + 1) in
  let _ = compile_byte_code (src, 1) in
  write_byte 0
in
let rec compile_program src =
  let pos = skip_space (src, 0) in
  if src.[pos + 6] == 115 then
    let p0 = skip_space (src, pos + 12) in
    if src.[p0] == 34 then emit_string_program (src, p0 + 1)
    else exit 1
  else
    emit_byte_source src
in
let source = Bytes.create 1024 in
let _ = read_all (source, 0) in
compile_program source
