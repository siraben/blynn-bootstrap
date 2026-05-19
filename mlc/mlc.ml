let rec byte n =
  n - ((n / 256) * 256)
in
let rec emit_u32 n =
  let _ = write_byte (byte n) in
  let _ = write_byte (byte (n / 256)) in
  let _ = write_byte (byte (n / 65536)) in
  write_byte (byte (n / 16777216))
in
let rec emit_header code_len =
  let _ = write_byte 'M' in
  let _ = write_byte 'Z' in
  let _ = write_byte 'B' in
  let _ = write_byte 'C' in
  let _ = emit_u32 1 in
  let _ = emit_u32 code_len in
  let _ = emit_u32 5 in
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
let rec emit_pop state =
  let (emit, count) = state in
  let _ = emit_byte_if (emit, 3) in
  let _ = emit_u32_if (emit, count) in
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
let rec emit_call_debug_byte emit =
  let _ = emit_byte_if (emit, 14) in
  let _ = emit_u32_if (emit, 1) in
  let _ = emit_u32_if (emit, 3) in
  9
in
let rec emit_call_debug_int emit =
  let _ = emit_byte_if (emit, 14) in
  let _ = emit_u32_if (emit, 1) in
  let _ = emit_u32_if (emit, 4) in
  9
in
let rec emit_call_exit emit =
  let _ = emit_byte_if (emit, 14) in
  let _ = emit_u32_if (emit, 1) in
  let _ = emit_u32_if (emit, 2) in
  9
in
let rec emit_call_read_byte emit =
  let _ = emit_byte_if (emit, 1) in
  let _ = emit_u32_if (emit, 0) in
  let _ = emit_byte_if (emit, 14) in
  let _ = emit_u32_if (emit, 1) in
  let _ = emit_u32_if (emit, 0) in
  14
in
let rec emit_call state =
  let (emit, target) = state in
  let _ = emit_byte_if (emit, 23) in
  let _ = emit_u32_if (emit, target) in
  5
in
let rec emit_return emit =
  let _ = emit_byte_if (emit, 24) in
  1
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
let rec emit_makeblock_dyn emit =
  let _ = emit_byte_if (emit, 28) in
  let _ = emit_u32_if (emit, 0) in
  5
in
let rec emit_getfield state =
  let (emit, index) = state in
  let _ = emit_byte_if (emit, 16) in
  let _ = emit_u32_if (emit, index) in
  5
in
let rec emit_setfield state =
  let (emit, index) = state in
  let _ = emit_byte_if (emit, 17) in
  let _ = emit_u32_if (emit, index) in
  5
in
let rec emit_getfield_dyn emit =
  let _ = emit_byte_if (emit, 25) in
  1
in
let rec emit_setfield_dyn emit =
  let _ = emit_byte_if (emit, 26) in
  1
in
let rec emit_blocksize emit =
  let _ = emit_byte_if (emit, 27) in
  1
in
let rec emit_gettag emit =
  let _ = emit_byte_if (emit, 18) in
  1
in
let rec is_digit ch =
  if ch < '0' then 0 else if ch > '9' then 0 else 1
in
let rec is_ident ch =
  if '0' <= ch then
    if ch <= '9' then 1 else
    if 'A' <= ch then
      if ch <= 'Z' then 1 else
      if ch == '_' then 1 else
      if 'a' <= ch then if ch <= 'z' then 1 else 0 else 0
    else
      if ch == '_' then 1 else 0
  else
    0
in
let rec is_lower_ident_start ch =
  if 'a' <= ch then if ch <= 'z' then 1 else 0 else 0
in
let rec is_space ch =
  if ch == ' ' then 1 else
  if ch == '\t' then 1 else
  if ch == '\n' then 1 else
  if ch == '\013' then 1 else 0
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
let rec parse_fail unit =
  exit 1
in
let rec parse_number_loop state =
  let (src, pair) = state in
  let (acc, pos) = pair in
  let ch = src.[pos] in
  if is_digit ch then parse_number_loop (src, (((acc * 10) + ch) - '0', pos + 1))
  else (acc, pos)
in
let rec parse_number input =
  let (src, pos) = input in
  let pos = skip_space (src, pos) in
  let ch = src.[pos] in
  if is_digit ch then parse_number_loop (src, (ch - '0', pos + 1))
  else parse_fail 0
in
let rec ident_hash n =
  n - ((n / 1000000007) * 1000000007)
in
let rec parse_ident_loop state =
  let (src, pair) = state in
  let (acc, pos) = pair in
  let ch = src.[pos] in
  if is_ident ch then parse_ident_loop (src, (ident_hash ((acc * 131) + ch), pos + 1))
  else (acc, pos)
in
let rec pack_ctor state =
  let (tag, has_arg) = state in
  (tag * 4) + has_arg
in
let rec ctor_tag packed =
  packed / 4
in
let rec ctor_has_arg packed =
  packed - ((packed / 4) * 4)
in
let rec ctor_is_field packed =
  ctor_has_arg packed == 2
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
  if packed < 0 then parse_fail 0 else packed
in
let rec lookup_field state =
  let packed = lookup_ctor state in
  if ctor_is_field packed then ctor_tag packed else parse_fail 0
in
let rec extend_func state =
  let (name, pair) = state in
  let (param, pair2) = pair in
  let (body_start, old) = pair2 in
  (name, (param, (body_start, old)))
in
let rec find_func state =
  let (funcs, want) = state in
  let (name, rest) = funcs in
  let (param, pair) = rest in
  let (body_start, tail) = pair in
  let _ = param in
  let _ = body_start in
  if name == want then 1 else
  if name < 0 then 0 else find_func (tail, want)
in
let rec func_param state =
  let (funcs, want) = state in
  let (name, rest) = funcs in
  let (param, pair) = rest in
  let (body_start, tail) = pair in
  let _ = body_start in
  if name == want then param else
  if name < 0 then parse_fail 0 else func_param (tail, want)
in
let rec func_body_start state =
  let (funcs, want) = state in
  let (name, rest) = funcs in
  let (param, pair) = rest in
  let (body_start, tail) = pair in
  let _ = param in
  if name == want then body_start else
  if name < 0 then parse_fail 0 else func_body_start (tail, want)
in
let rec string_at_loop state =
  let (src, pair) = state in
  let (pos, pair2) = pair in
  let (text, index) = pair2 in
  if index == String.length text then 1 else
  if src.[pos + index] == text.[index] then string_at_loop (src, (pos, (text, index + 1))) else 0
in
let rec string_at input =
  let (src, pair) = input in
  let (pos0, text) = pair in
  let pos = skip_space (src, pos0) in
  string_at_loop (src, (pos, (text, 0)))
in
let rec keyword_at input =
  let (src, pair) = input in
  let (pos0, text) = pair in
  let pos = skip_space (src, pos0) in
  let len = String.length text in
  if string_at_loop (src, (pos, (text, 0))) == 1 then 1 - (is_ident (src.[pos + len])) else 0
in
let rec p_ok state =
  let (value, pos) = state in
  (1, (value, pos))
in
let rec p_err pos =
  (0, (0, pos))
in
let rec p_is_ok reply =
  let (ok, rest) = reply in
  let _ = rest in
  ok
in
let rec p_value reply =
  let (ok, rest) = reply in
  let (value, pos) = rest in
  let _ = ok in
  let _ = pos in
  value
in
let rec p_pos reply =
  let (ok, rest) = reply in
  let (value, pos) = rest in
  let _ = ok in
  let _ = value in
  pos
in
let rec p_force reply =
  if p_is_ok reply == 1 then (p_value reply, p_pos reply) else parse_fail 0
in
let rec p_force_pos reply =
  let forced = p_force reply in
  let (value, pos) = forced in
  let _ = value in
  pos
in
let rec p_peek input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  (src.[pos], pos)
in
let rec p_try_char input =
  let (src, pair) = input in
  let (pos0, want) = pair in
  let peeked = p_peek (src, pos0) in
  let (got, pos) = peeked in
  if got == want then p_ok (got, pos + 1) else p_err pos
in
let rec p_need_char input =
  p_force_pos (p_try_char input)
in
let rec p_try_string input =
  let (src, pair) = input in
  let (pos0, text) = pair in
  let pos = skip_space (src, pos0) in
  if string_at_loop (src, (pos, (text, 0))) == 1 then p_ok (0, pos + String.length text) else p_err pos
in
let rec p_try_keyword input =
  let (src, pair) = input in
  let (pos0, text) = pair in
  let pos = skip_space (src, pos0) in
  if keyword_at (src, (pos, text)) == 1 then p_ok (0, pos + String.length text) else p_err pos
in
let rec p_need_string input =
  p_force_pos (p_try_string input)
in
let rec p_need_keyword input =
  p_force_pos (p_try_keyword input)
in
let rec need_string input =
  p_need_string input
in
let rec need_keyword input =
  p_need_keyword input
in
let rec p_try_ident input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  let ch = src.[pos] in
  if is_ident ch then
    let parsed = parse_ident_loop (src, (ch, pos + 1)) in
    let (name, done_pos) = parsed in
    p_ok (name, done_pos)
  else
    p_err pos
in
let rec p_need_ident input =
  p_force (p_try_ident input)
in
let rec parse_ident input =
  p_need_ident input
in
let rec parse_char_escape input =
  let (src, pos) = input in
  let esc = src.[pos] in
  if esc == 'n' then p_ok ('\n', pos + 1) else
  if esc == 't' then p_ok ('\t', pos + 1) else
  if is_digit esc then
    let d2 = src.[pos + 1] in
    let d3 = src.[pos + 2] in
    if (is_digit d2) * (is_digit d3) == 1 then
      let d1 = esc - '0' in
      let d2 = d2 - '0' in
      let d3 = d3 - '0' in
      p_ok ((d1 * 100) + (d2 * 10) + d3, pos + 3)
    else
      p_err pos
  else
    p_ok (esc, pos + 1)
in
let rec p_try_char_literal input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  let opened = p_try_char (src, (pos, '\'')) in
  if p_is_ok opened == 1 then
    let open_pos = p_pos opened in
    let ch = src.[open_pos] in
    let parsed =
      if ch == '\\' then parse_char_escape (src, open_pos + 1) else p_ok (ch, open_pos + 1)
    in
    if p_is_ok parsed == 1 then
      let closed = p_try_char (src, (p_pos parsed, '\'')) in
      if p_is_ok closed == 1 then p_ok (p_value parsed, p_pos closed) else closed
    else
      parsed
  else
    opened
in
let rec parse_char input =
  p_force (p_try_char_literal input)
in
let rec is_type_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "type")))
in
let rec is_of_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "of")))
in
let rec is_match_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "match")))
in
let rec is_write_byte_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "write_byte")))
in
let rec is_write_string_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "write_string")))
in
let rec is_debug_byte_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "debug_byte")))
in
let rec is_debug_string_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "debug_string")))
in
let rec is_debug_printf_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "debug_printf")))
in
let rec is_debug_int_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "debug_int")))
in
let rec is_if_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "if")))
in
let rec is_exit_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "exit")))
in
let rec is_read_byte_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "read_byte")))
in
let rec is_bytes_create_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "Bytes.create")))
in
let rec is_bytes_length_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "Bytes.length")))
in
let rec is_string_length_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "String.length")))
in
let rec is_cell_create_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "Cell.create")))
in
let rec is_cell_get_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "Cell.get")))
in
let rec is_cell_set_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "Cell.set")))
in
let rec is_then_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "then")))
in
let rec is_else_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "else")))
in
let rec is_let_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "let")))
in
let rec is_in_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "in")))
in
let rec is_rec_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "rec")))
in
let rec is_and_at input =
  let (src, pos0) = input in
  p_is_ok (p_try_keyword (src, (pos0, "and")))
in
let rec expect_with input =
  let (src, pos0) = input in
  need_keyword (src, (pos0, "with"))
in
let rec expect_arrow input =
  let (src, pos0) = input in
  need_string (src, (pos0, "->"))
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
let rec parse_record_fields state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (index, ctors) = pair2 in
  let pos = skip_space (src, pos0) in
  let empty = p_try_char (src, (pos, '}')) in
  if p_is_ok empty == 1 then (p_pos empty, ctors) else
    let parsed = parse_ident (src, pos) in
    let (field, field_end) = parsed in
    let after_colon = p_need_char (src, (field_end, ':')) in
    let typ = parse_ident (src, after_colon) in
    let (dummy, typ_end) = typ in
    let _ = dummy in
    let next_ctors = extend_ctor (field, (pack_ctor (index, 2), ctors)) in
    let next = skip_space (src, typ_end) in
    let semi = p_try_char (src, (next, ';')) in
    if p_is_ok semi == 1 then parse_record_fields (src, (p_pos semi, (index + 1, next_ctors))) else
    let close = p_try_char (src, (next, '}')) in
    if p_is_ok close == 1 then (p_pos close, next_ctors) else
      let forced = p_force close in
      let (dummy2, done_pos) = forced in
      let _ = dummy2 in
      (done_pos, next_ctors)
in
let rec parse_type_decls input =
  let (src, pair) = input in
  let (pos0, ctors) = pair in
  let pos = skip_space (src, pos0) in
  if is_type_at (src, pos) then
    let type_name = parse_ident (src, pos + 4) in
    let (dummy, name_end) = type_name in
    let _ = dummy in
    let after_eq = p_need_char (src, (name_end, '=')) in
    let after_eq = skip_space (src, after_eq) in
    let opened = p_try_char (src, (after_eq, '{')) in
    let parsed =
      if p_is_ok opened == 1 then parse_record_fields (src, (p_pos opened, (0, ctors)))
      else parse_type_ctors (src, (after_eq, (0, ctors)))
    in
    let (next_pos, next_ctors) = parsed in
    parse_type_decls (src, (next_pos, next_ctors))
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
  if found < 0 then parse_fail 0 else found
in
let rec extend_env input =
  let (name, env) = input in
  (name, (0, shift_env (env)))
in
let rec bind_if_named state =
  let (name, pair) = state in
  let (depth, env) = pair in
  if name == 95 then env else (name, (depth, env))
in
let rec shift5 env =
  shift_env (shift_env (shift_env (shift_env (shift_env env))))
in
let rec parse_case_payload input =
  let (src, pair) = input in
  let (pos0, has_arg) = pair in
  let pos = skip_space (src, pos0) in
  if has_arg == 1 then
    if src.[pos] == 40 then
      let first_pos = skip_space (src, pos + 1) in
      if src.[first_pos] == 40 then
        let bind1_parsed = parse_ident (src, first_pos + 1) in
        let (bind1, bind1_end0) = bind1_parsed in
        let bind1_end = skip_space (src, bind1_end0) in
        if src.[bind1_end] == 44 then
          let bind2_parsed = parse_ident (src, bind1_end + 1) in
          let (bind2, bind2_end0) = bind2_parsed in
          let bind2_end = skip_space (src, bind2_end0) in
          if src.[bind2_end] == 41 then
            let comma_pos = skip_space (src, bind2_end + 1) in
            if src.[comma_pos] == 44 then
              let bind3_parsed = parse_ident (src, comma_pos + 1) in
              let (bind3, bind3_end0) = bind3_parsed in
              let bind3_end = skip_space (src, bind3_end0) in
              if src.[bind3_end] == 41 then
                (1, (1, (bind1, (bind2, (bind3, bind3_end + 1)))))
              else
                parse_fail 0
            else
              parse_fail 0
          else
            parse_fail 0
        else
          parse_fail 0
      else
        let bind1_parsed = parse_ident (src, first_pos) in
        let (bind1, bind1_end0) = bind1_parsed in
        let bind1_end = skip_space (src, bind1_end0) in
        if src.[bind1_end] == 44 then
          let second_pos = skip_space (src, bind1_end + 1) in
          if src.[second_pos] == 40 then
            let bind2_parsed = parse_ident (src, second_pos + 1) in
            let (bind2, bind2_end0) = bind2_parsed in
            let bind2_end = skip_space (src, bind2_end0) in
            if src.[bind2_end] == 44 then
              let bind3_parsed = parse_ident (src, bind2_end + 1) in
              let (bind3, bind3_end0) = bind3_parsed in
              let bind3_end = skip_space (src, bind3_end0) in
              if src.[bind3_end] == 41 then
                let close_pos = skip_space (src, bind3_end + 1) in
                if src.[close_pos] == 41 then
                  (1, (2, (bind1, (bind2, (bind3, close_pos + 1)))))
                else
                  parse_fail 0
              else
                parse_fail 0
            else
              parse_fail 0
          else
            let bind2_parsed = parse_ident (src, second_pos) in
            let (bind2, bind2_end0) = bind2_parsed in
            let bind2_end = skip_space (src, bind2_end0) in
            if src.[bind2_end] == 41 then
              (1, (0, (bind1, (bind2, (0 - 1, bind2_end + 1)))))
            else
              parse_fail 0
        else
          parse_fail 0
    else
      let bind1_parsed = parse_ident (src, pos) in
      let (bind1, bind1_end) = bind1_parsed in
      (0, (0, (bind1, (0 - 1, (0 - 1, bind1_end)))))
  else
    (0, (0, (0 - 1, (0 - 1, (0 - 1, pos)))))
in
let rec case_payload_len input =
  let (has_arg, pair) = input in
  let (tuple, nested) = pair in
  if tuple == 1 then if nested == 0 then 33 else 55 else
  if has_arg == 1 then 11 else 0
in
let rec case_payload_env input =
  let (has_arg, pair) = input in
  let (tuple, pair2) = pair in
  let (nested, pair3) = pair2 in
  let (bind1, pair4) = pair3 in
  let (bind2, pair5) = pair4 in
  let (bind3, case_env) = pair5 in
  if tuple == 1 then
    if nested == 1 then
      let base = shift5 case_env in
      let env1 = bind_if_named (bind3, (0, base)) in
      let env2 = bind_if_named (bind2, (1, env1)) in
      bind_if_named (bind1, (2, env2))
    else if nested == 2 then
      let base = shift5 case_env in
      let env1 = bind_if_named (bind3, (0, base)) in
      let env2 = bind_if_named (bind2, (1, env1)) in
      bind_if_named (bind1, (3, env2))
    else
      let base = shift_env (shift_env (shift_env case_env)) in
      let env1 = bind_if_named (bind2, (0, base)) in
      bind_if_named (bind1, (1, env1))
  else if has_arg == 1 then
    extend_env (bind1, case_env)
  else
    case_env
in
let rec case_default_env input =
  let (is_wild, pair) = input in
  let (name, case_env) = pair in
  if is_wild == 1 then case_env else extend_env (name, case_env)
in
let rec emit_case_payload input =
  let (emit, pair) = input in
  let (has_arg, pair2) = pair in
  let (tuple, nested) = pair2 in
  if tuple == 1 then
    if nested == 1 then
      let _ = emit_acc (emit, 0) in
      let _ = emit_getfield (emit, 0) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 0) in
      let _ = emit_getfield (emit, 0) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 0) in
      let _ = emit_getfield (emit, 0) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 1) in
      let _ = emit_getfield (emit, 1) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 3) in
      let _ = emit_getfield (emit, 1) in
      emit_push emit
    else if nested == 2 then
      let _ = emit_acc (emit, 0) in
      let _ = emit_getfield (emit, 0) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 0) in
      let _ = emit_getfield (emit, 0) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 1) in
      let _ = emit_getfield (emit, 1) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 0) in
      let _ = emit_getfield (emit, 0) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 1) in
      let _ = emit_getfield (emit, 1) in
      emit_push emit
    else
      let _ = emit_acc (emit, 0) in
      let _ = emit_getfield (emit, 0) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 0) in
      let _ = emit_getfield (emit, 0) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 1) in
      let _ = emit_getfield (emit, 1) in
      emit_push emit
  else if has_arg == 1 then
    let _ = emit_acc (emit, 0) in
    let _ = emit_getfield (emit, 0) in
    emit_push emit
  else 0
in
let rec emit_case_payload_pop input =
  let (emit, pair) = input in
  let (has_arg, pair2) = pair in
  let (tuple, nested) = pair2 in
  if tuple == 1 then
    if nested == 1 then emit_pop (emit, 5) else emit_pop (emit, 3)
  else if has_arg == 1 then emit_pop1 emit else 0
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
        parse_fail 0
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
      if src.[inner_end] == 41 then (inner_len, inner_end + 1) else parse_fail 0
    else
      compile_simple_atom (src, (pos, (env, (ctors, emit))))
	  in
	  let (left_len0, next00) = left in
	  let next1 = skip_space (src, next00) in
	  let left =
	    if src.[next1] == 46 then
	      let open_ch = src.[next1 + 1] in
	      if open_ch == 91 then
	        let push_base = emit_push (emit) in
	        let index = compile_simple_expr (src, (next1 + 2, (shift_env env, (ctors, emit)))) in
	        let (index_len, index_end0) = index in
	        let index_end = skip_space (src, index_end0) in
	        if src.[index_end] == 93 then
	          let after_index = skip_space (src, index_end + 1) in
	          if src.[after_index] == 60 then
	            if src.[after_index + 1] == 45 then
	              let push_index = emit_push (emit) in
	              let value = compile_simple_expr (src, (after_index + 2, (shift_env (shift_env env), (ctors, emit)))) in
	              let (value_len, value_end) = value in
	              let set_len = emit_setfield_dyn (emit) in
	              (left_len0 + push_base + index_len + push_index + value_len + set_len, value_end)
	            else
	              parse_fail 0
	          else
	            let get_len = emit_getfield_dyn (emit) in
	            (left_len0 + push_base + index_len + get_len, index_end + 1)
	        else
	          parse_fail 0
	      else if open_ch == 40 then
	        let push_base = emit_push (emit) in
	        let index = compile_simple_expr (src, (next1 + 2, (shift_env env, (ctors, emit)))) in
	        let (index_len, index_end0) = index in
	        let index_end = skip_space (src, index_end0) in
	        if src.[index_end] == 41 then
	          let after_index = skip_space (src, index_end + 1) in
	          if src.[after_index] == 60 then
	            if src.[after_index + 1] == 45 then
	              let push_index = emit_push (emit) in
	              let value = compile_simple_expr (src, (after_index + 2, (shift_env (shift_env env), (ctors, emit)))) in
	              let (value_len, value_end) = value in
	              let set_len = emit_setfield_dyn (emit) in
	              (left_len0 + push_base + index_len + push_index + value_len + set_len, value_end)
	            else
	              parse_fail 0
	          else
	            let get_len = emit_getfield_dyn (emit) in
	            (left_len0 + push_base + index_len + get_len, index_end + 1)
	        else
	          parse_fail 0
	      else
	        let field = parse_ident (src, next1 + 1) in
	        let (field_name, field_end) = field in
	        let index = lookup_field (ctors, field_name) in
	        let field_len = emit_getfield (emit, index) in
	        (left_len0 + field_len, field_end)
	    else
	      left
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
      parse_fail 0
  else if src.[next] == 61 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_simple_expr (src, (next + 2, (shift_env (env), (ctors, emit)))) in
      let (right_len, done_pos) = right in
      let eq_len = emit_eq (emit) in
      (left_len + push_len + right_len + eq_len, done_pos)
    else
      parse_fail 0
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
  if is_then_at (src, then_pos) then
    let then0 = compile_simple_expr (src, (then_pos + 4, (env, (ctors, 0)))) in
    let (then_len, then_end) = then0 in
    let else_pos = skip_space (src, then_end) in
    if is_else_at (src, else_pos) then
      let else0 = compile_simple_expr (src, (else_pos + 4, (env, (ctors, 0)))) in
      let (else_len, else_end) = else0 in
      let _ = if emit == 1 then compile_simple_expr (src, (pos + 2, (env, (ctors, 1)))) else (0, 0) in
      let _ = emit_branch_if_not (emit, then_len + 5) in
      let _ = if emit == 1 then compile_simple_expr (src, (then_pos + 4, (env, (ctors, 1)))) else (0, 0) in
      let _ = emit_branch (emit, else_len) in
      let _ = if emit == 1 then compile_simple_expr (src, (else_pos + 4, (env, (ctors, 1)))) else (0, 0) in
      (cond_len + 5 + then_len + 5 + else_len, else_end)
    else
      parse_fail 0
  else
    parse_fail 0
in
let rec compile_atom input =
  let (src, pair) = input in
  let (pos0, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, emit) = pair3 in
  let pos = skip_space (src, pos0) in
  if is_if_at (src, pos) then compile_if (src, (pos, (env, (ctors, emit))))
  else compile_simple_atom (src, (pos, (env, (ctors, emit))))
in
let rec string_literal_len state =
  let (src, pair) = state in
  let (pos, count) = pair in
  if src.[pos] == 34 then count else string_literal_len (src, (pos + 1, count + 1))
in
let rec compile_string_tail state =
  let (src, pair) = state in
  let (pos, emit) = pair in
  if src.[pos] == 34 then (0, pos) else
    let push_len = emit_push emit in
    let const_len = emit_const (emit, src.[pos]) in
    let rest = compile_string_tail (src, (pos + 1, emit)) in
    let (rest_len, done_pos) = rest in
    (push_len + const_len + rest_len, done_pos)
in
let rec compile_string_literal state =
  let (src, pair) = state in
  let (pos, emit) = pair in
  let len = string_literal_len (src, (pos + 1, 0)) in
  if len == 0 then
    let const_len = emit_const (emit, 0) in
    let block_len = emit_makeblock (emit, (0, 0)) in
    (const_len + block_len, pos + 2)
  else
    let first_len = emit_const (emit, src.[pos + 1]) in
    let tail = compile_string_tail (src, (pos + 2, emit)) in
    let (tail_len, done_pos) = tail in
    let block_len = emit_makeblock (emit, (0, len)) in
    (first_len + tail_len + block_len, done_pos + 1)
in
let rec compile_debug_string_literal state =
  let (src, pair) = state in
  let (pos, emit) = pair in
  if src.[pos] == 34 then (0, pos + 1) else
    let const_len = emit_const (emit, src.[pos]) in
    let call_len = emit_call_debug_byte emit in
    let rest = compile_debug_string_literal (src, (pos + 1, emit)) in
    let (rest_len, done_pos) = rest in
    (const_len + call_len + rest_len, done_pos)
in
let rec compile_debug_printf_prefix state =
  let (src, pair) = state in
  let (pos, emit) = pair in
  if src.[pos] == 34 then parse_fail 0 else
    if (src.[pos] == 37) * (src.[pos + 1] == 100) then (0, pos + 2) else
      let const_len = emit_const (emit, src.[pos]) in
      let call_len = emit_call_debug_byte emit in
      let rest = compile_debug_printf_prefix (src, (pos + 1, emit)) in
      let (rest_len, done_pos) = rest in
      (const_len + call_len + rest_len, done_pos)
in
let rec skip_debug_printf_suffix state =
  let (src, pos) = state in
  if src.[pos] == 34 then pos + 1 else skip_debug_printf_suffix (src, pos + 1)
in
let rec compile_debug_printf_suffix state =
  let (src, pair) = state in
  let (pos, emit) = pair in
  if src.[pos] == 34 then (0, pos + 1) else
    let const_len = emit_const (emit, src.[pos]) in
    let call_len = emit_call_debug_byte emit in
    let rest = compile_debug_printf_suffix (src, (pos + 1, emit)) in
    let (rest_len, done_pos) = rest in
    (const_len + call_len + rest_len, done_pos)
in
let rec compile_arg_expr input =
  let (src, pair) = input in
  let (pos0, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, pair4) = pair3 in
  let (funcs, emit) = pair4 in
  let _ = funcs in
  let pos = skip_space (src, pos0) in
  let left =
    if src.[pos] == 34 then
      compile_string_literal (src, (pos, emit))
    else if src.[pos] == 40 then
      let inner = compile_simple_expr (src, (pos + 1, (env, (ctors, emit)))) in
      let (inner_len, inner_end0) = inner in
      let inner_end = skip_space (src, inner_end0) in
      if src.[inner_end] == 41 then (inner_len, inner_end + 1) else parse_fail 0
    else
      compile_simple_atom (src, (pos, (env, (ctors, emit))))
  in
  let (left_len0, next00) = left in
  let next1 = skip_space (src, next00) in
  if src.[next1] == 46 then
    let open_ch = src.[next1 + 1] in
    if open_ch == 91 then
      let push_base = emit_push emit in
      let index = compile_simple_expr (src, (next1 + 2, (shift_env env, (ctors, emit)))) in
      let (index_len, index_end0) = index in
      let index_end = skip_space (src, index_end0) in
      if src.[index_end] == 93 then
        let get_len = emit_getfield_dyn emit in
        (left_len0 + push_base + index_len + get_len, index_end + 1)
      else
        parse_fail 0
    else if open_ch == 40 then
      let push_base = emit_push emit in
      let index = compile_simple_expr (src, (next1 + 2, (shift_env env, (ctors, emit)))) in
      let (index_len, index_end0) = index in
      let index_end = skip_space (src, index_end0) in
      if src.[index_end] == 41 then
        let get_len = emit_getfield_dyn emit in
        (left_len0 + push_base + index_len + get_len, index_end + 1)
      else
        parse_fail 0
    else
      let field = parse_ident (src, next1 + 1) in
      let (field_name, field_end) = field in
      let index = lookup_field (ctors, field_name) in
      let field_len = emit_getfield (emit, index) in
      (left_len0 + field_len, field_end)
  else
    left
in
let rec compile_expr input =
  let (src, pair) = input in
  let (pos0, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, pair4) = pair3 in
  let (funcs, emit) = pair4 in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 34 then
    compile_string_literal (src, (pos, emit))
  else if is_string_length_at (src, pos) then
    let after_string_length = need_keyword (src, (pos, "String.length")) in
    let expr = compile_arg_expr (src, (after_string_length, (env, (ctors, (funcs, emit))))) in
    let (expr_len, done_pos) = expr in
    let size_len = emit_blocksize emit in
    (expr_len + size_len, done_pos)
  else if is_bytes_length_at (src, pos) then
    let after_bytes_length = need_keyword (src, (pos, "Bytes.length")) in
    let expr = compile_arg_expr (src, (after_bytes_length, (env, (ctors, (funcs, emit))))) in
    let (expr_len, done_pos) = expr in
    let size_len = emit_blocksize emit in
    (expr_len + size_len, done_pos)
  else if src.[pos] == 123 then
    let field1 = parse_ident (src, pos + 1) in
    let (field1_name, field1_end) = field1 in
    let field1_index = lookup_field (ctors, field1_name) in
    let eq1 = skip_space (src, field1_end) in
    if src.[eq1] == 61 then
      let value1 = compile_expr (src, (eq1 + 1, (env, (ctors, (funcs, emit))))) in
      let (value1_len, value1_end) = value1 in
      let semi = skip_space (src, value1_end) in
      if src.[semi] == 59 then
        let field2 = parse_ident (src, semi + 1) in
        let (field2_name, field2_end) = field2 in
        let field2_index = lookup_field (ctors, field2_name) in
        let eq2 = skip_space (src, field2_end) in
        if src.[eq2] == 61 then
          let push_len = emit_push emit in
          let value2 = compile_expr (src, (eq2 + 1, (shift_env env, (ctors, (funcs, emit))))) in
          let (value2_len, value2_end) = value2 in
          let close = skip_space (src, value2_end) in
          if src.[close] == 125 then
            if field1_index == 0 then
              if field2_index == 1 then
                let block_len = emit_makeblock (emit, (0, 2)) in
                (value1_len + push_len + value2_len + block_len, close + 1)
              else
                parse_fail 0
            else
              parse_fail 0
          else if src.[close] == 59 then
            let field3 = parse_ident (src, close + 1) in
            let (field3_name, field3_end) = field3 in
            let field3_index = lookup_field (ctors, field3_name) in
            let eq3 = skip_space (src, field3_end) in
            if src.[eq3] == 61 then
              let push_len2 = emit_push emit in
              let value3 = compile_expr (src, (eq3 + 1, (shift_env (shift_env env), (ctors, (funcs, emit))))) in
              let (value3_len, value3_end) = value3 in
              let close3 = skip_space (src, value3_end) in
              if src.[close3] == 125 then
                if field1_index == 0 then
                  if field2_index == 1 then
                    if field3_index == 2 then
                      let block_len = emit_makeblock (emit, (0, 3)) in
                      (value1_len + push_len + value2_len + push_len2 + value3_len + block_len, close3 + 1)
                    else
                      parse_fail 0
                  else
                    parse_fail 0
                else
                  parse_fail 0
              else
                parse_fail 0
            else
              parse_fail 0
          else
            parse_fail 0
        else
          parse_fail 0
      else
        parse_fail 0
    else
      parse_fail 0
  else if is_write_byte_at (src, pos) then
    let p = skip_space (src, pos + 10) in
    let expr = compile_expr (src, (p, (env, (ctors, (funcs, emit))))) in
    let (expr_len, done_pos) = expr in
    let call_len = emit_call_write_byte (emit) in
    (expr_len + call_len, done_pos)
  else if is_debug_byte_at (src, pos) then
    let p = need_keyword (src, (pos, "debug_byte")) in
    let expr = compile_expr (src, (p, (env, (ctors, (funcs, emit))))) in
    let (expr_len, done_pos) = expr in
    let call_len = emit_call_debug_byte (emit) in
    (expr_len + call_len, done_pos)
  else if is_debug_int_at (src, pos) then
    let p = need_keyword (src, (pos, "debug_int")) in
    let expr = compile_expr (src, (p, (env, (ctors, (funcs, emit))))) in
    let (expr_len, done_pos) = expr in
    let call_len = emit_call_debug_int (emit) in
    (expr_len + call_len, done_pos)
  else if is_debug_string_at (src, pos) then
    let after_debug_string = need_keyword (src, (pos, "debug_string")) in
    let p = skip_space (src, after_debug_string) in
    if src.[p] == 34 then compile_debug_string_literal (src, (p + 1, emit)) else parse_fail 0
  else if is_debug_printf_at (src, pos) then
    let after_debug_printf = need_keyword (src, (pos, "debug_printf")) in
    let p = skip_space (src, after_debug_printf) in
    if src.[p] == 34 then
      let prefix = compile_debug_printf_prefix (src, (p + 1, emit)) in
      let (prefix_len, suffix_pos) = prefix in
      let expr_pos = skip_space (src, skip_debug_printf_suffix (src, suffix_pos)) in
      let expr = compile_expr (src, (expr_pos, (env, (ctors, (funcs, emit))))) in
      let (expr_len, done_pos) = expr in
      let call_len = emit_call_debug_int emit in
      let suffix = compile_debug_printf_suffix (src, (suffix_pos, emit)) in
      let (suffix_len, suffix_end) = suffix in
      let _ = suffix_end in
      (prefix_len + expr_len + call_len + suffix_len, done_pos)
    else parse_fail 0
	  else if is_exit_at (src, pos) then
	    let p = need_keyword (src, (pos, "exit")) in
	    let expr = compile_expr (src, (p, (env, (ctors, (funcs, emit))))) in
	    let (expr_len, done_pos) = expr in
	    let call_len = emit_call_exit (emit) in
	    (expr_len + call_len, done_pos)
	  else if is_read_byte_at (src, pos) then
	    let len = emit_call_read_byte (emit) in
	    let done_pos = need_keyword (src, (pos, "read_byte")) in
	    (len, done_pos)
	  else if is_bytes_create_at (src, pos) then
	    let after_bytes_create = need_keyword (src, (pos, "Bytes.create")) in
	    let expr = compile_expr (src, (after_bytes_create, (env, (ctors, (funcs, emit))))) in
	    let (expr_len, done_pos) = expr in
	    let push_len = emit_push (emit) in
	    let const_len = emit_const (emit, 0) in
	    let block_len = emit_makeblock_dyn (emit) in
	    (expr_len + push_len + const_len + block_len, done_pos)
	  else if is_cell_create_at (src, pos) then
	    let after_cell_create = need_keyword (src, (pos, "Cell.create")) in
	    let expr = compile_expr (src, (after_cell_create, (env, (ctors, (funcs, emit))))) in
	    let (expr_len, done_pos) = expr in
	    let block_len = emit_makeblock (emit, (0, 1)) in
	    (expr_len + block_len, done_pos)
	  else if is_cell_get_at (src, pos) then
	    let after_cell_get = need_keyword (src, (pos, "Cell.get")) in
	    let expr = compile_arg_expr (src, (after_cell_get, (env, (ctors, (funcs, emit))))) in
	    let (expr_len, done_pos) = expr in
	    let field_len = emit_getfield (emit, 0) in
	    let left_len = expr_len + field_len in
	    let next = skip_space (src, done_pos) in
	    if src.[next] == 43 then
	      let push_len = emit_push (emit) in
	      let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
	      let (right_len, right_done) = right in
	      let add_len = emit_add (emit) in
	      (left_len + push_len + right_len + add_len, right_done)
	    else if src.[next] == 45 then
	      let push_len = emit_push (emit) in
	      let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
	      let (right_len, right_done) = right in
	      let sub_len = emit_sub (emit) in
	      (left_len + push_len + right_len + sub_len, right_done)
	    else if src.[next] == 42 then
	      let push_len = emit_push (emit) in
	      let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
	      let (right_len, right_done) = right in
	      let mul_len = emit_mul (emit) in
	      (left_len + push_len + right_len + mul_len, right_done)
	    else if src.[next] == 47 then
	      let push_len = emit_push (emit) in
	      let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
	      let (right_len, right_done) = right in
	      let div_len = emit_div (emit) in
	      (left_len + push_len + right_len + div_len, right_done)
	    else
	      (left_len, done_pos)
	  else if is_cell_set_at (src, pos) then
	    let after_cell_set = need_keyword (src, (pos, "Cell.set")) in
	    let cell = compile_arg_expr (src, (after_cell_set, (env, (ctors, (funcs, emit))))) in
	    let (cell_len, cell_end) = cell in
	    let push_len = emit_push emit in
	    let value = compile_expr (src, (cell_end, (shift_env env, (ctors, (funcs, emit))))) in
	    let (value_len, done_pos) = value in
	    let set_len = emit_setfield (emit, 0) in
	    (cell_len + push_len + value_len + set_len, done_pos)
	  else if is_if_at (src, pos) then
	    let cond0 = compile_expr (src, (pos + 2, (env, (ctors, (funcs, 0))))) in
	    let (cond_len, cond_end) = cond0 in
	    let then_pos = skip_space (src, cond_end) in
	    if is_then_at (src, then_pos) then
	      let then0 = compile_expr (src, (then_pos + 4, (env, (ctors, (funcs, 0))))) in
	      let (then_len, then_end) = then0 in
	      let else_pos = skip_space (src, then_end) in
	      if is_else_at (src, else_pos) then
	        let else0 = compile_expr (src, (else_pos + 4, (env, (ctors, (funcs, 0))))) in
	        let (else_len, else_end) = else0 in
	        let _ = if emit == 1 then compile_expr (src, (pos + 2, (env, (ctors, (funcs, 1))))) else (0, 0) in
	        let _ = emit_branch_if_not (emit, then_len + 5) in
	        let _ = if emit == 1 then compile_expr (src, (then_pos + 4, (env, (ctors, (funcs, 1))))) else (0, 0) in
	        let _ = emit_branch (emit, else_len) in
	        let _ = if emit == 1 then compile_expr (src, (else_pos + 4, (env, (ctors, (funcs, 1))))) else (0, 0) in
	        (cond_len + 5 + then_len + 5 + else_len, else_end)
	      else
	        parse_fail 0
	    else
	      parse_fail 0
	  else if is_let_at (src, pos) then
    let after_let = skip_space (src, pos + 3) in
    if src.[after_let] == 40 then
      let name1_parsed = parse_ident (src, after_let + 1) in
      let (name1, name1_end0) = name1_parsed in
      let name1_end = skip_space (src, name1_end0) in
      if src.[name1_end] == 44 then
        let name2_parsed = parse_ident (src, name1_end + 1) in
        let (name2, name2_end0) = name2_parsed in
        let name2_end = skip_space (src, name2_end0) in
        if src.[name2_end] == 41 then
          let eq_pos = skip_space (src, name2_end + 1) in
          if src.[eq_pos] == 61 then
            let rhs = compile_expr (src, (eq_pos + 1, (env, (ctors, (funcs, emit))))) in
            let (rhs_len, rhs_end) = rhs in
            let in_pos = skip_space (src, rhs_end) in
            if is_in_at (src, in_pos) then
              let body_pos = skip_space (src, in_pos + 2) in
              let p0 = emit_push emit in
              let a0 = emit_acc (emit, 0) in
              let g0 = emit_getfield (emit, 0) in
              let p1 = emit_push emit in
              let a1 = emit_acc (emit, 1) in
              let g1 = emit_getfield (emit, 1) in
              let p2 = emit_push emit in
              let shifted = shift_env (shift_env (shift_env env)) in
              let body_env = (name2, (0, (name1, (1, shifted)))) in
              let body = compile_expr (src, (body_pos, (body_env, (ctors, (funcs, emit))))) in
              let (body_len, body_end) = body in
              let pop_len = emit_pop (emit, 3) in
              (rhs_len + p0 + a0 + g0 + p1 + a1 + g1 + p2 + body_len + pop_len, body_end)
            else
              parse_fail 0
          else
            parse_fail 0
        else
          parse_fail 0
      else
        parse_fail 0
    else
      let binding = parse_ident (src, pos + 3) in
      let (name, name_end) = binding in
      let eq_pos = skip_space (src, name_end) in
      if src.[eq_pos] == 61 then
        let rhs = compile_expr (src, (eq_pos + 1, (env, (ctors, (funcs, emit))))) in
        let (rhs_len, rhs_end) = rhs in
        let in_pos = skip_space (src, rhs_end) in
        if is_in_at (src, in_pos) then
          let body_pos = skip_space (src, in_pos + 2) in
          let push_len = emit_push emit in
          let body_env = extend_env (name, env) in
          let body = compile_expr (src, (body_pos, (body_env, (ctors, (funcs, emit))))) in
          let (body_len, body_end) = body in
          let pop_len = emit_pop1 emit in
          (rhs_len + push_len + body_len + pop_len, body_end)
        else
          parse_fail 0
      else
        parse_fail 0
  else if is_match_at (src, pos) then
    let scrutinee0 = compile_expr (src, (pos + 5, (env, (ctors, (funcs, 0))))) in
    let (scrutinee_len, scrutinee_end) = scrutinee0 in
    let cases_start = expect_with (src, scrutinee_end) in
    let case_env = shift_env env in
    let case1_pos1 = skip_space (src, cases_start) in
    let case1_pos = if src.[case1_pos1] == 124 then skip_space (src, case1_pos1 + 1) else case1_pos1 in
    let case1_pat = parse_ident (src, case1_pos) in
    let (case1_name, case1_pat_end0) = case1_pat in
    let case1_ctor = lookup_ctor (ctors, case1_name) in
    let case1_has_arg = ctor_has_arg case1_ctor in
    let case1_payload = parse_case_payload (src, (case1_pat_end0, case1_has_arg)) in
    let (case1_tuple, case1_payload2) = case1_payload in
    let (case1_nested, case1_payload3) = case1_payload2 in
    let (case1_bind, case1_payload4) = case1_payload3 in
    let (case1_bind_right, case1_payload5) = case1_payload4 in
    let (case1_bind_third, case1_arrow) = case1_payload5 in
    let case1_body_start = expect_arrow (src, case1_arrow) in
    let case1_env = case_payload_env (case1_has_arg, (case1_tuple, (case1_nested, (case1_bind, (case1_bind_right, (case1_bind_third, case_env)))))) in
    let case1_body0 = compile_expr (src, (case1_body_start, (case1_env, (ctors, (funcs, 0))))) in
    let (case1_body_len, case1_body_end) = case1_body0 in
    let case2_pos1 = skip_space (src, case1_body_end) in
    let case2_pos = if src.[case2_pos1] == 124 then skip_space (src, case2_pos1 + 1) else parse_fail 0 in
    let case2_is_wild = if src.[case2_pos] == 95 then 1 else 0 in
    let case2_pat =
      if case2_is_wild == 1 then (0 - 1, case2_pos + 1) else parse_ident (src, case2_pos)
    in
    let (case2_name, case2_pat_end0) = case2_pat in
    let case2_found_ctor = if case2_is_wild == 1 then 0 else find_ctor (ctors, case2_name) in
    let case2_is_default_var = if case2_is_wild == 1 then 0 else if case2_found_ctor < 0 then is_lower_ident_start (src.[case2_pos]) else 0 in
    let case2_is_default = if case2_is_wild == 1 then 1 else case2_is_default_var in
    let case2_ctor = if case2_is_default == 1 then 0 else if case2_found_ctor < 0 then parse_fail 0 else case2_found_ctor in
    let case2_has_arg = if case2_is_default == 1 then 0 else ctor_has_arg case2_ctor in
    let case2_payload = parse_case_payload (src, (case2_pat_end0, case2_has_arg)) in
    let (case2_tuple, case2_payload2) = case2_payload in
    let (case2_nested, case2_payload3) = case2_payload2 in
    let (case2_bind, case2_payload4) = case2_payload3 in
    let (case2_bind_right, case2_payload5) = case2_payload4 in
    let (case2_bind_third, case2_arrow) = case2_payload5 in
    let case2_body_start = expect_arrow (src, case2_arrow) in
    let case2_env =
      if case2_is_default == 1 then case_default_env (case2_is_wild, (case2_name, case_env)) else
        case_payload_env (case2_has_arg, (case2_tuple, (case2_nested, (case2_bind, (case2_bind_right, (case2_bind_third, case_env))))))
    in
    let case2_body0 = compile_expr (src, (case2_body_start, (case2_env, (ctors, (funcs, 0))))) in
    let (case2_body_len, case2_body_end) = case2_body0 in
    let case3_pos1 = skip_space (src, case2_body_end) in
    let has_case3 = if src.[case3_pos1] == 124 then 1 else 0 in
    let case3_pos = if has_case3 == 1 then skip_space (src, case3_pos1 + 1) else case3_pos1 in
    let case3_is_wild = if has_case3 == 1 then if src.[case3_pos] == 95 then 1 else 0 else 1 in
    let case3_pat =
      if case3_is_wild == 1 then (0 - 1, case3_pos + 1) else parse_ident (src, case3_pos)
    in
    let (case3_name, case3_pat_end0) = case3_pat in
    let case3_found_ctor = if case3_is_wild == 1 then 0 else find_ctor (ctors, case3_name) in
    let case3_is_default_var = if case3_is_wild == 1 then 0 else if case3_found_ctor < 0 then is_lower_ident_start (src.[case3_pos]) else 0 in
    let case3_is_default = if case3_is_wild == 1 then 1 else case3_is_default_var in
    let case3_ctor = if case3_is_default == 1 then 0 else if case3_found_ctor < 0 then parse_fail 0 else case3_found_ctor in
    let case3_has_arg = if case3_is_default == 1 then 0 else ctor_has_arg case3_ctor in
    let case3_payload = parse_case_payload (src, (case3_pat_end0, case3_has_arg)) in
    let (case3_tuple, case3_payload2) = case3_payload in
    let (case3_nested, case3_payload3) = case3_payload2 in
    let (case3_bind, case3_payload4) = case3_payload3 in
    let (case3_bind_right, case3_payload5) = case3_payload4 in
    let (case3_bind_third, case3_arrow) = case3_payload5 in
    let case3_body_start = if has_case3 == 1 then expect_arrow (src, case3_arrow) else case2_body_end in
    let case3_env =
      if case3_is_default == 1 then case_default_env (case3_is_wild, (case3_name, case_env)) else
        case_payload_env (case3_has_arg, (case3_tuple, (case3_nested, (case3_bind, (case3_bind_right, (case3_bind_third, case_env))))))
    in
    let case3_body0 =
      if has_case3 == 1 then compile_expr (src, (case3_body_start, (case3_env, (ctors, (funcs, 0))))) else (0, case2_body_end)
    in
    let (case3_body_len, case3_body_end) = case3_body0 in
    let case4_pos1 = skip_space (src, case3_body_end) in
    let has_case4 = if has_case3 == 1 then if src.[case4_pos1] == 124 then 1 else 0 else 0 in
    let case4_pos = if has_case4 == 1 then skip_space (src, case4_pos1 + 1) else case4_pos1 in
    let case4_is_wild = if has_case4 == 1 then if src.[case4_pos] == 95 then 1 else 0 else 1 in
    let case4_pat =
      if case4_is_wild == 1 then (0 - 1, case4_pos + 1) else parse_ident (src, case4_pos)
    in
    let (case4_name, case4_pat_end0) = case4_pat in
    let case4_found_ctor = if case4_is_wild == 1 then 0 else find_ctor (ctors, case4_name) in
    let case4_is_default_var = if case4_is_wild == 1 then 0 else if case4_found_ctor < 0 then is_lower_ident_start (src.[case4_pos]) else 0 in
    let case4_is_default = if case4_is_wild == 1 then 1 else case4_is_default_var in
    let case4_ctor = if case4_is_default == 1 then 0 else if case4_found_ctor < 0 then parse_fail 0 else case4_found_ctor in
    let case4_has_arg = if case4_is_default == 1 then 0 else ctor_has_arg case4_ctor in
    let case4_payload = parse_case_payload (src, (case4_pat_end0, case4_has_arg)) in
    let (case4_tuple, case4_payload2) = case4_payload in
    let (case4_nested, case4_payload3) = case4_payload2 in
    let (case4_bind, case4_payload4) = case4_payload3 in
    let (case4_bind_right, case4_payload5) = case4_payload4 in
    let (case4_bind_third, case4_arrow) = case4_payload5 in
    let case4_body_start = if has_case4 == 1 then expect_arrow (src, case4_arrow) else case3_body_end in
    let case4_env =
      if case4_is_default == 1 then case_default_env (case4_is_wild, (case4_name, case_env)) else
        case_payload_env (case4_has_arg, (case4_tuple, (case4_nested, (case4_bind, (case4_bind_right, (case4_bind_third, case_env))))))
    in
    let case4_body0 =
      if has_case4 == 1 then compile_expr (src, (case4_body_start, (case4_env, (ctors, (funcs, 0))))) else (0, case3_body_end)
    in
    let (case4_body_len, case4_body_end) = case4_body0 in
    let case1_payload_len = case_payload_len (case1_has_arg, (case1_tuple, case1_nested)) in
    let case1_payload_pop_len = if case1_has_arg == 1 then 5 else 0 in
    let case1_total = case1_payload_len + case1_body_len + case1_payload_pop_len + 5 in
    let case2_payload_len = case_payload_len (case2_has_arg, (case2_tuple, case2_nested)) in
    let case2_payload_pop_len = if case2_has_arg == 1 then 5 else 0 in
    let case2_total = case2_payload_len + case2_body_len + case2_payload_pop_len + 5 in
    let case3_payload_len = case_payload_len (case3_has_arg, (case3_tuple, case3_nested)) in
    let case3_payload_pop_len = if case3_has_arg == 1 then 5 else 0 in
    let case3_total = if has_case3 == 1 then case3_payload_len + case3_body_len + case3_payload_pop_len + 5 else 0 in
    let case4_payload_len = case_payload_len (case4_has_arg, (case4_tuple, case4_nested)) in
    let case4_payload_pop_len = if case4_has_arg == 1 then 5 else 0 in
    let _ = if has_case3 == 1 then if case2_is_default == 1 then parse_fail 0 else 0 else 0 in
    let _ = if has_case4 == 1 then if case3_is_default == 1 then parse_fail 0 else 0 else 0 in
    let case4_total = if has_case4 == 1 then case4_payload_len + case4_body_len + case4_payload_pop_len + 5 else 0 in
    let case3_segment = if has_case4 == 1 then 18 + case3_total + 5 + case4_total else case3_total in
    let case2_segment = if has_case3 == 1 then 18 + case2_total + 5 + case3_segment else case2_total in
    let cases_len = 18 + case1_total + 5 + case2_segment in
    let _ =
      if emit == 1 then
        let _ = compile_expr (src, (pos + 5, (env, (ctors, (funcs, 1))))) in
        let _ = emit_push 1 in
        let _ = emit_acc (1, 0) in
        let _ = emit_gettag 1 in
        let _ = emit_push 1 in
        let _ = emit_const (1, ctor_tag case1_ctor) in
        let _ = emit_eq 1 in
        let _ = emit_branch_if_not (1, case1_total + 5) in
        let _ = emit_case_payload (1, (case1_has_arg, (case1_tuple, case1_nested))) in
        let _ = compile_expr (src, (case1_body_start, (case1_env, (ctors, (funcs, 1))))) in
        let _ = emit_case_payload_pop (1, (case1_has_arg, (case1_tuple, case1_nested))) in
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
        let _ = emit_case_payload (1, (case2_has_arg, (case2_tuple, case2_nested))) in
        let _ = compile_expr (src, (case2_body_start, (case2_env, (ctors, (funcs, 1))))) in
        let _ = emit_case_payload_pop (1, (case2_has_arg, (case2_tuple, case2_nested))) in
	        let _ = emit_pop1 1 in
        let _ = if has_case3 == 1 then emit_branch (1, case3_segment) else 0 in
        let _ =
          if has_case4 == 1 then
            let _ = emit_acc (1, 0) in
            let _ = emit_gettag 1 in
            let _ = emit_push 1 in
            let _ = emit_const (1, ctor_tag case3_ctor) in
            let _ = emit_eq 1 in
            emit_branch_if_not (1, case3_total + 5)
          else 0
        in
        let _ = emit_case_payload (1, (case3_has_arg, (case3_tuple, case3_nested))) in
        let _ = if has_case3 == 1 then compile_expr (src, (case3_body_start, (case3_env, (ctors, (funcs, 1))))) else (0, 0) in
        let _ = emit_case_payload_pop (1, (case3_has_arg, (case3_tuple, case3_nested))) in
        let _ = if has_case3 == 1 then emit_pop1 1 else 0 in
        let _ = if has_case4 == 1 then emit_branch (1, case4_total) else 0 in
        let _ = emit_case_payload (1, (case4_has_arg, (case4_tuple, case4_nested))) in
        let _ = if has_case4 == 1 then compile_expr (src, (case4_body_start, (case4_env, (ctors, (funcs, 1))))) else (0, 0) in
        let _ = emit_case_payload_pop (1, (case4_has_arg, (case4_tuple, case4_nested))) in
        let _ = if has_case4 == 1 then emit_pop1 1 else 0 in
        0
      else
        0
    in
    (scrutinee_len + 1 + cases_len, if has_case4 == 1 then case4_body_end else case3_body_end)
  else if is_ident (src.[pos]) then
    let parsed = parse_ident (src, pos) in
    let (name, name_end) = parsed in
    let depth = find_env (env, name) in
    let found_func = if depth < 0 then find_func (funcs, name) else 0 in
    if found_func == 1 then
      let arg_pos = skip_space (src, name_end) in
      let arg =
        if src.[arg_pos] == 40 then
          let inner = compile_expr (src, (arg_pos + 1, (env, (ctors, (funcs, emit))))) in
          let (inner_len, inner_end0) = inner in
          let inner_end = skip_space (src, inner_end0) in
          if src.[inner_end] == 44 then
            let push_len = emit_push emit in
            let right = compile_expr (src, (inner_end + 1, (shift_env env, (ctors, (funcs, emit))))) in
            let (right_len, right_end0) = right in
            let right_end = skip_space (src, right_end0) in
            if src.[right_end] == 41 then
              let block_len = emit_makeblock (emit, (0, 2)) in
              (inner_len + push_len + right_len + block_len, right_end + 1)
            else
              parse_fail 0
          else if src.[inner_end] == 41 then (inner_len, inner_end + 1) else parse_fail 0
        else if src.[arg_pos] == 34 then
          compile_string_literal (src, (arg_pos, emit))
        else
          compile_atom (src, (arg_pos, (env, (ctors, emit))))
      in
      let (arg_len, arg_end) = arg in
      let target = func_body_start (funcs, name) in
      let call_len = emit_call (emit, target) in
      let left_len = arg_len + call_len in
      let next = skip_space (src, arg_end) in
      if src.[next] == 43 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
        let (right_len, done_pos) = right in
        let add_len = emit_add (emit) in
        (left_len + push_len + right_len + add_len, done_pos)
      else if src.[next] == 45 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
        let (right_len, done_pos) = right in
        let sub_len = emit_sub (emit) in
        (left_len + push_len + right_len + sub_len, done_pos)
      else if src.[next] == 42 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
        let (right_len, done_pos) = right in
        let mul_len = emit_mul (emit) in
        (left_len + push_len + right_len + mul_len, done_pos)
      else if src.[next] == 47 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
        let (right_len, done_pos) = right in
        let div_len = emit_div (emit) in
        (left_len + push_len + right_len + div_len, done_pos)
      else if src.[next] == 60 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let le_len = emit_le (emit) in
          (left_len + push_len + right_len + le_len, done_pos)
        else
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let lt_len = emit_lt (emit) in
          (left_len + push_len + right_len + lt_len, done_pos)
      else if src.[next] == 62 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let ge_len = emit_ge (emit) in
          (left_len + push_len + right_len + ge_len, done_pos)
        else
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let gt_len = emit_gt (emit) in
          (left_len + push_len + right_len + gt_len, done_pos)
      else if src.[next] == 33 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let ne_len = emit_ne (emit) in
          (left_len + push_len + right_len + ne_len, done_pos)
        else
          parse_fail 0
      else if src.[next] == 61 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let eq_len = emit_eq (emit) in
          (left_len + push_len + right_len + eq_len, done_pos)
        else
          parse_fail 0
      else
        (left_len, arg_end)
    else
    let ctor = if depth < 0 then find_ctor (ctors, name) else 0 - 1 in
    if ctor >= 0 then
      let tag = ctor_tag ctor in
      if ctor_is_field ctor then
        parse_fail 0
      else if ctor_has_arg ctor == 1 then
        let payload = compile_expr (src, (name_end, (env, (ctors, (funcs, emit))))) in
        let (payload_len, payload_end) = payload in
        let block_len = emit_makeblock (emit, (tag, 1)) in
        (payload_len + block_len, payload_end)
      else
        let block_len = emit_makeblock (emit, (tag, 0)) in
        (block_len, name_end)
    else
      let left =
        if src.[pos] == 40 then
          let inner = compile_expr (src, (pos + 1, (env, (ctors, (funcs, emit))))) in
          let (inner_len, inner_end0) = inner in
          let inner_end = skip_space (src, inner_end0) in
          if src.[inner_end] == 44 then
            let push_len = emit_push emit in
            let right = compile_expr (src, (inner_end + 1, (shift_env env, (ctors, (funcs, emit))))) in
            let (right_len, right_end0) = right in
            let right_end = skip_space (src, right_end0) in
            if src.[right_end] == 41 then
              let block_len = emit_makeblock (emit, (0, 2)) in
              (inner_len + push_len + right_len + block_len, right_end + 1)
            else
              parse_fail 0
          else if src.[inner_end] == 41 then (inner_len, inner_end + 1) else parse_fail 0
        else
	          compile_atom (src, (pos, (env, (ctors, emit))))
	      in
	      let (left_len0, next00) = left in
	      let next1 = skip_space (src, next00) in
	      let left =
	        if src.[next1] == 46 then
	          let open_ch = src.[next1 + 1] in
	          if open_ch == 91 then
	            let push_base = emit_push (emit) in
	            let index = compile_expr (src, (next1 + 2, (shift_env env, (ctors, (funcs, emit))))) in
	            let (index_len, index_end0) = index in
	            let index_end = skip_space (src, index_end0) in
	            if src.[index_end] == 93 then
	              let after_index = skip_space (src, index_end + 1) in
	              if src.[after_index] == 60 then
	                if src.[after_index + 1] == 45 then
	                  let push_index = emit_push (emit) in
	                  let value = compile_expr (src, (after_index + 2, (shift_env (shift_env env), (ctors, (funcs, emit))))) in
	                  let (value_len, value_end) = value in
	                  let set_len = emit_setfield_dyn (emit) in
	                  (left_len0 + push_base + index_len + push_index + value_len + set_len, value_end)
	                else
	                  parse_fail 0
	              else
	                let get_len = emit_getfield_dyn (emit) in
	                (left_len0 + push_base + index_len + get_len, index_end + 1)
	            else
	              parse_fail 0
	          else if open_ch == 40 then
	            let push_base = emit_push (emit) in
	            let index = compile_expr (src, (next1 + 2, (shift_env env, (ctors, (funcs, emit))))) in
	            let (index_len, index_end0) = index in
	            let index_end = skip_space (src, index_end0) in
	            if src.[index_end] == 41 then
	              let after_index = skip_space (src, index_end + 1) in
	              if src.[after_index] == 60 then
	                if src.[after_index + 1] == 45 then
	                  let push_index = emit_push (emit) in
	                  let value = compile_expr (src, (after_index + 2, (shift_env (shift_env env), (ctors, (funcs, emit))))) in
	                  let (value_len, value_end) = value in
	                  let set_len = emit_setfield_dyn (emit) in
	                  (left_len0 + push_base + index_len + push_index + value_len + set_len, value_end)
	                else
	                  parse_fail 0
	              else
	                let get_len = emit_getfield_dyn (emit) in
	                (left_len0 + push_base + index_len + get_len, index_end + 1)
	            else
	              parse_fail 0
	          else
	            let field = parse_ident (src, next1 + 1) in
	            let (field_name, field_end) = field in
	            let index = lookup_field (ctors, field_name) in
	            let field_len = emit_getfield (emit, index) in
	            (left_len0 + field_len, field_end)
	        else
	          left
	      in
	      let (left_len, next0) = left in
	      let next = skip_space (src, next0) in
      if src.[next] == 43 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
        let (right_len, done_pos) = right in
        let add_len = emit_add (emit) in
        (left_len + push_len + right_len + add_len, done_pos)
      else if src.[next] == 45 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
        let (right_len, done_pos) = right in
        let sub_len = emit_sub (emit) in
        (left_len + push_len + right_len + sub_len, done_pos)
      else if src.[next] == 42 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
        let (right_len, done_pos) = right in
        let mul_len = emit_mul (emit) in
        (left_len + push_len + right_len + mul_len, done_pos)
      else if src.[next] == 47 then
        let push_len = emit_push (emit) in
        let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
        let (right_len, done_pos) = right in
        let div_len = emit_div (emit) in
        (left_len + push_len + right_len + div_len, done_pos)
      else if src.[next] == 60 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let le_len = emit_le (emit) in
          (left_len + push_len + right_len + le_len, done_pos)
        else
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let lt_len = emit_lt (emit) in
          (left_len + push_len + right_len + lt_len, done_pos)
      else if src.[next] == 62 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let ge_len = emit_ge (emit) in
          (left_len + push_len + right_len + ge_len, done_pos)
        else
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let gt_len = emit_gt (emit) in
          (left_len + push_len + right_len + gt_len, done_pos)
      else if src.[next] == 33 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let ne_len = emit_ne (emit) in
          (left_len + push_len + right_len + ne_len, done_pos)
        else
          parse_fail 0
      else if src.[next] == 61 then
        if src.[next + 1] == 61 then
          let push_len = emit_push (emit) in
          let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
          let (right_len, done_pos) = right in
          let eq_len = emit_eq (emit) in
          (left_len + push_len + right_len + eq_len, done_pos)
        else
          parse_fail 0
      else
        left
  else
  let left =
    if src.[pos] == 40 then
      let inner = compile_expr (src, (pos + 1, (env, (ctors, (funcs, emit))))) in
      let (inner_len, inner_end0) = inner in
      let inner_end = skip_space (src, inner_end0) in
      if src.[inner_end] == 44 then
        let push_len = emit_push emit in
        let right = compile_expr (src, (inner_end + 1, (shift_env env, (ctors, (funcs, emit))))) in
        let (right_len, right_end0) = right in
        let right_end = skip_space (src, right_end0) in
        if src.[right_end] == 41 then
          let block_len = emit_makeblock (emit, (0, 2)) in
          (inner_len + push_len + right_len + block_len, right_end + 1)
        else
          parse_fail 0
      else if src.[inner_end] == 41 then (inner_len, inner_end + 1) else parse_fail 0
	    else
	      compile_atom (src, (pos, (env, (ctors, emit))))
	  in
	  let (left_len0, next00) = left in
	  let next1 = skip_space (src, next00) in
	  let left =
	    if src.[next1] == 46 then
	      let open_ch = src.[next1 + 1] in
	      if open_ch == 91 then
	        let push_base = emit_push (emit) in
	        let index = compile_expr (src, (next1 + 2, (shift_env env, (ctors, (funcs, emit))))) in
	        let (index_len, index_end0) = index in
	        let index_end = skip_space (src, index_end0) in
	        if src.[index_end] == 93 then
	          let after_index = skip_space (src, index_end + 1) in
	          if src.[after_index] == 60 then
	            if src.[after_index + 1] == 45 then
	              let push_index = emit_push (emit) in
	              let value = compile_expr (src, (after_index + 2, (shift_env (shift_env env), (ctors, (funcs, emit))))) in
	              let (value_len, value_end) = value in
	              let set_len = emit_setfield_dyn (emit) in
	              (left_len0 + push_base + index_len + push_index + value_len + set_len, value_end)
	            else
	              parse_fail 0
	          else
	            let get_len = emit_getfield_dyn (emit) in
	            (left_len0 + push_base + index_len + get_len, index_end + 1)
	        else
	          parse_fail 0
	      else if open_ch == 40 then
	        let push_base = emit_push (emit) in
	        let index = compile_expr (src, (next1 + 2, (shift_env env, (ctors, (funcs, emit))))) in
	        let (index_len, index_end0) = index in
	        let index_end = skip_space (src, index_end0) in
	        if src.[index_end] == 41 then
	          let after_index = skip_space (src, index_end + 1) in
	          if src.[after_index] == 60 then
	            if src.[after_index + 1] == 45 then
	              let push_index = emit_push (emit) in
	              let value = compile_expr (src, (after_index + 2, (shift_env (shift_env env), (ctors, (funcs, emit))))) in
	              let (value_len, value_end) = value in
	              let set_len = emit_setfield_dyn (emit) in
	              (left_len0 + push_base + index_len + push_index + value_len + set_len, value_end)
	            else
	              parse_fail 0
	          else
	            let get_len = emit_getfield_dyn (emit) in
	            (left_len0 + push_base + index_len + get_len, index_end + 1)
	        else
	          parse_fail 0
	      else
	        let field = parse_ident (src, next1 + 1) in
	        let (field_name, field_end) = field in
	        let index = lookup_field (ctors, field_name) in
	        let field_len = emit_getfield (emit, index) in
	        (left_len0 + field_len, field_end)
	    else
	      left
	  in
	  let (left_len, next0) = left in
	  let next = skip_space (src, next0) in
  if src.[next] == 43 then
    let push_len = emit_push (emit) in
    let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
    let (right_len, done_pos) = right in
    let add_len = emit_add (emit) in
    (left_len + push_len + right_len + add_len, done_pos)
  else if src.[next] == 45 then
    let push_len = emit_push (emit) in
    let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
    let (right_len, done_pos) = right in
    let sub_len = emit_sub (emit) in
    (left_len + push_len + right_len + sub_len, done_pos)
  else if src.[next] == 42 then
    let push_len = emit_push (emit) in
    let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
    let (right_len, done_pos) = right in
    let mul_len = emit_mul (emit) in
    (left_len + push_len + right_len + mul_len, done_pos)
  else if src.[next] == 47 then
    let push_len = emit_push (emit) in
    let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
    let (right_len, done_pos) = right in
    let div_len = emit_div (emit) in
    (left_len + push_len + right_len + div_len, done_pos)
  else if src.[next] == 60 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
      let (right_len, done_pos) = right in
      let le_len = emit_le (emit) in
      (left_len + push_len + right_len + le_len, done_pos)
    else
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
      let (right_len, done_pos) = right in
      let lt_len = emit_lt (emit) in
      (left_len + push_len + right_len + lt_len, done_pos)
  else if src.[next] == 62 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
      let (right_len, done_pos) = right in
      let ge_len = emit_ge (emit) in
      (left_len + push_len + right_len + ge_len, done_pos)
    else
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 1, (shift_env (env), (ctors, (funcs, emit))))) in
      let (right_len, done_pos) = right in
      let gt_len = emit_gt (emit) in
      (left_len + push_len + right_len + gt_len, done_pos)
  else if src.[next] == 33 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
      let (right_len, done_pos) = right in
      let ne_len = emit_ne (emit) in
      (left_len + push_len + right_len + ne_len, done_pos)
    else
      parse_fail 0
  else if src.[next] == 61 then
    if src.[next + 1] == 61 then
      let push_len = emit_push (emit) in
      let right = compile_expr (src, (next + 2, (shift_env (env), (ctors, (funcs, emit))))) in
      let (right_len, done_pos) = right in
      let eq_len = emit_eq (emit) in
      (left_len + push_len + right_len + eq_len, done_pos)
    else
      parse_fail 0
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
  let _ = emit_header ((len * 14) + 1) in
  emit_string_loop (src, pos)
in
let rec compile_write_byte input =
  let (src, pair) = input in
  let (pos, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, pair4) = pair3 in
  let (funcs, emit) = pair4 in
  let p = need_keyword (src, (pos, "write_byte")) in
  let expr = compile_expr (src, (p, (env, (ctors, (funcs, emit))))) in
  let (expr_len, done_pos) = expr in
  let call_len = emit_call_write_byte (emit) in
  (expr_len + call_len, done_pos)
in
let rec skip_string_pos input =
  let (src, pos0) = input in
  if src.[pos0] == 0 then parse_fail 0 else
  if src.[pos0] == '\\' then skip_string_pos (src, pos0 + 2) else
  if src.[pos0] == '"' then pos0 + 1 else skip_string_pos (src, pos0 + 1)
in
let rec skip_char_pos input =
  let (src, pos0) = input in
  if src.[pos0] == 0 then parse_fail 0 else
  if src.[pos0] == '\\' then skip_char_pos (src, pos0 + 2) else
  if src.[pos0] == '\'' then pos0 + 1 else skip_char_pos (src, pos0 + 1)
in
let rec find_and_pos input =
  let (src, pos0) = input in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 0 then 0 - 1 else
  if src.[pos] == '"' then find_and_pos (src, skip_string_pos (src, pos + 1)) else
  if src.[pos] == '\'' then find_and_pos (src, skip_char_pos (src, pos + 1)) else
  if is_in_at (src, pos) == 1 then 0 - 1 else
  if is_and_at (src, pos) == 1 then pos else find_and_pos (src, pos + 1)
in
let rec compile_byte_code input =
  let (src, pair) = input in
  let (pos0, pair2) = pair in
  let (env, pair3) = pair2 in
  let (ctors, pair4) = pair3 in
  let (funcs, pair5) = pair4 in
  let (base, emit) = pair5 in
  let pos = skip_space (src, pos0) in
  if is_let_at (src, pos) then
    let after_let = skip_space (src, pos + 3) in
    let is_rec = is_rec_at (src, after_let) in
    if is_rec == 1 then
      let fname_parsed = parse_ident (src, after_let + 3) in
      let (fname, fname_end) = fname_parsed in
      let param_parsed = parse_ident (src, fname_end) in
      let (param, param_end) = param_parsed in
      let eq_pos = skip_space (src, param_end) in
      if src.[eq_pos] == 61 then
        let fn_body_start = eq_pos + 1 in
        let target = base + 5 in
        let and_pos = find_and_pos (src, fn_body_start) in
        if and_pos >= 0 then
          let sname_parsed = parse_ident (src, and_pos + 3) in
          let (sname, sname_end) = sname_parsed in
          let sparam_parsed = parse_ident (src, sname_end) in
          let (sparam, sparam_end) = sparam_parsed in
          let seq_pos = skip_space (src, sparam_end) in
          if src.[seq_pos] == 61 then
            let s_body_start = seq_pos + 1 in
            let third_and_pos = find_and_pos (src, s_body_start) in
            if third_and_pos >= 0 then
              let tname_parsed = parse_ident (src, third_and_pos + 3) in
              let (tname, tname_end) = tname_parsed in
              let tparam_parsed = parse_ident (src, tname_end) in
              let (tparam, tparam_end) = tparam_parsed in
              let teq_pos = skip_space (src, tparam_end) in
              if src.[teq_pos] == 61 then
                let t_body_start = teq_pos + 1 in
                let provisional_funcs = extend_func (tname, (tparam, (0, extend_func (sname, (sparam, (0, extend_func (fname, (param, (target, funcs))))))))) in
                let fn_env = extend_env (param, env) in
                let fn_body = compile_expr (src, (fn_body_start, (fn_env, (ctors, (provisional_funcs, 0))))) in
                let (fn_len, fn_end) = fn_body in
                let fn_total = 1 + fn_len + 5 + 1 in
                let starget = target + fn_total in
                let funcs2 = extend_func (sname, (sparam, (starget, extend_func (fname, (param, (target, funcs)))))) in
                let funcs2_provisional = extend_func (tname, (tparam, (0, funcs2))) in
                let s_env = extend_env (sparam, env) in
                let s_body = compile_expr (src, (s_body_start, (s_env, (ctors, (funcs2_provisional, 0))))) in
                let (s_len, s_end) = s_body in
                let s_total = 1 + s_len + 5 + 1 in
                let ttarget = starget + s_total in
                let next_funcs = extend_func (tname, (tparam, (ttarget, funcs2))) in
                let t_env = extend_env (tparam, env) in
                let t_body = compile_expr (src, (t_body_start, (t_env, (ctors, (next_funcs, 0))))) in
                let (t_len, t_end) = t_body in
                let t_total = 1 + t_len + 5 + 1 in
                let in_pos = skip_space (src, t_end) in
                let body_pos = if is_in_at (src, in_pos) then skip_space (src, in_pos + 2) else in_pos in
                let body = compile_byte_code (src, (body_pos, (env, (ctors, (next_funcs, (base + 5 + fn_total + s_total + t_total, 0)))))) in
                let (body_len, body_end) = body in
                let _ =
                  if emit == 1 then
                    let _ = emit_branch (1, fn_total + s_total + t_total) in
                    let _ = emit_push 1 in
                    let _ = compile_expr (src, (fn_body_start, (fn_env, (ctors, (next_funcs, 1))))) in
                    let _ = emit_pop1 1 in
                    let _ = emit_return 1 in
                    let _ = emit_push 1 in
                    let _ = compile_expr (src, (s_body_start, (s_env, (ctors, (next_funcs, 1))))) in
                    let _ = emit_pop1 1 in
                    let _ = emit_return 1 in
                    let _ = emit_push 1 in
                    let _ = compile_expr (src, (t_body_start, (t_env, (ctors, (next_funcs, 1))))) in
                    let _ = emit_pop1 1 in
                    let _ = emit_return 1 in
                    compile_byte_code (src, (body_pos, (env, (ctors, (next_funcs, (base + 5 + fn_total + s_total + t_total, 1))))))
                  else
                    (0, 0)
                in
                (5 + fn_total + s_total + t_total + body_len, body_end)
              else
                parse_fail 0
            else
              let provisional_funcs = extend_func (sname, (sparam, (0, extend_func (fname, (param, (target, funcs)))))) in
              let fn_env = extend_env (param, env) in
              let fn_body = compile_expr (src, (fn_body_start, (fn_env, (ctors, (provisional_funcs, 0))))) in
              let (fn_len, fn_end) = fn_body in
              let fn_total = 1 + fn_len + 5 + 1 in
              let starget = target + fn_total in
              let next_funcs = extend_func (sname, (sparam, (starget, extend_func (fname, (param, (target, funcs)))))) in
              let s_env = extend_env (sparam, env) in
              let s_body = compile_expr (src, (s_body_start, (s_env, (ctors, (next_funcs, 0))))) in
              let (s_len, s_end) = s_body in
              let s_total = 1 + s_len + 5 + 1 in
              let in_pos = skip_space (src, s_end) in
              let body_pos = if is_in_at (src, in_pos) then skip_space (src, in_pos + 2) else in_pos in
              let body = compile_byte_code (src, (body_pos, (env, (ctors, (next_funcs, (base + 5 + fn_total + s_total, 0)))))) in
              let (body_len, body_end) = body in
              let _ =
                if emit == 1 then
                  let _ = emit_branch (1, fn_total + s_total) in
                  let _ = emit_push 1 in
                  let _ = compile_expr (src, (fn_body_start, (fn_env, (ctors, (next_funcs, 1))))) in
                  let _ = emit_pop1 1 in
                  let _ = emit_return 1 in
                  let _ = emit_push 1 in
                  let _ = compile_expr (src, (s_body_start, (s_env, (ctors, (next_funcs, 1))))) in
                  let _ = emit_pop1 1 in
                  let _ = emit_return 1 in
                  compile_byte_code (src, (body_pos, (env, (ctors, (next_funcs, (base + 5 + fn_total + s_total, 1))))))
                else
                  (0, 0)
              in
              (5 + fn_total + s_total + body_len, body_end)
          else
            parse_fail 0
        else
          let next_funcs = extend_func (fname, (param, (target, funcs))) in
          let fn_env = extend_env (param, env) in
          let fn_body = compile_expr (src, (fn_body_start, (fn_env, (ctors, (next_funcs, 0))))) in
          let (fn_len, fn_end) = fn_body in
          let fn_total = 1 + fn_len + 5 + 1 in
          let in_pos = skip_space (src, fn_end) in
          let body_pos = if is_in_at (src, in_pos) then skip_space (src, in_pos + 2) else in_pos in
          let body = compile_byte_code (src, (body_pos, (env, (ctors, (next_funcs, (base + 5 + fn_total, 0)))))) in
          let (body_len, body_end) = body in
          let _ =
            if emit == 1 then
              let _ = emit_branch (1, fn_total) in
              let _ = emit_push 1 in
              let _ = compile_expr (src, (fn_body_start, (fn_env, (ctors, (next_funcs, 1))))) in
              let _ = emit_pop1 1 in
              let _ = emit_return 1 in
              compile_byte_code (src, (body_pos, (env, (ctors, (next_funcs, (base + 5 + fn_total, 1))))))
            else
              (0, 0)
          in
          (5 + fn_total + body_len, body_end)
      else
        parse_fail 0
    else
      if src.[after_let] == 40 then
        let name1_parsed = parse_ident (src, after_let + 1) in
        let (name1, name1_end0) = name1_parsed in
        let name1_end = skip_space (src, name1_end0) in
        if src.[name1_end] == 44 then
          let name2_parsed = parse_ident (src, name1_end + 1) in
          let (name2, name2_end0) = name2_parsed in
          let name2_end = skip_space (src, name2_end0) in
          if src.[name2_end] == 41 then
            let eq_pos = skip_space (src, name2_end + 1) in
            if src.[eq_pos] == 61 then
              let rhs = compile_expr (src, (eq_pos + 1, (env, (ctors, (funcs, emit))))) in
              let (rhs_len, rhs_end) = rhs in
              let in_pos = skip_space (src, rhs_end) in
              let body_pos = if is_in_at (src, in_pos) then skip_space (src, in_pos + 2) else in_pos in
              let p0 = emit_push emit in
              let a0 = emit_acc (emit, 0) in
              let g0 = emit_getfield (emit, 0) in
              let p1 = emit_push emit in
              let a1 = emit_acc (emit, 1) in
              let g1 = emit_getfield (emit, 1) in
              let p2 = emit_push emit in
              let shifted = shift_env (shift_env (shift_env env)) in
              let body_env = (name2, (0, (name1, (1, shifted)))) in
              let body_base = base + rhs_len + p0 + a0 + g0 + p1 + a1 + g1 + p2 in
              let body = compile_byte_code (src, (body_pos, (body_env, (ctors, (funcs, (body_base, emit)))))) in
              let (body_len, body_end) = body in
              let pop_len = emit_pop (emit, 3) in
              (rhs_len + p0 + a0 + g0 + p1 + a1 + g1 + p2 + body_len + pop_len, body_end)
            else
              parse_fail 0
          else
            parse_fail 0
        else
          parse_fail 0
      else
        let binding = parse_ident (src, pos + 3) in
        let (name, name_end) = binding in
        let eq_pos = skip_space (src, name_end) in
        if src.[eq_pos] == 61 then
          let rhs = compile_expr (src, (eq_pos + 1, (env, (ctors, (funcs, emit))))) in
          let (rhs_len, rhs_end) = rhs in
          let in_pos = skip_space (src, rhs_end) in
          let body_pos = if is_in_at (src, in_pos) then skip_space (src, in_pos + 2) else in_pos in
          let push_len = emit_push (emit) in
          let next_env = extend_env (name, env) in
          let body_base = base + rhs_len + push_len in
          let body = compile_byte_code (src, (body_pos, (next_env, (ctors, (funcs, (body_base, emit)))))) in
          let (body_len, body_end) = body in
          let pop_len = emit_pop1 (emit) in
          (rhs_len + push_len + body_len + pop_len, body_end)
        else
          parse_fail 0
	  else
	    compile_expr (src, (pos, (env, (ctors, (funcs, emit)))))
	in
let rec emit_byte_source input =
  let (src, start_pos) = input in
  let empty_env = (0 - 1, (0, 0)) in
  let start_ctors = (0 - 1, (0, (0, 0))) in
  let start_funcs = (0 - 1, (0, (0, 0))) in
  let parsed_types = parse_type_decls (src, (start_pos, start_ctors)) in
  let (body_pos, ctors) = parsed_types in
  let measured = compile_byte_code (src, (body_pos, (empty_env, (ctors, (start_funcs, (0, 0)))))) in
  let (code_len, done_pos) = measured in
  let _ = emit_header (code_len + 1) in
  let _ = compile_byte_code (src, (body_pos, (empty_env, (ctors, (start_funcs, (0, 1)))))) in
  write_byte 0
in
let rec compile_program src =
  let pos = skip_space (src, 0) in
  if is_write_string_at (src, pos) then
    let after_write_string = need_keyword (src, (pos, "write_string")) in
    let p0 = skip_space (src, after_write_string) in
    if src.[p0] == 34 then emit_string_program (src, p0 + 1)
    else parse_fail 0
  else
    emit_byte_source (src, pos)
in
let source = Bytes.create 131072 in
let _ = read_all (source, 0) in
compile_program source
