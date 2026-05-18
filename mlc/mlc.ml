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
let rec emit_sub emit =
  let _ = emit_byte_if (emit, 6) in
  1
in
let rec emit_mul emit =
  let _ = emit_byte_if (emit, 7) in
  1
in
let rec emit_div emit =
  let _ = emit_byte_if (emit, 8) in
  1
in
let rec emit_eq emit =
  let _ = emit_byte_if (emit, 9) in
  1
in
let rec emit_lt emit =
  let _ = emit_byte_if (emit, 10) in
  1
in
let rec emit_ne emit =
  let _ = emit_byte_if (emit, 19) in
  1
in
let rec emit_le emit =
  let _ = emit_byte_if (emit, 20) in
  1
in
let rec emit_gt emit =
  let _ = emit_byte_if (emit, 21) in
  1
in
let rec emit_ge emit =
  let _ = emit_byte_if (emit, 22) in
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
let rec emit_makeblock state =
  let (emit, pair) = state in
  let (tag, size) = pair in
  let _ = emit_byte_if (emit, 15) in
  let _ = emit_u32_if (emit, tag) in
  let _ = emit_u32_if (emit, size) in
  9
in
let rec emit_getfield state =
  let (emit, index) = state in
  let _ = emit_byte_if (emit, 16) in
  let _ = emit_u32_if (emit, index) in
  5
in
let rec emit_gettag emit =
  let _ = emit_byte_if (emit, 18) in
  1
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
let empty_ctors = (0 - 1, (0, (0, 0))) in
let rec pack_ctor state =
  let (tag, has_arg) = state in
  tag * 2 + has_arg
in
let rec ctor_tag packed =
  packed / 2
in
let rec ctor_has_arg packed =
  packed - (packed / 2) * 2
in
let rec extend_ctor state =
  let (name, pair) = state in
  let (packed, old) = pair in
  (name, (packed, old))
in
let rec find_ctor state =
  let (ctors, name) = state in
  let (head, rest) = ctors in
  let (packed, tail) = rest in
  if head == name then packed else
  if head < 0 then 0 - 1 else find_ctor (tail, name)
in
let rec lookup_ctor state =
  let packed = find_ctor state in
  if packed < 0 then exit 1 else packed
in
let rec is_type_at input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 116 then
    if src.[pos + 1] == 121 then
      if src.[pos + 2] == 112 then
        if src.[pos + 3] == 101 then
          if is_ident (src.[pos + 4]) then 0 else 1
        else 0
      else 0
    else 0
  else 0
in
let rec is_of_at input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 111 then
    if src.[pos + 1] == 102 then
      if is_ident (src.[pos + 2]) then 0 else 1
    else 0
  else 0
in
let rec is_match_at input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 109 then
    if src.[pos + 1] == 97 then
      if src.[pos + 2] == 116 then
        if src.[pos + 3] == 99 then
          if src.[pos + 4] == 104 then
            if is_ident (src.[pos + 5]) then 0 else 1
          else 0
        else 0
      else 0
    else 0
  else 0
in
let rec is_write_byte_at input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 119 then
    if src.[pos + 1] == 114 then
      if src.[pos + 2] == 105 then
        if src.[pos + 3] == 116 then
          if src.[pos + 4] == 101 then
            if src.[pos + 5] == 95 then
              if src.[pos + 6] == 98 then
                if src.[pos + 7] == 121 then
                  if src.[pos + 8] == 116 then
                    if src.[pos + 9] == 101 then
                      if is_ident (src.[pos + 10]) then 0 else 1
                    else 0
                  else 0
                else 0
              else 0
            else 0
          else 0
        else 0
      else 0
    else 0
  else 0
in
let rec expect_with input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 119 then
    if src.[pos + 1] == 105 then
      if src.[pos + 2] == 116 then
        if src.[pos + 3] == 104 then pos + 4 else exit 1
      else exit 1
    else exit 1
  else exit 1
in
let rec expect_arrow input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 45 then
    if src.[pos + 1] == 62 then pos + 2 else exit 1
  else exit 1
in
let rec parse_type_ctors state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (tag, ctors) = pair2 in
  let pos1 = skip_space (src, pos0) in
  let pos = if src.[pos1] == 124 then skip_space (src, pos1 + 1) else pos1 in
  let parsed = parse_ident (src, pos) in
  let (name, after_name) = parsed in
  let after_ctor = skip_space (src, after_name) in
  if is_of_at (src, after_ctor) then
    let skipped = parse_ident (src, after_ctor + 2) in
    let (dummy, after_type) = skipped in
    let _ = dummy in
    let next_ctors = extend_ctor (name, (pack_ctor (tag, 1), ctors)) in
    let next = skip_space (src, after_type) in
    if src.[next] == 124 then parse_type_ctors (src, (next, (tag + 1, next_ctors))) else (next, next_ctors)
  else
    let next_ctors = extend_ctor (name, (pack_ctor (tag, 0), ctors)) in
    if src.[after_ctor] == 124 then parse_type_ctors (src, (after_ctor, (tag + 1, next_ctors))) else (after_ctor, next_ctors)
in
let rec parse_type_decls input =
  let (src, pair) = input in
  let (pos0, ctors) = pair in
  let pos = skip_space (src, pos0) in
  if is_type_at (src, pos) then
    let type_name = parse_ident (src, pos + 4) in
    let (dummy, name_end) = type_name in
    let _ = dummy in
    let eq_pos = skip_space (src, name_end) in
    if src.[eq_pos] == 61 then
      let parsed = parse_type_ctors (src, (eq_pos + 1, (0, ctors))) in
      let (next_pos, next_ctors) = parsed in
      parse_type_decls (src, (next_pos, next_ctors))
    else
      exit 1
  else
    (pos, ctors)
in
let rec shift_env env =
  let (name, rest) = env in
  let (depth, tail) = rest in
  if name < 0 then env else (name, (depth + 1, shift_env (tail)))
in
let rec find_env input =
  let (env, want) = input in
  let (name, rest) = env in
  let (depth, tail) = rest in
  if name == want then depth else
  if name < 0 then 0 - 1 else find_env (tail, want)
in
let rec lookup_env input =
  let (env, want) = input in
  let found = find_env (env, want) in
  if found < 0 then exit 1 else found
in
let rec extend_env input =
  let (name, env) = input in
  (name, (0, shift_env (env)))
in
let rec compile_simple_atom input =
  let (src, pair) = input in
  let (pos0, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, emit) = pair3 in
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
    let depth = find_env (env, name) in
    if depth >= 0 then
      let len = emit_acc (emit, depth) in
      (len, done_pos)
    else
      let ctor = lookup_ctor (ctors, name) in
      let tag = ctor_tag ctor in
      if ctor_has_arg ctor == 0 then
        let block_len = emit_makeblock (emit, (tag, 0)) in
        (block_len, done_pos)
      else
        exit 1
in
let rec compile_simple_expr input =
  let (src, pair) = input in
  let (pos0, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, emit) = pair3 in
  let pos = skip_space (src, pos0) in
  let left =
    if src.[pos] == 40 then
      let inner = compile_simple_expr (src, (pos + 1, (env, (ctors, emit)))) in
      let (inner_len, inner_end0) = inner in
      let inner_end = skip_space (src, inner_end0) in
      if src.[inner_end] == 41 then (inner_len, inner_end + 1) else exit 1
    else
      compile_simple_atom (src, (pos, (env, (ctors, emit))))
  in
  let (left_len, next0) = left in
  let next = skip_space (src, next0) in
  if src.[next] == 43 then
    let push_len = emit_push (emit) in
    let right = compile_simple_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
    let (right_len, done_pos) = right in
    let add_len = emit_add (emit) in
    (left_len + push_len + right_len + add_len, done_pos)
  else if src.[next] == 45 then
    let push_len = emit_push (emit) in
    let right = compile_simple_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
    let (right_len, done_pos) = right in
    let sub_len = emit_sub (emit) in
    (left_len + push_len + right_len + sub_len, done_pos)
  else if src.[next] == 42 then
    let push_len = emit_push (emit) in
    let right = compile_simple_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
    let (right_len, done_pos) = right in
    let mul_len = emit_mul (emit) in
    (left_len + push_len + right_len + mul_len, done_pos)
  else if src.[next] == 47 then
    let push_len = emit_push (emit) in
    let right = compile_simple_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
    let (right_len, done_pos) = right in
    let div_len = emit_div (emit) in
    (left_len + push_len + right_len + div_len, done_pos)
  else if src.[next] == 60 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_simple_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let le_len = emit_le (emit) in
      (left_len + push_len + right_len + le_len, done_pos)
    else
      let push_len = emit_push (emit) in
      let right = compile_simple_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let lt_len = emit_lt (emit) in
      (left_len + push_len + right_len + lt_len, done_pos)
  else if src.[next] == 62 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_simple_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let ge_len = emit_ge (emit) in
      (left_len + push_len + right_len + ge_len, done_pos)
    else
      let push_len = emit_push (emit) in
      let right = compile_simple_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let gt_len = emit_gt (emit) in
      (left_len + push_len + right_len + gt_len, done_pos)
  else if src.[next] == 33 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_simple_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let ne_len = emit_ne (emit) in
      (left_len + push_len + right_len + ne_len, done_pos)
    else
      exit 1
  else if src.[next] == 61 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_simple_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let eq_len = emit_eq (emit) in
      (left_len + push_len + right_len + eq_len, done_pos)
    else
      exit 1
  else
    left
in
let rec compile_if input =
  let (src, pair) = input in
  let (pos, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, emit) = pair3 in
  let cond0 = compile_simple_expr (src, (pos + 2, (env, (ctors, 0)))) in
  let (cond_len, cond_end) = cond0 in
  let then_pos = skip_space (src, cond_end) in
  if src.[then_pos] == 116 then
    let then0 = compile_simple_expr (src, (then_pos + 4, (env, (ctors, 0)))) in
    let (then_len, then_end) = then0 in
    let else_pos = skip_space (src, then_end) in
    if src.[else_pos] == 101 then
      let else0 = compile_simple_expr (src, (else_pos + 4, (env, (ctors, 0)))) in
      let (else_len, else_end) = else0 in
      let _ = if emit == 1 then compile_simple_expr (src, (pos + 2, (env, (ctors, 1)))) else (0, 0) in
      let _ = emit_branch_if_not (emit, then_len + 5) in
      let _ = if emit == 1 then compile_simple_expr (src, (then_pos + 4, (env, (ctors, 1)))) else (0, 0) in
      let _ = emit_branch (emit, else_len) in
      let _ = if emit == 1 then compile_simple_expr (src, (else_pos + 4, (env, (ctors, 1)))) else (0, 0) in
      (cond_len + 5 + then_len + 5 + else_len, else_end)
    else
      exit 1
  else
    exit 1
in
let rec compile_atom input =
  let (src, pair) = input in
  let (pos0, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, emit) = pair3 in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 105 then compile_if (src, (pos, (env, (ctors, emit))))
  else compile_simple_atom (src, (pos, (env, (ctors, emit))))
in
let rec compile_expr input =
  let (src, pair) = input in
  let (pos0, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, emit) = pair3 in
  let pos = skip_space (src, pos0) in
  if is_write_byte_at (src, pos) then
    let p = skip_space (src, pos + 10) in
    let expr = compile_expr (src, (p, (env, (ctors, emit)))) in
    let (expr_len, done_pos) = expr in
    let call_len = emit_call_write_byte (emit) in
    (expr_len + call_len, done_pos)
  else if is_match_at (src, pos) then
    let scrutinee0 = compile_expr (src, (pos + 5, (env, (ctors, 0)))) in
    let (scrutinee_len, scrutinee_end) = scrutinee0 in
    let cases_start = expect_with (src, scrutinee_end) in
    let case_env = shift_env env in
    let case1_pos1 = skip_space (src, cases_start) in
    let case1_pos = if src.[case1_pos1] == 124 then skip_space (src, case1_pos1 + 1) else case1_pos1 in
    let case1_pat = parse_ident (src, case1_pos) in
    let (case1_name, case1_pat_end0) = case1_pat in
    let case1_ctor = lookup_ctor (ctors, case1_name) in
    let case1_pat_end = skip_space (src, case1_pat_end0) in
    let case1_has_arg = ctor_has_arg case1_ctor in
    let case1_binder = if case1_has_arg == 1 then parse_ident (src, case1_pat_end) else (0 - 1, case1_pat_end) in
    let (case1_bind, case1_bind_end) = case1_binder in
    let case1_arrow = if case1_has_arg == 1 then case1_bind_end else case1_pat_end in
    let case1_body_start = expect_arrow (src, case1_arrow) in
    let case1_env = if case1_has_arg == 1 then extend_env (case1_bind, case_env) else case_env in
    let case1_body0 = compile_expr (src, (case1_body_start, (case1_env, (ctors, 0)))) in
    let (case1_body_len, case1_body_end) = case1_body0 in
    let case2_pos1 = skip_space (src, case1_body_end) in
    let case2_pos = if src.[case2_pos1] == 124 then skip_space (src, case2_pos1 + 1) else exit 1 in
    let case2_is_wild = if src.[case2_pos] == 95 then 1 else 0 in
    let case2_pat =
      if case2_is_wild == 1 then (0 - 1, case2_pos + 1) else parse_ident (src, case2_pos)
    in
    let (case2_name, case2_pat_end0) = case2_pat in
    let case2_ctor = if case2_is_wild == 1 then 0 else lookup_ctor (ctors, case2_name) in
    let case2_pat_end = skip_space (src, case2_pat_end0) in
    let case2_has_arg = if case2_is_wild == 1 then 0 else ctor_has_arg case2_ctor in
    let case2_binder = if case2_has_arg == 1 then parse_ident (src, case2_pat_end) else (0 - 1, case2_pat_end) in
    let (case2_bind, case2_bind_end) = case2_binder in
    let case2_arrow = if case2_has_arg == 1 then case2_bind_end else case2_pat_end in
    let case2_body_start = expect_arrow (src, case2_arrow) in
    let case2_env = if case2_has_arg == 1 then extend_env (case2_bind, case_env) else case_env in
    let case2_body0 = compile_expr (src, (case2_body_start, (case2_env, (ctors, 0)))) in
    let (case2_body_len, case2_body_end) = case2_body0 in
    let case3_pos1 = skip_space (src, case2_body_end) in
    let has_case3 = if src.[case3_pos1] == 124 then 1 else 0 in
    let case3_pos = if has_case3 == 1 then skip_space (src, case3_pos1 + 1) else case3_pos1 in
    let case3_is_wild = if has_case3 == 1 then if src.[case3_pos] == 95 then 1 else 0 else 1 in
    let case3_pat =
      if case3_is_wild == 1 then (0 - 1, case3_pos + 1) else parse_ident (src, case3_pos)
    in
    let (case3_name, case3_pat_end0) = case3_pat in
    let case3_ctor = if case3_is_wild == 1 then 0 else lookup_ctor (ctors, case3_name) in
    let case3_pat_end = skip_space (src, case3_pat_end0) in
    let case3_has_arg = if case3_is_wild == 1 then 0 else ctor_has_arg case3_ctor in
    let case3_binder = if case3_has_arg == 1 then parse_ident (src, case3_pat_end) else (0 - 1, case3_pat_end) in
    let (case3_bind, case3_bind_end) = case3_binder in
    let case3_arrow = if case3_has_arg == 1 then case3_bind_end else case3_pat_end in
    let case3_body_start = if has_case3 == 1 then expect_arrow (src, case3_arrow) else case2_body_end in
    let case3_env = if case3_has_arg == 1 then extend_env (case3_bind, case_env) else case_env in
    let case3_body0 =
      if has_case3 == 1 then compile_expr (src, (case3_body_start, (case3_env, (ctors, 0)))) else (0, case2_body_end)
    in
    let (case3_body_len, case3_body_end) = case3_body0 in
    let case1_payload_len = if case1_has_arg == 1 then 11 else 0 in
    let case1_payload_pop_len = if case1_has_arg == 1 then 5 else 0 in
    let case1_total = case1_payload_len + case1_body_len + case1_payload_pop_len + 5 in
    let case2_payload_len = if case2_has_arg == 1 then 11 else 0 in
    let case2_payload_pop_len = if case2_has_arg == 1 then 5 else 0 in
    let case2_total = case2_payload_len + case2_body_len + case2_payload_pop_len + 5 in
    let case3_payload_len = if case3_has_arg == 1 then 11 else 0 in
    let case3_payload_pop_len = if case3_has_arg == 1 then 5 else 0 in
    let case3_total = if has_case3 == 1 then case3_payload_len + case3_body_len + case3_payload_pop_len + 5 else 0 in
    let case2_segment = if has_case3 == 1 then 18 + case2_total + 5 + case3_total else case2_total in
    let cases_len = 18 + case1_total + 5 + case2_segment in
    let _ =
      if emit == 1 then
        let _ = compile_expr (src, (pos + 5, (env, (ctors, 1)))) in
        let _ = emit_push 1 in
        let _ = emit_acc (1, 0) in
        let _ = emit_gettag 1 in
        let _ = emit_push 1 in
        let _ = emit_const (1, ctor_tag case1_ctor) in
        let _ = emit_eq 1 in
        let _ = emit_branch_if_not (1, case1_total + 5) in
        let _ =
          if case1_has_arg == 1 then
            let _ = emit_acc (1, 0) in
            let _ = emit_getfield (1, 0) in
            emit_push 1
          else 0
        in
        let _ = compile_expr (src, (case1_body_start, (case1_env, (ctors, 1)))) in
        let _ = if case1_has_arg == 1 then emit_pop1 1 else 0 in
        let _ = emit_pop1 1 in
        let _ = emit_branch (1, case2_segment) in
        let _ =
          if has_case3 == 1 then
            let _ = emit_acc (1, 0) in
            let _ = emit_gettag 1 in
            let _ = emit_push 1 in
            let _ = emit_const (1, ctor_tag case2_ctor) in
            let _ = emit_eq 1 in
            emit_branch_if_not (1, case2_total + 5)
          else 0
        in
        let _ =
          if case2_has_arg == 1 then
            let _ = emit_acc (1, 0) in
            let _ = emit_getfield (1, 0) in
            emit_push 1
          else 0
        in
        let _ = compile_expr (src, (case2_body_start, (case2_env, (ctors, 1)))) in
        let _ = if case2_has_arg == 1 then emit_pop1 1 else 0 in
        let _ = emit_pop1 1 in
        let _ = if has_case3 == 1 then emit_branch (1, case3_total) else 0 in
        let _ =
          if case3_has_arg == 1 then
            let _ = emit_acc (1, 0) in
            let _ = emit_getfield (1, 0) in
            emit_push 1
          else 0
        in
        let _ = if has_case3 == 1 then compile_expr (src, (case3_body_start, (case3_env, (ctors, 1)))) else (0, 0) in
        let _ = if case3_has_arg == 1 then emit_pop1 1 else 0 in
        let _ = if has_case3 == 1 then emit_pop1 1 else 0 in
        0
      else
        0
    in
    (scrutinee_len + 1 + cases_len, case3_body_end)
  else if is_ident (src.[pos]) then
    let parsed = parse_ident (src, pos) in
    let (name, name_end) = parsed in
    let depth = find_env (env, name) in
    let ctor = if depth < 0 then find_ctor (ctors, name) else 0 - 1 in
    if ctor >= 0 then
      let tag = ctor_tag ctor in
      if ctor_has_arg ctor == 1 then
        let payload = compile_expr (src, (name_end, (env, (ctors, emit)))) in
        let (payload_len, payload_end) = payload in
        let block_len = emit_makeblock (emit, (tag, 1)) in
        (payload_len + block_len, payload_end)
      else
        let block_len = emit_makeblock (emit, (tag, 0)) in
        (block_len, name_end)
    else
      let left =
        if src.[pos] == 40 then
          let inner = compile_expr (src, (pos + 1, (env, (ctors, emit)))) in
          let (inner_len, inner_end0) = inner in
          let inner_end = skip_space (src, inner_end0) in
          if src.[inner_end] == 41 then (inner_len, inner_end + 1) else exit 1
        else
          compile_atom (src, (pos, (env, (ctors, emit))))
      in
      let (left_len, next0) = left in
      let next = skip_space (src, next0) in
      if src.[next] == 43 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
        let (right_len, done_pos) = right in
        let add_len = emit_add (emit) in
        (left_len + push_len + right_len + add_len, done_pos)
      else if src.[next] == 45 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
        let (right_len, done_pos) = right in
        let sub_len = emit_sub (emit) in
        (left_len + push_len + right_len + sub_len, done_pos)
      else if src.[next] == 42 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
        let (right_len, done_pos) = right in
        let mul_len = emit_mul (emit) in
        (left_len + push_len + right_len + mul_len, done_pos)
      else if src.[next] == 47 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
        let (right_len, done_pos) = right in
        let div_len = emit_div (emit) in
        (left_len + push_len + right_len + div_len, done_pos)
      else if src.[next] == 60 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
          let (right_len, done_pos) = right in
          let le_len = emit_le (emit) in
          (left_len + push_len + right_len + le_len, done_pos)
        else
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
          let (right_len, done_pos) = right in
          let lt_len = emit_lt (emit) in
          (left_len + push_len + right_len + lt_len, done_pos)
      else if src.[next] == 62 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
          let (right_len, done_pos) = right in
          let ge_len = emit_ge (emit) in
          (left_len + push_len + right_len + ge_len, done_pos)
        else
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
          let (right_len, done_pos) = right in
          let gt_len = emit_gt (emit) in
          (left_len + push_len + right_len + gt_len, done_pos)
      else if src.[next] == 33 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
          let (right_len, done_pos) = right in
          let ne_len = emit_ne (emit) in
          (left_len + push_len + right_len + ne_len, done_pos)
        else
          exit 1
      else if src.[next] == 61 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
          let (right_len, done_pos) = right in
          let eq_len = emit_eq (emit) in
          (left_len + push_len + right_len + eq_len, done_pos)
        else
          exit 1
      else
        left
  else
  let left =
    if src.[pos] == 40 then
      let inner = compile_expr (src, (pos + 1, (env, (ctors, emit)))) in
      let (inner_len, inner_end0) = inner in
      let inner_end = skip_space (src, inner_end0) in
      if src.[inner_end] == 41 then (inner_len, inner_end + 1) else exit 1
    else
      compile_atom (src, (pos, (env, (ctors, emit))))
  in
  let (left_len, next0) = left in
  let next = skip_space (src, next0) in
  if src.[next] == 43 then
    let push_len = emit_push (emit) in
    let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
    let (right_len, done_pos) = right in
    let add_len = emit_add (emit) in
    (left_len + push_len + right_len + add_len, done_pos)
  else if src.[next] == 45 then
    let push_len = emit_push (emit) in
    let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
    let (right_len, done_pos) = right in
    let sub_len = emit_sub (emit) in
    (left_len + push_len + right_len + sub_len, done_pos)
  else if src.[next] == 42 then
    let push_len = emit_push (emit) in
    let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
    let (right_len, done_pos) = right in
    let mul_len = emit_mul (emit) in
    (left_len + push_len + right_len + mul_len, done_pos)
  else if src.[next] == 47 then
    let push_len = emit_push (emit) in
    let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
    let (right_len, done_pos) = right in
    let div_len = emit_div (emit) in
    (left_len + push_len + right_len + div_len, done_pos)
  else if src.[next] == 60 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let le_len = emit_le (emit) in
      (left_len + push_len + right_len + le_len, done_pos)
    else
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let lt_len = emit_lt (emit) in
      (left_len + push_len + right_len + lt_len, done_pos)
  else if src.[next] == 62 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let ge_len = emit_ge (emit) in
      (left_len + push_len + right_len + ge_len, done_pos)
    else
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let gt_len = emit_gt (emit) in
      (left_len + push_len + right_len + gt_len, done_pos)
  else if src.[next] == 33 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let ne_len = emit_ne (emit) in
      (left_len + push_len + right_len + ne_len, done_pos)
    else
      exit 1
  else if src.[next] == 61 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let eq_len = emit_eq (emit) in
      (left_len + push_len + right_len + eq_len, done_pos)
    else
      exit 1
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
  let (pos, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, emit) = pair3 in
  let p = skip_space (src, pos + 10) in
  let expr = compile_expr (src, (p, (env, (ctors, emit)))) in
  let (expr_len, done_pos) = expr in
  let call_len = emit_call_write_byte (emit) in
  (expr_len + call_len, done_pos)
in
let rec compile_byte_code input =
  let (src, pair) = input in
  let (pos0, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, emit) = pair3 in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 108 then
    let binding = parse_ident (src, pos + 3) in
    let (name, name_end) = binding in
    let eq_pos = skip_space (src, name_end) in
    if src.[eq_pos] == 61 then
      let rhs = compile_expr (src, (eq_pos + 1, (env, (ctors, emit)))) in
      let (rhs_len, rhs_end) = rhs in
      let in_pos = skip_space (src, rhs_end) in
      if src.[in_pos] == 105 then
        let body_pos = skip_space (src, in_pos + 2) in
        let push_len = emit_push (emit) in
        let next_env = extend_env (name, env) in
        let body = compile_byte_code (src, (body_pos, (next_env, (ctors, emit)))) in
        let (body_len, body_end) = body in
        let pop_len = emit_pop1 (emit) in
        (rhs_len + push_len + body_len + pop_len, body_end)
      else
        exit 1
    else
      exit 1
  else
    compile_write_byte (src, (pos, (env, (ctors, emit))))
in
let rec emit_byte_source input =
  let (src, start_pos) = input in
  let empty_env = (0 - 1, (0, 0)) in
  let parsed_types = parse_type_decls (src, (start_pos, empty_ctors)) in
  let (body_pos, ctors) = parsed_types in
  let measured = compile_byte_code (src, (body_pos, (empty_env, (ctors, 0)))) in
  let (code_len, done_pos) = measured in
  let _ = emit_header (code_len + 1) in
  let _ = compile_byte_code (src, (body_pos, (empty_env, (ctors, 1)))) in
  write_byte 0
in
let rec compile_program src =
  let pos = skip_space (src, 0) in
  if src.[pos + 6] == 115 then
    let p0 = skip_space (src, pos + 12) in
    if src.[p0] == 34 then emit_string_program (src, p0 + 1)
    else exit 1
  else
    emit_byte_source (src, pos)
in
let source = Bytes.create 1024 in
let _ = read_all (source, 0) in
compile_program source
