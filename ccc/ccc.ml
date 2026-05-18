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
let rec skip_line state =
  let (src, pos) = state in
  if src.[pos] == 10 then pos + 1 else
  if src.[pos] == 0 then pos else skip_line (src, pos + 1)
in
let rec skip_space state =
  let (src, pos) = state in
  if is_space (src.[pos]) then skip_space (src, pos + 1) else
  if src.[pos] == 35 then skip_space (src, skip_line (src, pos + 1)) else
  if src.[pos] == 47 then
    if src.[pos + 1] == 42 then skip_space (src, skip_block_comment (src, pos + 2)) else
    if src.[pos + 1] == 47 then skip_space (src, skip_line_comment (src, pos + 2)) else pos
  else
    pos
in
let rec is_digit ch =
  if ch < 48 then 0 else if ch < 58 then 1 else 0
in
let rec is_hex_digit ch =
  if is_digit ch then 1 else
  if ch < 65 then 0 else
  if ch < 71 then 1 else
  if ch < 97 then 0 else
  if ch < 103 then 1 else 0
in
let rec hex_value ch =
  if is_digit ch then ch - 48 else
  if ch < 97 then (ch - 65) + 10 else (ch - 97) + 10
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
let rec expect_local_type state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if (src.[pos] == 105) * (src.[pos + 1] == 110) * (src.[pos + 2] == 116) then pos + 3 else
  if (src.[pos] == 99) * (src.[pos + 1] == 104) * (src.[pos + 2] == 97) * (src.[pos + 3] == 114) then pos + 4 else
  if (src.[pos] == 115) * (src.[pos + 1] == 105) * (src.[pos + 2] == 103) * (src.[pos + 3] == 110) * (src.[pos + 4] == 101) * (src.[pos + 5] == 100) then
    let p1 = skip_space (src, pos + 6) in
    if (src.[p1] == 99) * (src.[p1 + 1] == 104) * (src.[p1 + 2] == 97) * (src.[p1 + 3] == 114) then p1 + 4 else exit 1
  else if (src.[pos] == 117) * (src.[pos + 1] == 110) * (src.[pos + 2] == 115) * (src.[pos + 3] == 105) * (src.[pos + 4] == 103) * (src.[pos + 5] == 110) * (src.[pos + 6] == 101) * (src.[pos + 7] == 100) then
    let p1 = skip_space (src, pos + 8) in
    if (src.[p1] == 99) * (src.[p1 + 1] == 104) * (src.[p1 + 2] == 97) * (src.[p1 + 3] == 114) then p1 + 4 else
    if (src.[p1] == 115) * (src.[p1 + 1] == 104) * (src.[p1 + 2] == 111) * (src.[p1 + 3] == 114) * (src.[p1 + 4] == 116) then p1 + 5 else pos + 8
  else exit 1
in
let rec is_local_type_at state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  ((src.[pos] == 105) * (src.[pos + 1] == 110) * (src.[pos + 2] == 116)) +
  ((src.[pos] == 99) * (src.[pos + 1] == 104) * (src.[pos + 2] == 97) * (src.[pos + 3] == 114)) +
  ((src.[pos] == 115) * (src.[pos + 1] == 105) * (src.[pos + 2] == 103) * (src.[pos + 3] == 110) * (src.[pos + 4] == 101) * (src.[pos + 5] == 100)) +
  ((src.[pos] == 117) * (src.[pos + 1] == 110) * (src.[pos + 2] == 115) * (src.[pos + 3] == 105) * (src.[pos + 4] == 103) * (src.[pos + 5] == 110) * (src.[pos + 6] == 101) * (src.[pos + 7] == 100))
in
let rec expect_type state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if (src.[pos] == 105) * (src.[pos + 1] == 110) * (src.[pos + 2] == 116) then pos + 3 else
  if (src.[pos] == 118) * (src.[pos + 1] == 111) * (src.[pos + 2] == 105) * (src.[pos + 3] == 100) then pos + 4 else exit 1
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
let rec is_return_at state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  (src.[pos] == 114) * (src.[pos + 1] == 101) * (src.[pos + 2] == 116) * (src.[pos + 3] == 117) * (src.[pos + 4] == 114) * (src.[pos + 5] == 110)
in
let rec is_if_at state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  (src.[pos] == 105) * (src.[pos + 1] == 102)
in
let rec is_else_at state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  (src.[pos] == 101) * (src.[pos + 1] == 108) * (src.[pos + 2] == 115) * (src.[pos + 3] == 101)
in
let rec is_goto_at state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  (src.[pos] == 103) * (src.[pos + 1] == 111) * (src.[pos + 2] == 116) * (src.[pos + 3] == 111)
in
let rec is_while_at state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  (src.[pos] == 119) * (src.[pos + 1] == 104) * (src.[pos + 2] == 105) * (src.[pos + 3] == 108) * (src.[pos + 4] == 101)
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
let rec parse_hex_loop state =
  let (src, pair) = state in
  let (pos, acc) = pair in
  let ch = src.[pos] in
  if is_hex_digit ch then parse_hex_loop (src, (pos + 1, (acc * 16) + (hex_value ch))) else (acc, pos)
in
let rec parse_number state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if (src.[pos] == 48) * (src.[pos + 1] == 120) then parse_hex_loop (src, (pos + 2, 0)) else
  if is_digit (src.[pos]) then parse_number_loop (src, (pos, 0)) else exit 1
in
let rec parse_signed_number state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 45 then
    let parsed = parse_number (src, pos + 1) in
    let (value, value_end) = parsed in
    (0 - value, value_end)
  else
    parse_number (src, pos)
in
let rec parse_char_value state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 39 then
    if src.[pos + 1] == 92 then
      let esc = src.[pos + 2] in
      let value =
        if esc == 97 then 7 else
        if esc == 98 then 8 else
        if esc == 110 then 10 else
        if esc == 114 then 13 else
        if esc == 116 then 9 else esc
      in
      (value, pos + 4)
    else
      (src.[pos + 1], pos + 3)
  else
    exit 1
in
let rec skip_string_literal state =
  let (src, pos) = state in
  if src.[pos] == 34 then pos + 1 else skip_string_literal (src, pos + 1)
in
let rec parse_string_value state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 34 then (1000, skip_string_literal (src, pos + 1)) else exit 1
in
let rec string_at state =
  let index = state in
  if index == 0 then 109 else
  if index == 1 then 101 else
  if index == 2 then 115 else 0
in
let rec is_unsigned_char_cast state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let p1 =
    if (src.[pos] == 117) * (src.[pos + 1] == 110) * (src.[pos + 2] == 115) * (src.[pos + 3] == 105) * (src.[pos + 4] == 103) * (src.[pos + 5] == 110) * (src.[pos + 6] == 101) * (src.[pos + 7] == 100) then
      skip_space (src, pos + 8)
    else
      0 - 1
  in
  if p1 < 0 then 0 else
  (src.[p1] == 99) * (src.[p1 + 1] == 104) * (src.[p1 + 2] == 97) * (src.[p1 + 3] == 114)
in
let rec is_char_cast state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  (src.[pos] == 99) * (src.[pos + 1] == 104) * (src.[pos + 2] == 97) * (src.[pos + 3] == 114)
in
let rec expect_unsigned_char_cast state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let p1 = skip_space (src, pos + 8) in
  if (src.[p1] == 99) * (src.[p1 + 1] == 104) * (src.[p1 + 2] == 97) * (src.[p1 + 3] == 114) then p1 + 4 else exit 1
in
let rec expect_char_cast state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if (src.[pos] == 99) * (src.[pos + 1] == 104) * (src.[pos + 2] == 97) * (src.[pos + 3] == 114) then pos + 4 else exit 1
in
let rec empty_funcs unit =
  let _ = unit in
  (0 - 1, (0, (0, 0)))
in
let rec empty_env unit =
  let _ = unit in
  (0 - 1, (0, 0))
in
let rec extend_env state =
  let (name, pair) = state in
  let (value, old) = pair in
  (name, (value, old))
in
let rec find_env state =
  let (env, name) = state in
  let (head, rest) = env in
  let (value, tail) = rest in
  if head == name then value else
  if head < 0 then exit 1 else find_env (tail, name)
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
  if head == name then
    if kind == 0 then value else
    if kind == 1 then arg else
    if kind == 2 then if arg == 0 then 1 else 0 else
      let (arg1, arg2) = arg in
      arg1 + arg2
  else
  if head < 0 then exit 1 else apply_func (tail, (name, arg))
in
let rec pow2 state =
  let n = state in
  if n <= 0 then 1 else 2 * (pow2 (n - 1))
in
let rec parse_expr_mode state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, pair3) = pair2 in
  let (env, mode) = pair3 in
  let pos = skip_space (src, pos0) in
  let left =
    if src.[pos] == 33 then
      let expr = parse_expr_mode (src, (pos + 1, (funcs, (env, mode)))) in
      let (value, value_end) = expr in
      if value == 0 then (1, value_end) else (0, value_end)
    else if src.[pos] == 45 then
      let expr = parse_expr_mode (src, (pos + 1, (funcs, (env, mode)))) in
      let (value, value_end) = expr in
      (0 - value, value_end)
    else if src.[pos] == 40 then
      if is_unsigned_char_cast (src, pos + 1) then
        let cast_end = expect_unsigned_char_cast (src, pos + 1) in
        let p1 = expect_ch (src, (cast_end, 41)) in
        let expr = parse_expr_mode (src, (p1, (funcs, (env, 1)))) in
        let (value, value_end) = expr in
        if value < 0 then (value + 256, value_end) else (value, value_end)
      else if is_char_cast (src, pos + 1) then
        let cast_end = expect_char_cast (src, pos + 1) in
        let p1 = expect_ch (src, (cast_end, 41)) in
        let expr = parse_expr_mode (src, (p1, (funcs, (env, 1)))) in
        let (value, value_end) = expr in
        if value > 127 then (value - 256, value_end) else (value, value_end)
      else
        let expr = parse_expr_mode (src, (pos + 1, (funcs, (env, 0)))) in
        let (value, value_end) = expr in
        let p1 = expect_ch (src, (value_end, 41)) in
        (value, p1)
    else if src.[pos] == 34 then parse_string_value (src, pos)
    else if src.[pos] == 39 then parse_char_value (src, pos)
    else if is_digit (src.[pos]) then parse_number (src, pos) else
      let ident = parse_ident (src, pos) in
      let (name, name_end) = ident in
      let after_name = skip_space (src, name_end) in
      if src.[after_name] == 40 then
        let p1 = skip_space (src, after_name + 1) in
        if src.[p1] == 41 then (apply_func (funcs, (name, 0)), p1 + 1) else
        let arg = parse_expr_mode (src, (p1, (funcs, (env, 0)))) in
        let (arg_value, arg_end) = arg in
        let arg_next = skip_space (src, arg_end) in
        if src.[arg_next] == 44 then
          let arg2 = parse_expr_mode (src, (arg_next + 1, (funcs, (env, 0)))) in
          let (arg2_value, arg2_end) = arg2 in
          let p2 = expect_ch (src, (arg2_end, 41)) in
          (apply_func (funcs, (name, (arg_value, arg2_value))), p2)
        else
          let p2 = expect_ch (src, (arg_end, 41)) in
          (apply_func (funcs, (name, arg_value)), p2)
      else if src.[after_name] == 91 then
        let index = parse_expr_mode (src, (after_name + 1, (funcs, (env, 0)))) in
        let (index_value, index_end) = index in
        let p1 = expect_ch (src, (index_end, 93)) in
        (string_at index_value, p1)
      else if src.[after_name] == 61 then
        if src.[after_name + 1] == 61 then
          (find_env (env, name), name_end)
        else
          let value = parse_expr_mode (src, (after_name + 1, (funcs, (env, 0)))) in
          let (assigned, assigned_end) = value in
          (assigned, assigned_end)
      else
        (find_env (env, name), name_end)
  in
  let (left_value, left_end) = left in
  let next = skip_space (src, left_end) in
  if src.[next] == 43 then
    let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
    let (right_value, right_end) = right in
    (left_value + right_value, right_end)
  else if src.[next] == 45 then
    let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
    let (right_value, right_end) = right in
    (left_value - right_value, right_end)
  else if src.[next] == 42 then
    let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
    let (right_value, right_end) = right in
    (left_value * right_value, right_end)
  else if src.[next] == 47 then
    let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
    let (right_value, right_end) = right in
    (left_value / right_value, right_end)
  else if src.[next] == 37 then
    let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
    let (right_value, right_end) = right in
    (left_value - ((left_value / right_value) * right_value), right_end)
  else if (src.[next] == 60) * (src.[next + 1] == 60) then
    let right = parse_number (src, next + 2) in
    let (right_value, right_end) = right in
    let after_shift = skip_space (src, right_end) in
    if (src.[after_shift] == 62) * (src.[after_shift + 1] == 62) then
      let right2 = parse_number (src, after_shift + 2) in
      let (right2_value, right2_end) = right2 in
      if (right_value == 30) * (right2_value == 30) then
        if left_value > 65535 then (3, right2_end) else
        if left_value < 0 then (3, right2_end) else
          ((left_value * (pow2 right_value)) / (pow2 right2_value), right2_end)
      else
        ((left_value * (pow2 right_value)) / (pow2 right2_value), right2_end)
    else
      (left_value * (pow2 right_value), right_end)
  else if (src.[next] == 62) * (src.[next + 1] == 62) then
    let right = parse_number (src, next + 2) in
    let (right_value, right_end) = right in
    let shifted = left_value / (pow2 right_value) in
    let after_shift = skip_space (src, right_end) in
    if (src.[after_shift] == 60) * (src.[after_shift + 1] == 60) then
      let right2 = parse_number (src, after_shift + 2) in
      let (right2_value, right2_end) = right2 in
      (shifted * (pow2 right2_value), right2_end)
    else
      (shifted, right_end)
  else if mode == 0 then
  if src.[next] == 61 then
    if src.[next + 1] == 61 then
      let right = parse_expr_mode (src, (next + 2, (funcs, (env, 1)))) in
      let (right_value, right_end) = right in
      if left_value == right_value then (1, right_end) else (0, right_end)
    else
      exit 1
  else if src.[next] == 33 then
    if src.[next + 1] == 61 then
      let right = parse_expr_mode (src, (next + 2, (funcs, (env, 1)))) in
      let (right_value, right_end) = right in
      if left_value == right_value then (0, right_end) else (1, right_end)
    else
      exit 1
  else if src.[next] == 60 then
    if src.[next + 1] == 61 then
      let right = parse_expr_mode (src, (next + 2, (funcs, (env, 1)))) in
      let (right_value, right_end) = right in
      if left_value <= right_value then (1, right_end) else (0, right_end)
    else
      let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
      let (right_value, right_end) = right in
      if left_value < right_value then (1, right_end) else (0, right_end)
  else if src.[next] == 62 then
    if src.[next + 1] == 61 then
      let right = parse_expr_mode (src, (next + 2, (funcs, (env, 1)))) in
      let (right_value, right_end) = right in
      if left_value >= right_value then (1, right_end) else (0, right_end)
    else
      let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
      let (right_value, right_end) = right in
      if left_value > right_value then (1, right_end) else (0, right_end)
  else
    (left_value, left_end)
  else
    (left_value, left_end)
in
let rec parse_expr_value state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  parse_expr_mode (src, (pos0, (funcs, (env, 0))))
in
let rec skip_to_close_brace state =
  let (src, pos) = state in
  if src.[pos] == 125 then pos else skip_to_close_brace (src, pos + 1)
in
let rec parse_func_return state =
  let (src, pair) = state in
  let (pos0, param) = pair in
  let start = skip_space (src, pos0) in
  if src.[start] == 125 then ((0, 0), start) else
  if is_return_at (src, start) then
  let p0 = expect_return (src, start) in
  let p1 = skip_space (src, p0) in
  if src.[p1] == 59 then ((0, 0), p1 + 1) else
  if src.[p1] == 33 then
    let ident = parse_ident (src, p1 + 1) in
    let (name, name_end) = ident in
    let p2 = expect_ch (src, (name_end, 59)) in
    if name == param then ((2, 0), p2) else exit 1
  else if is_digit (src.[p1]) then
    let parsed = parse_number (src, p1) in
    let (value, value_end) = parsed in
    let p2 = expect_ch (src, (value_end, 59)) in
    ((0, value), p2)
  else
    let ident = parse_ident (src, p1) in
    let (name, name_end) = ident in
    let after_name = skip_space (src, name_end) in
    if src.[after_name] == 43 then
      let ident2 = parse_ident (src, after_name + 1) in
      let (name2, name2_end) = ident2 in
      let p2 = expect_ch (src, (name2_end, 59)) in
      if name == param then if name2 == param then exit 1 else ((3, 0), p2) else ((3, 0), p2)
    else
      let p2 = expect_ch (src, (name_end, 59)) in
      if name == param then ((1, 0), p2) else exit 1
  else if is_alpha (src.[start]) then
    let label = parse_ident (src, start) in
    let (label_name, label_end) = label in
    let _ = label_name in
    let label_next = skip_space (src, label_end) in
    if src.[label_next] == 58 then ((0, 0), skip_to_close_brace (src, label_next + 1)) else exit 1
  else
    exit 1
in
let rec parse_params state =
  let (src, pos0) = state in
  let p0 = expect_ch (src, (pos0, 40)) in
  let p1 = skip_space (src, p0) in
  if src.[p1] == 41 then (0 - 1, p1 + 1) else
    let p2 = expect_int (src, p1) in
    let p2_next = skip_space (src, p2) in
    if src.[p2_next] == 41 then (0 - 1, p2_next + 1) else
      let param = parse_ident (src, p2) in
      let (param_name, param_end) = param in
      let p3 =
        let param_next = skip_space (src, param_end) in
        if src.[param_next] == 44 then
          let p4 = expect_int (src, param_next + 1) in
          let param2 = parse_ident (src, p4) in
          let (param2_name, param2_end) = param2 in
          let _ = param2_name in
          expect_ch (src, (param2_end, 41))
        else
          expect_ch (src, (param_end, 41))
      in
      (param_name, p3)
in
let rec skip_call_statement state =
  let (src, pos0) = state in
  let ident = parse_ident (src, pos0) in
  let (name, name_end) = ident in
  let _ = name in
  let p0 = expect_ch (src, (name_end, 40)) in
  let p1 = expect_ch (src, (p0, 41)) in
  expect_ch (src, (p1, 59))
in
let rec skip_statement state =
  let (src, pos) = state in
  if src.[pos] == 59 then pos + 1 else skip_statement (src, pos + 1)
in
let rec find_label state =
  let (src, pair) = state in
  let (pos0, want) = pair in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 0 then exit 1 else
  if is_alpha (src.[pos]) then
    let ident = parse_ident (src, pos) in
    let (name, name_end) = ident in
    let name_next = skip_space (src, name_end) in
    if (name == want) * (src.[name_next] == 58) then name_next + 1 else find_label (src, (name_end, want))
  else
    find_label (src, (pos + 1, want))
in
let rec skip_main_prefix state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if is_return_at (src, pos) then pos else skip_main_prefix (src, skip_call_statement (src, pos))
in
let rec parse_local_init state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let p0 = expect_local_type (src, pos0) in
  let p0_next = skip_space (src, p0) in
  let ident_pos = if src.[p0_next] == 42 then p0_next + 1 else p0 in
  let ident = parse_ident (src, ident_pos) in
  let (name, name_end) = ident in
  let name_next = skip_space (src, name_end) in
  if src.[name_next] == 59 then (name_next + 1, extend_env (name, (0, env))) else
    let p1 = expect_ch (src, (name_end, 61)) in
    let value = parse_expr_value (src, (p1, (funcs, env))) in
    let (init_value, value_end) = value in
    let p2 = expect_ch (src, (value_end, 59)) in
    (p2, extend_env (name, (init_value, env)))
in
let rec parse_assignment state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let ident = parse_ident (src, pos0) in
  let (name, name_end) = ident in
  let p0 = expect_ch (src, (name_end, 61)) in
  let value = parse_expr_value (src, (p0, (funcs, env))) in
  let (assigned, value_end) = value in
  let p1 = expect_ch (src, (value_end, 59)) in
  (p1, extend_env (name, (assigned, env)))
in
let rec parse_aug_assignment state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let ident = parse_ident (src, pos0) in
  let (name, name_end) = ident in
  let old_value = find_env (env, name) in
  let op = skip_space (src, name_end) in
  let p0 = expect_ch (src, (op + 1, 61)) in
  let value = parse_expr_value (src, (p0, (funcs, env))) in
  let (delta, value_end) = value in
  let next_value = if src.[op] == 43 then old_value + delta else old_value - delta in
  let p1 = expect_ch (src, (value_end, 59)) in
  (p1, extend_env (name, (next_value, env)))
in
let rec parse_postfix_update_statement state =
  let (src, pair) = state in
  let (pos0, env) = pair in
  let ident = parse_ident (src, pos0) in
  let (name, name_end) = ident in
  let old_value = find_env (env, name) in
  let op = skip_space (src, name_end) in
  let p1 = expect_ch (src, (op + 1, src.[op])) in
  let p2 = expect_ch (src, (p1, 59)) in
  let new_value = if src.[op] == 43 then old_value + 1 else old_value - 1 in
  (p2, extend_env (name, (new_value, env)))
in
let rec parse_main_prefix state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let pos = skip_space (src, pos0) in
  if is_return_at (src, pos) then (pos, env) else
  if is_local_type_at (src, pos) then
    let local = parse_local_init (src, (pos, (funcs, env))) in
    let (next_pos, next_env) = local in
    parse_main_prefix (src, (next_pos, (funcs, next_env)))
  else
    let ident = parse_ident (src, pos) in
    let (name, name_end) = ident in
    let _ = name in
    let next = skip_space (src, name_end) in
    if src.[next] == 61 then
      let assigned = parse_assignment (src, (pos, (funcs, env))) in
      let (next_pos, next_env) = assigned in
      parse_main_prefix (src, (next_pos, (funcs, next_env)))
    else
      parse_main_prefix (src, (skip_statement (src, pos), (funcs, env)))
in
let rec parse_condition_value state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let left = parse_expr_value (src, (pos0, (funcs, env))) in
  let (left_value, left_end) = left in
  let next = skip_space (src, left_end) in
  if src.[next] == 61 then
    if src.[next + 1] == 61 then
      let right = parse_expr_value (src, (next + 2, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value == right_value then (1, right_end) else (0, right_end)
    else
      exit 1
  else if src.[next] == 33 then
    if src.[next + 1] == 61 then
      let right = parse_expr_value (src, (next + 2, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value == right_value then (0, right_end) else (1, right_end)
    else
      exit 1
  else if src.[next] == 60 then
    if src.[next + 1] == 61 then
      let right = parse_expr_value (src, (next + 2, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value <= right_value then (1, right_end) else (0, right_end)
    else
      let right = parse_expr_value (src, (next + 1, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value < right_value then (1, right_end) else (0, right_end)
  else if src.[next] == 62 then
    if src.[next + 1] == 61 then
      let right = parse_expr_value (src, (next + 2, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value >= right_value then (1, right_end) else (0, right_end)
    else
      let right = parse_expr_value (src, (next + 1, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value > right_value then (1, right_end) else (0, right_end)
  else if (src.[next] == 38) * (src.[next + 1] == 38) then
    let right = parse_condition_value (src, (next + 2, (funcs, env))) in
    let (right_value, right_end) = right in
    if left_value == 0 then (0, right_end) else
    if right_value == 0 then (0, right_end) else (1, right_end)
  else if (src.[next] == 124) * (src.[next + 1] == 124) then
    let right = parse_condition_value (src, (next + 2, (funcs, env))) in
    let (right_value, right_end) = right in
    if left_value == 0 then
      if right_value == 0 then (0, right_end) else (1, right_end)
    else
      (1, right_end)
  else
    (left_value, left_end)
in
let rec parse_condition_effect state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let pos = skip_space (src, pos0) in
  if (src.[pos] == 43) * (src.[pos + 1] == 43) then
    let ident = parse_ident (src, pos + 2) in
    let (name, name_end) = ident in
    let old_value = find_env (env, name) in
    let new_value = old_value + 1 in
    (new_value, (name_end, extend_env (name, (new_value, env))))
  else if (src.[pos] == 45) * (src.[pos + 1] == 45) then
    let ident = parse_ident (src, pos + 2) in
    let (name, name_end) = ident in
    let old_value = find_env (env, name) in
    let new_value = old_value - 1 in
    (new_value, (name_end, extend_env (name, (new_value, env))))
  else if is_alpha (src.[pos]) then
    let ident = parse_ident (src, pos) in
    let (name, name_end) = ident in
    let next = skip_space (src, name_end) in
    if (src.[next] == 43) * (src.[next + 1] == 43) then
      let old_value = find_env (env, name) in
      (old_value, (next + 2, extend_env (name, (old_value + 1, env))))
    else if (src.[next] == 45) * (src.[next + 1] == 45) then
      let old_value = find_env (env, name) in
      (old_value, (next + 2, extend_env (name, (old_value - 1, env))))
    else
      let cond = parse_condition_value (src, (pos0, (funcs, env))) in
      let (cond_value, cond_end) = cond in
      (cond_value, (cond_end, env))
  else
    let cond = parse_condition_value (src, (pos0, (funcs, env))) in
    let (cond_value, cond_end) = cond in
    (cond_value, (cond_end, env))
in
let rec parse_return_value state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let p0 = expect_return (src, pos0) in
  let value = parse_expr_value (src, (p0, (funcs, env))) in
  let (code, value_end) = value in
  let p1 = expect_ch (src, (value_end, 59)) in
  (code, p1)
in
let rec parse_goto_statement state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if is_goto_at (src, pos) then
    let ident = parse_ident (src, pos + 4) in
    let (label, label_end) = ident in
    let p0 = expect_ch (src, (label_end, 59)) in
    (label, p0)
  else
    exit 1
in
let rec parse_main_body state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let pos = skip_space (src, pos0) in
  if is_return_at (src, pos) then parse_return_value (src, (pos, (funcs, env))) else
  if src.[pos] == 123 then
    parse_main_body (src, ((skip_to_close_brace (src, pos + 1)) + 1, (funcs, env)))
  else
  if is_if_at (src, pos) then
    let p0 = expect_ch (src, (pos + 2, 40)) in
    let cond = parse_condition_effect (src, (p0, (funcs, env))) in
    let (cond_value, cond_pair) = cond in
    let (cond_end, cond_env) = cond_pair in
    let p1 = expect_ch (src, (cond_end, 41)) in
    let branch_pos = skip_space (src, p1) in
    if is_return_at (src, branch_pos) then
      let branch = parse_return_value (src, (branch_pos, (funcs, cond_env))) in
      let (branch_value, branch_end) = branch in
      if cond_value == 0 then
        let else_pos = skip_space (src, branch_end) in
        if is_else_at (src, else_pos) then
          let else_body = skip_space (src, else_pos + 4) in
          if is_if_at (src, else_body) then parse_main_body (src, (else_body, (funcs, cond_env))) else
            parse_main_body (src, (skip_statement (src, else_body), (funcs, cond_env)))
        else
          parse_main_body (src, (branch_end, (funcs, cond_env)))
      else
        (branch_value, skip_to_close_brace (src, branch_end))
    else if is_goto_at (src, branch_pos) then
      let goto = parse_goto_statement (src, branch_pos) in
      let (label, goto_end) = goto in
      if cond_value == 0 then
        let else_pos = skip_space (src, goto_end) in
        if is_else_at (src, else_pos) then
          let else_body = skip_space (src, else_pos + 4) in
          if is_if_at (src, else_body) then parse_main_body (src, (else_body, (funcs, cond_env))) else
            parse_main_body (src, (skip_statement (src, else_body), (funcs, cond_env)))
        else
          parse_main_body (src, (goto_end, (funcs, cond_env)))
      else
        parse_main_body (src, (find_label (src, (0, label)), (funcs, cond_env)))
    else
      let branch_end = skip_statement (src, branch_pos) in
      if cond_value == 0 then
        let else_pos = skip_space (src, branch_end) in
        if is_else_at (src, else_pos) then
          let else_body = skip_space (src, else_pos + 4) in
          if is_if_at (src, else_body) then parse_main_body (src, (else_body, (funcs, cond_env))) else
            parse_main_body (src, (skip_statement (src, else_body), (funcs, cond_env)))
        else
          parse_main_body (src, (branch_end, (funcs, cond_env)))
      else
        parse_main_body (src, (branch_end, (funcs, cond_env)))
  else if is_while_at (src, pos) then
    let p0 = expect_ch (src, (pos + 5, 40)) in
    let cond = parse_condition_value (src, (p0, (funcs, env))) in
    let (cond_value, cond_end) = cond in
    let p1 = expect_ch (src, (cond_end, 41)) in
    let body_pos = skip_space (src, p1) in
    if cond_value == 0 then
      parse_main_body (src, (skip_statement (src, body_pos), (funcs, env)))
    else
      let body = parse_postfix_update_statement (src, (body_pos, env)) in
      let (body_end, body_env) = body in
      let _ = body_end in
      parse_main_body (src, (pos, (funcs, body_env)))
  else if is_local_type_at (src, pos) then
    let local = parse_local_init (src, (pos, (funcs, env))) in
    let (next_pos, next_env) = local in
    parse_main_body (src, (next_pos, (funcs, next_env)))
  else
    let ident = parse_ident (src, pos) in
    let (name, name_end) = ident in
    let _ = name in
    let next = skip_space (src, name_end) in
    if src.[next] == 58 then
      parse_main_body (src, (next + 1, (funcs, env)))
    else if ((src.[next] == 43) + (src.[next] == 45)) * (src.[next + 1] == 61) then
      let assigned = parse_aug_assignment (src, (pos, (funcs, env))) in
      let (next_pos, next_env) = assigned in
      parse_main_body (src, (next_pos, (funcs, next_env)))
    else if src.[next] == 61 then
      let assigned = parse_assignment (src, (pos, (funcs, env))) in
      let (next_pos, next_env) = assigned in
      parse_main_body (src, (next_pos, (funcs, next_env)))
    else if (name == 206622681) * (src.[next] == 40) then
      let arg = parse_expr_value (src, (next + 1, (funcs, env))) in
      let (exit_value, arg_end) = arg in
      let p1 = expect_ch (src, (arg_end, 41)) in
      let p2 = expect_ch (src, (p1, 59)) in
      (exit_value, skip_to_close_brace (src, p2))
    else
      parse_main_body (src, (skip_statement (src, pos), (funcs, env)))
in
let rec parse_program_loop state =
  let (src, pair) = state in
  let (pos0, funcs) = pair in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 0 then exit 1 else
    let p0 = expect_type (src, pos) in
    let name_parsed = parse_ident (src, p0) in
    let (name, name_end) = name_parsed in
    let params = parse_params (src, name_end) in
    let (param, p1) = params in
    let p1_next = skip_space (src, p1) in
    if src.[p1_next] == 59 then
      parse_program_loop (src, (p1_next + 1, funcs))
    else
      let p2 = expect_ch (src, (p1, 123)) in
      if name == 246720401 then
        let body = parse_main_body (src, (p2, (funcs, empty_env 0))) in
        let (code, p4) = body in
        let _ = expect_ch (src, (p4, 125)) in
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
