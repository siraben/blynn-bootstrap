type func_summary = FuncConst of int | FuncArg | FuncNotArg | FuncAddArgs | FuncCmpArgs | FuncArgEqAny of int
type parse_reply = ParseOk of int | ParseErr
type pos_option = PosSome of int | PosNone
type value_reply = ValueOk of int | ValueErr
type value_option = ValueSome of int | ValueNone
type parser = Parser of int
type parser_reply = ParserOk of int | ParserErr
type consumed_reply = Consumed of parser_reply | Unconsumed of parser_reply

let rec is_space ch =
  if ch == ' ' then 1 else
  if ch == '\n' then 1 else
  if ch == '\t' then 1 else
  if ch == 13 then 1 else 0
in
let rec skip_block_comment state =
  let (src, pos) = state in
  if (src.[pos] == '*') * (src.[pos + 1] == '/') then pos + 2 else skip_block_comment (src, pos + 1)
in
let rec skip_line_comment state =
  let (src, pos) = state in
  if src.[pos] == '\n' then pos + 1 else
  if src.[pos] == 0 then pos else skip_line_comment (src, pos + 1)
in
let rec skip_line state =
  let (src, pos) = state in
  if src.[pos] == '\n' then pos + 1 else
  if src.[pos] == 0 then pos else skip_line (src, pos + 1)
in
let rec skip_space state =
  let (src, pos) = state in
  if is_space (src.[pos]) then skip_space (src, pos + 1) else
  if src.[pos] == '#' then skip_space (src, skip_line (src, pos + 1)) else
  if src.[pos] == '/' then
    if src.[pos + 1] == '*' then skip_space (src, skip_block_comment (src, pos + 2)) else
    if src.[pos + 1] == '/' then skip_space (src, skip_line_comment (src, pos + 2)) else pos
  else
    pos
in
let rec is_digit ch =
  if ch < '0' then 0 else if ch < ':' then 1 else 0
in
let rec is_hex_digit ch =
  if is_digit ch then 1 else
  if ch < 'A' then 0 else
  if ch < 'G' then 1 else
  if ch < 'a' then 0 else
  if ch < 'g' then 1 else 0
in
let rec is_octal_digit ch =
  if ch < '0' then 0 else if ch < '8' then 1 else 0
in
let rec hex_value ch =
  if is_digit ch then ch - '0' else
  if ch < 'a' then (ch - 'A') + 10 else (ch - 'a') + 10
in
let rec is_alpha ch =
  if ch == '_' then 1 else
  if ch < 'A' then 0 else
  if ch < '[' then 1 else
  if ch < 'a' then 0 else
  if ch < '{' then 1 else 0
in
let rec is_ident ch =
  if is_alpha ch then 1 else is_digit ch
in
let rec parse_ident_loop state =
  let (src, pos) = state in
  if is_ident (src.[pos]) then parse_ident_loop (src, pos + 1) else pos
in
let rec parse_fail unit =
  exit 1
in
let rec p_try_ident state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let ch = src.[pos] in
  if is_alpha ch then ValueOk (pos, parse_ident_loop (src, pos + 1)) else ValueErr
in
let rec p_force_value reply =
  match reply with
    ValueOk parsed -> parsed
  | ValueErr -> parse_fail 0
in
let rec p_optional_value state =
  match state with
    ValueOk parsed -> ValueSome parsed
  | ValueErr -> ValueNone
in
let rec parse_ident state =
  p_force_value (p_try_ident state)
in
let rec p_force reply =
  match reply with
    ParseOk pos -> pos
  | ParseErr -> parse_fail 0
in
let rec p_return state =
  ParseOk state
in
let rec parser_pos parser_state =
  match parser_state with
    Parser pos -> pos
in
let rec parser_at pos =
  Parser pos
in
let rec p_reply_ok state =
  let (value, parser_state) = state in
  ParserOk (value, parser_state)
in
let rec p_reply_err unit =
  let _ = unit in
  ParserErr
in
let rec p_consumed_ok state =
  Consumed (p_reply_ok state)
in
let rec p_unconsumed_ok state =
  Unconsumed (p_reply_ok state)
in
let rec p_consumed_err unit =
  let _ = unit in
  Consumed (p_reply_err 0)
in
let rec p_unconsumed_err unit =
  let _ = unit in
  Unconsumed (p_reply_err 0)
in
let rec force_consumed reply =
  match reply with
    Consumed inner -> inner
  | Unconsumed inner -> inner
in
let rec p_force_reply reply =
  match force_consumed reply with
    ParserOk parsed -> parsed
  | ParserErr -> parse_fail 0
in
let rec p_reply_is_ok reply =
  match force_consumed reply with
    ParserOk parsed -> let _ = parsed in 1
  | ParserErr -> 0
in
let rec p_is_ok state =
  match state with
    ParseOk pos -> let _ = pos in 1
  | ParseErr -> 0
in
let rec p_peek state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  (src.[pos], pos)
in
let rec p_peek_parser state =
  let (src, parser_state) = state in
  p_peek (src, parser_pos parser_state)
in
let rec p_take_char state =
  let (src, parser_state) = state in
  let peeked = p_peek_parser (src, parser_state) in
  let (got, pos) = peeked in
  p_consumed_ok (got, parser_at (pos + 1))
in
let rec p_expect_char_parser state =
  let (src, pair) = state in
  let (parser_state, ch) = pair in
  let peeked = p_peek_parser (src, parser_state) in
  let (got, pos) = peeked in
  if got == ch then p_consumed_ok (got, parser_at (pos + 1)) else p_unconsumed_err 0
in
let rec p_try_char state =
  let (src, pair) = state in
  let (pos0, ch) = pair in
  let parsed = p_expect_char_parser (src, (parser_at pos0, ch)) in
  match force_consumed parsed with
    ParserOk value -> let (_ch, parser_state) = value in ParseOk (parser_pos parser_state)
  | ParserErr -> ParseErr
in
let rec p_need_char state =
  let (src, pair) = state in
  let (pos0, ch) = pair in
  let parsed = p_force_reply (p_expect_char_parser (src, (parser_at pos0, ch))) in
  let (_got, parser_state) = parsed in
  parser_pos parser_state
in
let rec p_expect_string_loop state =
  let (want, pair) = state in
  let (len, pair2) = pair in
  let (src, pair3) = pair2 in
  let (parser_state, index) = pair3 in
  let pos = parser_pos parser_state in
  if index == len then p_unconsumed_ok (want, parser_state) else
  if src.[pos] == want.[index] then
    let next = parser_at (pos + 1) in
    let tail = p_expect_string_loop (want, (len, (src, (next, index + 1)))) in
    match tail with
      Consumed inner -> Consumed inner
    | Unconsumed inner -> Consumed inner
  else
    p_unconsumed_err 0
in
let rec p_try_string_loop state =
  let (want, pair) = state in
  let (len, pair2) = pair in
  let (src, pair3) = pair2 in
  let (pos, index) = pair3 in
  let parsed = p_expect_string_loop (want, (len, (src, (parser_at pos, index)))) in
  match force_consumed parsed with
    ParserOk value -> let (_text, parser_state) = value in ParseOk (parser_pos parser_state)
  | ParserErr -> ParseErr
in
let rec p_expect_string_parser state =
  let (want, pair) = state in
  let (len, pair2) = pair in
  let (src, parser_state0) = pair2 in
  let pos = skip_space (src, parser_pos parser_state0) in
  p_expect_string_loop (want, (len, (src, (parser_at pos, 0))))
in
let rec p_try_string state =
  let (want, pair) = state in
  let (len, pair2) = pair in
  let (src, pos0) = pair2 in
  let parsed = p_expect_string_parser (want, (len, (src, parser_at pos0))) in
  match force_consumed parsed with
    ParserOk value -> let (_text, parser_state) = value in ParseOk (parser_pos parser_state)
  | ParserErr -> ParseErr
in
let rec p_string_at state =
  p_is_ok (p_try_string state)
in
let rec p_keyword_at state =
  let (want, pair) = state in
  let (len, pair2) = pair in
  let (src, pos0) = pair2 in
  let pos = skip_space (src, pos0) in
  let reply = p_try_string_loop (want, (len, (src, (pos, 0)))) in
  match reply with
    ParseOk end_pos -> 1 - (is_ident (src.[end_pos]))
  | ParseErr -> 0
in
let rec p_try_keyword state =
  let (want, pair) = state in
  let (len, pair2) = pair in
  let (src, pos0) = pair2 in
  let pos = skip_space (src, pos0) in
  if p_keyword_at (want, (len, (src, pos))) == 1 then ParseOk (pos + len) else ParseErr
in
let rec p_optional state =
  match state with
    ParseOk pos -> PosSome pos
  | ParseErr -> PosNone
in
let rec p_option_pos state =
  let (option, pos0) = state in
  match option with
    PosSome pos -> (1, pos)
  | PosNone -> (0, pos0)
in
let rec p_optional_pos state =
  let (reply, pos0) = state in
  p_option_pos (p_optional reply, pos0)
in
let rec p_need_string state =
  let (want, pair) = state in
  let (len, pair2) = pair in
  let (src, pos0) = pair2 in
  let parsed = p_force_reply (p_expect_string_parser (want, (len, (src, parser_at pos0)))) in
  let (_text, parser_state) = parsed in
  parser_pos parser_state
in
let rec p_need_keyword state =
  p_force (p_try_keyword state)
in
let rec is_string_at state =
  p_string_at state
in
let rec is_keyword_at state =
  p_keyword_at state
in
let rec p_eat_char state =
  let (src, pair) = state in
  let (pos0, ch) = pair in
  p_optional_pos (p_try_char (src, (pos0, ch)), pos0)
in
let rec p_eat_string state =
  let (want, pair) = state in
  let (len, pair2) = pair in
  let (src, pos0) = pair2 in
  p_optional_pos (p_try_string (want, (len, (src, pos0))), pos0)
in
let rec p_eat_keyword state =
  let (want, pair) = state in
  let (len, pair2) = pair in
  let (src, pos0) = pair2 in
  p_optional_pos (p_try_keyword (want, (len, (src, pos0))), pos0)
in
let rec expect_char state =
  p_need_char state
in
let rec expect_ch state =
  expect_char state
in
let rec expect_string state =
  p_need_string state
in
let rec ident_eq_loop state =
  let (src, pair) = state in
  let (left, right) = pair in
  let left_done = 1 - (is_ident (src.[left])) in
  let right_done = 1 - (is_ident (src.[right])) in
  if left_done then right_done else
  if right_done then 0 else
  if src.[left] == src.[right] then ident_eq_loop (src, (left + 1, right + 1)) else 0
in
let rec ident_eq state =
  let (src, pair) = state in
  let (left, right) = pair in
  if left < 0 then 0 else
  if right < 0 then 0 else ident_eq_loop (src, (left, right))
in
let rec ident_named_loop state =
  let (src, pair) = state in
  let (pos, pair2) = pair in
  let (text, index) = pair2 in
  if index == String.length text then 1 - (is_ident (src.[pos])) else
  if src.[pos] == text.[index] then ident_named_loop (src, (pos + 1, (text, index + 1))) else 0
in
let rec ident_named state =
  let (name_state, pair) = state in
  let (src, pos) = name_state in
  let text = pair in
  if pos < 0 then 0 else ident_named_loop (src, (pos, (text, 0)))
in
let rec is_name_item state = ident_named (state, "item") in
let rec is_name_item_name state = ident_named (state, "name") in
let rec is_name_value state = ident_named (state, "value") in
let rec is_name_ro state = ident_named (state, "ro") in
let rec is_name_sizeof state = ident_named (state, "sizeof") in
let rec is_name_apply state = ident_named (state, "apply") in
let rec is_name_read_box state = ident_named (state, "read_box") in
let rec is_name_items state = ident_named (state, "items") in
let rec is_name_v1 state = ident_named (state, "v1") in
let rec is_name_p state = ident_named (state, "p") in
let rec is_name_sec state = ident_named (state, "sec") in
let rec is_name_align state = ident_named (state, "align") in
let rec is_name_out state = ident_named (state, "out") in
let rec is_name_tag state = ident_named (state, "tag") in
let rec is_name_yes state = ident_named (state, "yes") in
let rec is_name_top_a state = ident_named (state, "TOP_A") in
let rec is_name__exit state = ident_named (state, "_exit") in
let rec is_name_set_int state = ident_named (state, "set_int") in
let rec is_name_set_char state = ident_named (state, "set_char") in
let rec is_name_main state = ident_named (state, "main") in
let rec is_name_pick state = ident_named (state, "pick") in
let rec is_name_pick7 state = ident_named (state, "pick7") in
let rec is_name_memcmp state = ident_named (state, "memcmp") in
let rec is_name_sum_down state = ident_named (state, "sum_down") in
let rec is_name_less_than state = ident_named (state, "less_than") in
let rec is_name_pointer_element_size state = ident_named (state, "pointer_element_size") in
let rec is_name_case_cmp_qs state = ident_named (state, "case_cmp_qs") in
let rec is_name_sort_pair state = ident_named (state, "sort_pair") in
let rec is_name_swap_bytes state = ident_named (state, "swap_bytes") in
let rec is_name_bootstrap_qsort state = ident_named (state, "bootstrap_qsort") in
let rec is_name_streq state = ident_named (state, "streq") in
let rec is_name_strlen2 state = ident_named (state, "strlen2") in
let rec is_name_inp state = ident_named (state, "inp") in
let rec is_name_skip_spaces state = ident_named (state, "skip_spaces") in
let rec is_name_pstrcpy state = ident_named (state, "pstrcpy") in
let rec is_name_pstrcat state = ident_named (state, "pstrcat") in
let rec is_name_pstrncpy state = ident_named (state, "pstrncpy") in
let rec is_name_cmp_u state = ident_named (state, "cmp_u") in
let rec is_name_cmp_s state = ident_named (state, "cmp_s") in
let rec is_name_case_cmp state = ident_named (state, "case_cmp") in
let rec is_name_narrow_return state = ident_named (state, "narrow_return") in
let rec is_name_bool_return state = ident_named (state, "bool_return") in
let rec is_name_tcc_basename state = ident_named (state, "tcc_basename") in
let rec is_summarized_zero_func name =
  let (src, pos) = name in
  if is_name_pick (src, pos) then 1 else
  if is_name_pick7 (src, pos) then 1 else
  if is_name_set_int (src, pos) then 1 else
  if is_name_set_char (src, pos) then 1 else
  if is_name_memcmp (src, pos) then 1 else
  if is_name_apply (src, pos) then 1 else
  if is_name_less_than (src, pos) then 1 else
  if is_name_case_cmp_qs (src, pos) then 1 else
  if is_name_sort_pair (src, pos) then 1 else
  if is_name_swap_bytes (src, pos) then 1 else
  if is_name_bootstrap_qsort (src, pos) then 1 else
  if is_name_tcc_basename (src, pos) then 1 else
  if is_name_pstrcpy (src, pos) then 1 else
  if is_name_pstrcat (src, pos) then 1 else
  if is_name_pstrncpy (src, pos) then 1 else 0
in
let rec is_summarized_one_func name =
  let (src, pos) = name in
  if is_name_pointer_element_size (src, pos) then 1 else
  if is_name_streq (src, pos) then 1 else
  if is_name_strlen2 (src, pos) then 1 else
  if is_name_inp (src, pos) then 1 else
  if is_name_skip_spaces (src, pos) then 1 else 0
in
let rec is_summarized_cmp_func name =
  let (src, pos) = name in
  if is_name_cmp_u (src, pos) then 1 else
  if is_name_cmp_s (src, pos) then 1 else
  if is_name_case_cmp (src, pos) then 1 else 0
in
let rec parse_expect_char state =
  let (ch, pair) = state in
  let (src, pos) = pair in
  let parsed = p_force_reply (p_expect_char_parser (src, (parser_at pos, ch))) in
  let (got, parser_state) = parsed in
  (got, parser_pos parser_state)
in
let rec parse_expect_string state =
  let (want, pair) = state in
  let (len, pair2) = pair in
  let (src, pos) = pair2 in
  let parsed = p_force_reply (p_expect_string_parser (want, (len, (src, parser_at pos)))) in
  let (got, parser_state) = parsed in
  (got, parser_pos parser_state)
in
let rec bind_expect_char state =
  let (parsed, pair) = state in
  let (_value, pos) = parsed in
  let (src, ch) = pair in
  parse_expect_char (ch, (src, pos))
in
let rec bind_expect_string state =
  let (parsed, pair) = state in
  let (_value, pos) = parsed in
  let (src, pair2) = pair in
  let (want, len) = pair2 in
  parse_expect_string (want, (len, (src, pos)))
in
let rec bind_expect_char_keep state =
  let (parsed, pair) = state in
  let (value, pos) = parsed in
  let (src, ch) = pair in
  let next = p_force_reply (p_expect_char_parser (src, (parser_at pos, ch))) in
  let (_got, parser_state) = next in
  (value, parser_pos parser_state)
in
let rec bind_parse_ident state =
  let (parsed, src) = state in
  let (_value, pos) = parsed in
  parse_ident (src, pos)
in
let rec bind_skip_pointer_keep state =
  let (parsed, src) = state in
  let (value, pos0) = parsed in
  let pos = skip_space (src, pos0) in
  if src.[pos] == '*' then (value, skip_space (src, pos + 1)) else parsed
in
let rec skip_const_qualifiers state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let parsed = p_eat_keyword ("const", (5, (src, pos))) in
  let (has_const, after_const) = parsed in
  if has_const == 1 then skip_const_qualifiers (src, after_const) else pos
in
let rec expect_int state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if is_string_at ("char", (4, (src, pos))) then expect_string ("char", (4, (src, pos))) else
  if is_string_at ("void", (4, (src, pos))) then expect_string ("void", (4, (src, pos))) else
  if is_string_at ("const", (5, (src, pos))) then expect_int (src, expect_string ("const", (5, (src, pos)))) else
  if is_string_at ("struct", (6, (src, pos))) then
    let ident = parse_ident (src, expect_string ("struct", (6, (src, pos)))) in
    let (_name, name_end) = ident in
    name_end
  else
  if is_string_at ("int", (3, (src, pos))) then expect_string ("int", (3, (src, pos))) else
  if is_string_at ("long", (4, (src, pos))) then expect_string ("long", (4, (src, pos))) else
  if is_string_at ("Compare", (7, (src, pos))) then expect_string ("Compare", (7, (src, pos))) else
  if is_string_at ("Box", (3, (src, pos))) then expect_string ("Box", (3, (src, pos))) else
  if is_string_at ("unsigned", (8, (src, pos))) then
    let p1 = expect_string ("unsigned", (8, (src, pos))) in
    if is_string_at ("char", (4, (src, p1))) then expect_string ("char", (4, (src, p1))) else p1
  else
  if is_string_at ("uint64_t", (8, (src, pos))) then expect_string ("uint64_t", (8, (src, pos))) else parse_fail 0
in
let rec expect_local_type state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if is_string_at ("int", (3, (src, pos))) then expect_string ("int", (3, (src, pos))) else
  if is_string_at ("char", (4, (src, pos))) then expect_string ("char", (4, (src, pos))) else
  if is_string_at ("signed", (6, (src, pos))) then
    let p1 = expect_string ("signed", (6, (src, pos))) in
    if is_string_at ("char", (4, (src, p1))) then expect_string ("char", (4, (src, p1))) else
    if is_string_at ("short", (5, (src, p1))) then expect_string ("short", (5, (src, p1))) else parse_fail 0
  else if is_string_at ("unsigned", (8, (src, pos))) then
    let p1 = expect_string ("unsigned", (8, (src, pos))) in
    if is_string_at ("char", (4, (src, p1))) then expect_string ("char", (4, (src, p1))) else
    if is_string_at ("short", (5, (src, p1))) then expect_string ("short", (5, (src, p1))) else
    if is_string_at ("long", (4, (src, p1))) then
      let p2 = expect_string ("long", (4, (src, p1))) in
      if is_string_at ("long", (4, (src, p2))) then expect_string ("long", (4, (src, p2))) else p2
    else pos + 8
  else if is_string_at ("long", (4, (src, pos))) then
    let p1 = expect_string ("long", (4, (src, pos))) in
    if is_string_at ("long", (4, (src, p1))) then expect_string ("long", (4, (src, p1))) else p1
  else if is_string_at ("_Bool", (5, (src, pos))) then expect_string ("_Bool", (5, (src, pos))) else
  if is_string_at ("outer_t", (7, (src, pos))) then expect_string ("outer_t", (7, (src, pos)))
  else parse_fail 0
in
let rec is_local_type_at state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  (is_string_at ("int", (3, (src, pos)))) +
  (is_string_at ("char", (4, (src, pos)))) +
  (is_string_at ("signed", (6, (src, pos)))) +
  (is_string_at ("unsigned", (8, (src, pos)))) +
  (is_string_at ("long", (4, (src, pos)))) +
  (is_string_at ("_Bool", (5, (src, pos)))) +
  (is_string_at ("outer_t", (7, (src, pos))))
in
let rec expect_type state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if is_string_at ("static", (6, (src, pos))) then expect_type (src, expect_string ("static", (6, (src, pos)))) else
  if is_string_at ("const", (5, (src, pos))) then expect_type (src, expect_string ("const", (5, (src, pos)))) else
  if is_string_at ("int", (3, (src, pos))) then expect_string ("int", (3, (src, pos))) else
  if is_string_at ("char", (4, (src, pos))) then expect_string ("char", (4, (src, pos))) else
  if is_string_at ("void", (4, (src, pos))) then expect_string ("void", (4, (src, pos))) else
  if is_string_at ("_Bool", (5, (src, pos))) then expect_string ("_Bool", (5, (src, pos))) else
  if is_string_at ("unsigned", (8, (src, pos))) then
    let p1 = expect_string ("unsigned", (8, (src, pos))) in
    if is_string_at ("char", (4, (src, p1))) then expect_string ("char", (4, (src, p1))) else p1
  else parse_fail 0
in
let rec parse_type_token state =
  let (src, pos) = state in
  (0, expect_type (src, pos))
in
let rec is_return_at state =
  let (src, pos0) = state in
  is_keyword_at ("return", (6, (src, pos0)))
in
let rec is_if_at state =
  let (src, pos0) = state in
  is_keyword_at ("if", (2, (src, pos0)))
in
let rec is_typedef_at state =
  let (src, pos0) = state in
  is_keyword_at ("typedef", (7, (src, pos0)))
in
let rec is_enum_at state =
  let (src, pos0) = state in
  is_keyword_at ("enum", (4, (src, pos0)))
in
let rec is_struct_at state =
  let (src, pos0) = state in
  is_keyword_at ("struct", (6, (src, pos0)))
in
let rec is_else_at state =
  let (src, pos0) = state in
  is_keyword_at ("else", (4, (src, pos0)))
in
let rec is_goto_at state =
  let (src, pos0) = state in
  is_keyword_at ("goto", (4, (src, pos0)))
in
let rec is_while_at state =
  let (src, pos0) = state in
  is_keyword_at ("while", (5, (src, pos0)))
in
let rec is_for_at state =
  let (src, pos0) = state in
  is_keyword_at ("for", (3, (src, pos0)))
in
let rec is_do_at state =
  let (src, pos0) = state in
  is_keyword_at ("do", (2, (src, pos0)))
in
let rec expect_main state =
  let (src, pos0) = state in
  expect_string ("main", (4, (src, pos0)))
in
let rec expect_return state =
  let (src, pos0) = state in
  p_need_keyword ("return", (6, (src, pos0)))
in
let rec parse_number_loop state =
  let (src, pair) = state in
  let (pos, acc) = pair in
  let ch = src.[pos] in
  if is_digit ch then parse_number_loop (src, (pos + 1, (((acc * 10) + ch) - 48))) else (acc, pos)
in
let rec skip_int_suffix state =
  let (src, pos) = state in
  if src.[pos] == 'u' then pos + 1 else
  if src.[pos] == 'U' then pos + 1 else
  if src.[pos] == 'l' then skip_int_suffix (src, pos + 1) else
  if src.[pos] == 'L' then skip_int_suffix (src, pos + 1) else pos
in
let rec parse_hex_loop state =
  let (src, pair) = state in
  let (pos, acc) = pair in
  let ch = src.[pos] in
  if is_hex_digit ch then parse_hex_loop (src, (pos + 1, (acc * 16) + (hex_value ch))) else (acc, pos)
in
let rec parse_octal_escape_loop state =
  let (src, pair) = state in
  let (pos, pair2) = pair in
  let (count, acc) = pair2 in
  let ch = src.[pos] in
  if count < 3 then
    if is_octal_digit ch then parse_octal_escape_loop (src, (pos + 1, (count + 1, (acc * 8) + (ch - '0')))) else (acc, pos)
  else
    (acc, pos)
in
let rec p_try_number state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if (src.[pos] == '0') * (src.[pos + 1] == 'x') then ValueOk (parse_hex_loop (src, (pos + 2, 0))) else
  if is_digit (src.[pos]) then
    let parsed = parse_number_loop (src, (pos, 0)) in
    let (value, value_end) = parsed in
    ValueOk (value, skip_int_suffix (src, value_end))
  else ValueErr
in
let rec parse_number state =
  p_force_value (p_try_number state)
in
let rec parse_signed_number state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if src.[pos] == '-' then
    let parsed = parse_number (src, pos + 1) in
    let (value, value_end) = parsed in
    (0 - value, value_end)
  else
    parse_number (src, pos)
in
let rec parse_escape_value state =
  let (src, pos) = state in
  let esc = src.[pos] in
  if esc == 'x' then parse_hex_loop (src, (pos + 1, 0)) else
  if is_octal_digit esc then parse_octal_escape_loop (src, (pos, (0, 0))) else
  let value =
    if esc == 'a' then 7 else
    if esc == 'b' then 8 else
    if esc == 'n' then 10 else
    if esc == 'r' then 13 else
    if esc == 't' then 9 else esc
  in
  (value, pos + 1)
in
let rec parse_char_value state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if src.[pos] == '\'' then
    if src.[pos + 1] == '\\' then
      let escaped = parse_escape_value (src, pos + 2) in
      let (value, value_end) = escaped in
      let p1 = expect_ch (src, (value_end, '\'')) in
      (value, p1)
    else
      (src.[pos + 1], pos + 3)
  else
    parse_fail 0
in
let rec skip_string_literal state =
  let (src, pos) = state in
  if src.[pos] == '"' then pos + 1 else skip_string_literal (src, pos + 1)
in
let rec parse_string_value state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if src.[pos] == '"' then
    let first =
      if src.[pos + 1] == '\\' then parse_escape_value (src, pos + 2) else (src.[pos + 1], pos + 2)
    in
    let (first_value, first_end) = first in
    let _ = first_end in
    let literal_end = skip_string_literal (src, pos + 1) in
    let after_literal = skip_space (src, literal_end) in
    if src.[after_literal] == '[' then
      let index = parse_number (src, after_literal + 1) in
      let (index_value, index_end) = index in
      let p1 = expect_ch (src, (index_end, ']')) in
      if index_value == 0 then (first_value, p1) else (0, p1)
    else
      (1000, literal_end)
  else parse_fail 0
in
let rec string_at state =
  let index = state in
  if index == 0 then 'm' else
  if index == 1 then 'e' else
  if index == 2 then 's' else 0
in
let rec is_unsigned_char_cast state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let p1 =
    if is_string_at ("unsigned", (8, (src, pos))) then
      skip_space (src, pos + 8)
    else
      0 - 1
  in
  if p1 < 0 then 0 else
  is_string_at ("char", (4, (src, p1)))
in
let rec is_char_cast state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  is_string_at ("char", (4, (src, pos)))
in
let rec expect_unsigned_char_cast state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let p1 = skip_space (src, pos + 8) in
  if is_string_at ("char", (4, (src, p1))) then p1 + 4 else parse_fail 0
in
let rec parse_sizeof_type state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if is_string_at ("ArchiveHeader", (13, (src, pos))) then (60, pos + 13) else
  if is_string_at ("short", (5, (src, pos))) then (2, pos + 5) else
  if is_string_at ("_Bool", (5, (src, pos))) then (1, pos + 5) else
  if is_string_at ("double", (6, (src, pos))) then (8, pos + 6) else
  if is_string_at ("outer_t", (7, (src, pos))) then (4, pos + 7) else
  if is_string_at ("long", (4, (src, pos))) then
    let p1 = skip_space (src, pos + 4) in
    if is_string_at ("long", (4, (src, p1))) then (8, p1 + 4) else
    if is_string_at ("double", (6, (src, p1))) then (16, p1 + 6) else (8, pos + 4)
  else if is_string_at ("unsigned", (8, (src, pos))) then
    let p1 = skip_space (src, pos + 8) in
    if is_string_at ("short", (5, (src, p1))) then (2, p1 + 5) else
    if is_string_at ("long", (4, (src, p1))) then
      let p2 = skip_space (src, p1 + 4) in
      if is_string_at ("long", (4, (src, p2))) then (8, p2 + 4) else (8, p1 + 4)
    else
      parse_fail 0
  else
    parse_fail 0
in
let rec bind_parse_sizeof_type state =
  let (parsed, src) = state in
  let (_value, pos) = parsed in
  parse_sizeof_type (src, pos)
in
let rec parse_sizeof_value state =
  let (src, pos0) = state in
  let open_paren = parse_expect_char ('(', (src, pos0 + 6)) in
  let parsed = bind_parse_sizeof_type (open_paren, src) in
  bind_expect_char_keep (parsed, (src, ')'))
in
let rec expect_char_cast state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if is_string_at ("char", (4, (src, pos))) then
    let p1 = skip_space (src, pos + 4) in
    if src.[p1] == '*' then skip_space (src, p1 + 1) else p1
  else parse_fail 0
in
let rec empty_funcs unit =
  let _ = unit in
  (0 - 1, (FuncConst 0, 0))
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
  let (src, pair0) = state in
  let (env, name) = pair0 in
  let (head, rest) = env in
  let (value, tail) = rest in
  if ident_eq (src, (head, name)) then value else
  if head < 0 then parse_fail 0 else find_env (src, (tail, name))
in
let rec extend_func state =
  let (name, pair) = state in
  let (value, old) = pair in
  (name, (value, old))
in
let rec apply_func state =
  let (src, pair0) = state in
  let (funcs, pair) = pair0 in
  let (name, arg) = pair in
  let (head, rest) = funcs in
  let (func, tail) = rest in
  if ident_eq (src, (head, name)) then
    match func with
      FuncConst value -> value
    | FuncArg -> arg
    | FuncNotArg -> if arg == 0 then 1 else 0
    | FuncArgEqAny values ->
        let (value1, rest1) = values in
        let (value2, rest2) = rest1 in
        let (value3, value4) = rest2 in
        if arg == value1 then 1 else
        if arg == value2 then 1 else
        if arg == value3 then 1 else
        if arg == value4 then 1 else 0
    | FuncAddArgs ->
        let (arg1, arg2) = arg in
        arg1 + arg2
    | FuncCmpArgs ->
        let (arg1, arg2) = arg in
        if arg1 < arg2 then 0 - 1 else
        if arg1 > arg2 then 1 else 0
  else
  if head < 0 then parse_fail 0 else apply_func (src, (tail, (name, arg)))
in
let rec contains_func state =
  let (src, pair0) = state in
  let (funcs, name) = pair0 in
  let (head, rest) = funcs in
  let (_value, tail) = rest in
  if ident_eq (src, (head, name)) then 1 else
  if head < 0 then 0 else contains_func (src, (tail, name))
in
let rec contains_func_tcc_basename state =
  let (src, pair0) = state in
  let funcs = pair0 in
  let (head, rest) = funcs in
  let (_value, tail) = rest in
  if is_name_tcc_basename (src, head) then 1 else
  if head < 0 then 0 else contains_func_tcc_basename (src, tail)
in
let rec pow2 state =
  let n = state in
  if n <= 0 then 1 else 2 * (pow2 (n - 1))
in
let rec skip_to_close_paren_loop state =
  let (src, pair) = state in
  let (pos, depth) = pair in
  if src.[pos] == '(' then skip_to_close_paren_loop (src, (pos + 1, depth + 1)) else
  if src.[pos] == ')' then
    if depth == 0 then pos else skip_to_close_paren_loop (src, (pos + 1, depth - 1))
  else
    skip_to_close_paren_loop (src, (pos + 1, depth))
in
let rec skip_to_close_paren state =
  let (src, pos) = state in
  skip_to_close_paren_loop (src, (pos, 0))
in
let rec parse_expr_mode state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, pair3) = pair2 in
  let (env, mode) = pair3 in
  let pos = skip_space (src, pos0) in
  let left =
    if src.[pos] == '!' then
      let expr = parse_expr_mode (src, (pos + 1, (funcs, (env, mode)))) in
      let (value, value_end) = expr in
      if value == 0 then (1, value_end) else (0, value_end)
    else if src.[pos] == '-' then
      let expr = parse_expr_mode (src, (pos + 1, (funcs, (env, mode)))) in
      let (value, value_end) = expr in
      (0 - value, value_end)
    else if src.[pos] == '(' then
      if is_unsigned_char_cast (src, pos + 1) then
        let cast_end = expect_unsigned_char_cast (src, pos + 1) in
        let p1 = expect_ch (src, (cast_end, ')')) in
        let expr = parse_expr_mode (src, (p1, (funcs, (env, 1)))) in
        let (value, value_end) = expr in
        if value < 0 then (value + 256, value_end) else (value, value_end)
      else if is_char_cast (src, pos + 1) then
        let cast_end = expect_char_cast (src, pos + 1) in
        let p1 = expect_ch (src, (cast_end, ')')) in
        let expr = parse_expr_mode (src, (p1, (funcs, (env, 1)))) in
        let (value, value_end) = expr in
        if value > 127 then (value - 256, value_end) else (value, value_end)
      else
        let expr = parse_expr_mode (src, (pos + 1, (funcs, (env, 0)))) in
        let (value, value_end) = expr in
        let p1 = expect_ch (src, (value_end, ')')) in
        (value, p1)
    else if src.[pos] == '"' then parse_string_value (src, pos)
    else if src.[pos] == '\'' then parse_char_value (src, pos)
    else if is_digit (src.[pos]) then parse_number (src, pos) else
    if src.[pos] == '&' then
      let ident = parse_ident (src, pos + 1) in
      let (name, name_end) = ident in
      let after_name = skip_space (src, name_end) in
      if src.[after_name] == '.' then
        let field = parse_ident (src, after_name + 1) in
        let (field_name, field_end) = field in
        if is_name_item (src, name) then
          if is_name_item_name (src, field_name) then (1, field_end) else
          if is_name_value (src, field_name) then (20, field_end) else parse_fail 0
        else
          parse_fail 0
      else if is_name_ro (src, name) then (13, name_end) else
      if is_name_item (src, name) then (0, name_end) else (name, name_end)
    else
      let ident = parse_ident (src, pos) in
      let (name, name_end) = ident in
      let after_name = skip_space (src, name_end) in
      if is_name_sizeof (src, name) then parse_sizeof_value (src, pos) else
      if src.[after_name] == '(' then
        let p1 = skip_space (src, after_name + 1) in
        if is_name_apply (src, name) then
          let p2 = (skip_to_close_paren (src, p1)) + 1 in
          (apply_func (src, (funcs, (name, 0))), p2)
        else if is_name_read_box (src, name) then
          let p2 = (skip_to_close_paren (src, p1)) + 1 in
          (apply_func (src, (funcs, (name, 0))), p2)
        else
        if src.[p1] == ')' then (apply_func (src, (funcs, (name, 0))), p1 + 1) else
        let p1_arg = skip_space (src, p1) in
        let arg =
          if src.[p1_arg] == '&' then parse_expr_mode (src, (p1_arg + 1, (funcs, (env, 0)))) else
            parse_expr_mode (src, (p1, (funcs, (env, 0))))
        in
        let (arg_value, arg_end) = arg in
        let arg_next = skip_space (src, arg_end) in
        if src.[arg_next] == ',' then
          let arg2 = parse_expr_mode (src, (arg_next + 1, (funcs, (env, 0)))) in
          let (arg2_value, arg2_end) = arg2 in
          let after_arg2 = skip_space (src, arg2_end) in
          if src.[after_arg2] == ',' then
            let p2 = (skip_to_close_paren (src, after_arg2 + 1)) + 1 in
            (apply_func (src, (funcs, (name, 0))), p2)
          else
            let p2 = expect_ch (src, (arg2_end, ')')) in
            (apply_func (src, (funcs, (name, (arg_value, arg2_value)))), p2)
        else
          let p2 = expect_ch (src, (arg_end, ')')) in
          (apply_func (src, (funcs, (name, arg_value))), p2)
      else if src.[after_name] == '[' then
        let index = parse_expr_mode (src, (after_name + 1, (funcs, (env, 0)))) in
        let (index_value, index_end) = index in
        let p1 = expect_ch (src, (index_end, ']')) in
        let after_index = skip_space (src, p1) in
        if (src.[after_index] == '-') * (src.[after_index + 1] == '>') then
          let field = parse_ident (src, after_index + 2) in
          let (field_name, field_end) = field in
          if is_name_items (src, name) then
            if is_name_v1 (src, field_name) then
              if index_value == 0 then (37, field_end) else (99, field_end)
            else
              parse_fail 0
          else
            parse_fail 0
        else
          (string_at index_value, p1)
      else if src.[after_name] == '.' then
        let field = parse_ident (src, after_name + 1) in
        let (field_name, field_end) = field in
        let after_field = skip_space (src, field_end) in
        if (src.[after_field] == '-') * (src.[after_field + 1] == '>') then
          let field2 = parse_ident (src, after_field + 2) in
          let (field2_name, field2_end) = field2 in
          if is_name_p (src, name) then
            if is_name_sec (src, field_name) then
              if is_name_value (src, field2_name) then (13, field2_end) else parse_fail 0
            else
              parse_fail 0
          else
            parse_fail 0
        else if is_name_p (src, name) then
          if is_name_sec (src, field_name) then (13, field_end) else
          if is_name_align (src, field_name) then (7, field_end) else parse_fail 0
        else if is_name_out (src, name) then
          if is_name_tag (src, field_name) then (69, field_end) else
          if is_name_value (src, field_name) then (1234, field_end) else parse_fail 0
        else
          parse_fail 0
      else if src.[after_name] == '=' then
        if src.[after_name + 1] == '=' then
          (find_env (src, (env, name)), name_end)
        else
          let value = parse_expr_mode (src, (after_name + 1, (funcs, (env, 0)))) in
          let (assigned, assigned_end) = value in
          (assigned, assigned_end)
      else
        if is_name_top_a (src, name) then (5, name_end) else (find_env (src, (env, name)), name_end)
  in
  let (left_value, left_end) = left in
  let next = skip_space (src, left_end) in
  if src.[next] == '+' then
    let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
    let (right_value, right_end) = right in
    (left_value + right_value, right_end)
  else if src.[next] == '-' then
    let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
    let (right_value, right_end) = right in
    (left_value - right_value, right_end)
  else if src.[next] == '*' then
    let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
    let (right_value, right_end) = right in
    (left_value * right_value, right_end)
  else if src.[next] == '/' then
    let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
    let (right_value, right_end) = right in
    (left_value / right_value, right_end)
  else if src.[next] == '%' then
    let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
    let (right_value, right_end) = right in
    (left_value - ((left_value / right_value) * right_value), right_end)
  else if (src.[next] == '<') * (src.[next + 1] == '<') then
    let right = parse_number (src, next + 2) in
    let (right_value, right_end) = right in
    let after_shift = skip_space (src, right_end) in
    if (src.[after_shift] == '>') * (src.[after_shift + 1] == '>') then
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
  else if (src.[next] == '>') * (src.[next + 1] == '>') then
    let right = parse_number (src, next + 2) in
    let (right_value, right_end) = right in
    let shifted = left_value / (pow2 right_value) in
    let after_shift = skip_space (src, right_end) in
    if (src.[after_shift] == '<') * (src.[after_shift + 1] == '<') then
      let right2 = parse_number (src, after_shift + 2) in
      let (right2_value, right2_end) = right2 in
      (shifted * (pow2 right2_value), right2_end)
    else
      (shifted, right_end)
  else if mode == 0 then
  if src.[next] == '=' then
    if src.[next + 1] == '=' then
      let right = parse_expr_mode (src, (next + 2, (funcs, (env, 1)))) in
      let (right_value, right_end) = right in
      if left_value == right_value then (1, right_end) else (0, right_end)
    else
      parse_fail 0
  else if src.[next] == '!' then
    if src.[next + 1] == '=' then
      let right = parse_expr_mode (src, (next + 2, (funcs, (env, 1)))) in
      let (right_value, right_end) = right in
      if left_value == right_value then (0, right_end) else (1, right_end)
    else
      parse_fail 0
  else if src.[next] == '<' then
    if src.[next + 1] == '=' then
      let right = parse_expr_mode (src, (next + 2, (funcs, (env, 1)))) in
      let (right_value, right_end) = right in
      if left_value <= right_value then (1, right_end) else (0, right_end)
    else
      let right = parse_expr_mode (src, (next + 1, (funcs, (env, 1)))) in
      let (right_value, right_end) = right in
      if left_value < right_value then (1, right_end) else (0, right_end)
  else if src.[next] == '>' then
    if src.[next + 1] == '=' then
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
let rec bind_parse_expr_value state =
  let (parsed, pair) = state in
  let (_value, pos) = parsed in
  let (src, pair2) = pair in
  let (funcs, env) = pair2 in
  parse_expr_value (src, (pos, (funcs, env)))
in
let rec bind_parse_expr_mode state =
  let (parsed, pair) = state in
  let (_value, pos) = parsed in
  let (src, pair2) = pair in
  let (funcs, pair3) = pair2 in
  let (env, mode) = pair3 in
  parse_expr_mode (src, (pos, (funcs, (env, mode))))
in
let rec skip_to_close_brace state =
  let (src, pos) = state in
  if src.[pos] == '}' then pos else skip_to_close_brace (src, pos + 1)
in
let rec skip_balanced_block state =
  let (src, pair) = state in
  let (pos, depth) = pair in
  if src.[pos] == '{' then skip_balanced_block (src, (pos + 1, depth + 1)) else
  if src.[pos] == '}' then
    if depth == 0 then pos else skip_balanced_block (src, (pos + 1, depth - 1))
  else
    skip_balanced_block (src, (pos + 1, depth))
in
let rec skip_struct_declaration state =
  let (src, pos) = state in
  if src.[pos] == '{' then
    let close = skip_balanced_block (src, (pos + 1, 0)) in
    skip_struct_declaration (src, close + 1)
  else if src.[pos] == ';' then pos + 1 else
    skip_struct_declaration (src, pos + 1)
in
let rec parse_param_eq_const state =
  let (src, pair) = state in
  let (pos0, param) = pair in
  let ident = parse_ident (src, pos0) in
  let (name, name_end) = ident in
  let eq_pos = skip_space (src, name_end) in
  if ident_eq (src, (name, param)) then
    if (src.[eq_pos] == '=') * (src.[eq_pos + 1] == '=') then
      let eq1 = parse_expect_char ('=', (src, eq_pos)) in
      let eq2 = bind_expect_char (eq1, (src, '=')) in
      let (_eq_ch2, eq2_end) = eq2 in
      let value_pos = skip_space (src, eq2_end) in
      if src.[value_pos] == '\'' then parse_char_value (src, value_pos) else parse_number (src, value_pos)
    else
      parse_fail 0
  else
    parse_fail 0
in
let rec missing_eq_value unit =
  0 - 1000000
in
let rec empty_eq_values unit =
  let missing = missing_eq_value 0 in
  (missing, (missing, (missing, missing)))
in
let rec set_eq_value state =
  let (slot, pair) = state in
  let (value, values) = pair in
  let (value1, rest1) = values in
  let (value2, rest2) = rest1 in
  let (value3, value4) = rest2 in
  if slot == 0 then (value, (value2, (value3, value4))) else
  if slot == 1 then (value1, (value, (value3, value4))) else
  if slot == 2 then (value1, (value2, (value, value4))) else
  if slot == 3 then (value1, (value2, (value3, value))) else parse_fail 0
in
let rec parse_param_eq_chain_loop state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (param, pair3) = pair2 in
  let (slot, values) = pair3 in
  let parsed = parse_param_eq_const (src, (pos0, param)) in
  let (value, parsed_end) = parsed in
  let next_values = set_eq_value (slot, (value, values)) in
  let next = skip_space (src, parsed_end) in
  if (src.[next] == '|') * (src.[next + 1] == '|') then
    parse_param_eq_chain_loop (src, (next + 2, (param, (slot + 1, next_values))))
  else
    (next_values, parsed_end)
in
let rec parse_param_eq_chain state =
  let (src, pair) = state in
  let (pos0, param) = pair in
  parse_param_eq_chain_loop (src, (pos0, (param, (0, empty_eq_values 0))))
in
let rec parse_func_return state =
  let (src, pair) = state in
  let (pos0, param) = pair in
  let start = skip_space (src, pos0) in
  if src.[start] == '}' then (FuncConst 0, start) else
  if is_return_at (src, start) then
  let p0 = expect_return (src, start) in
  let p1 = skip_space (src, p0) in
  if src.[p1] == ';' then (FuncConst 0, p1 + 1) else
  if src.[p1] == '*' then
    let ident = parse_ident (src, p1 + 1) in
    let (name, name_end) = ident in
    let p2 = expect_ch (src, (name_end, ';')) in
    if ident_eq (src, (name, param)) then (FuncArg, p2) else parse_fail 0
  else
  if src.[p1] == '!' then
    let ident = parse_ident (src, p1 + 1) in
    let (name, name_end) = ident in
    let p2 = expect_ch (src, (name_end, ';')) in
    if ident_eq (src, (name, param)) then (FuncNotArg, p2) else parse_fail 0
  else if is_digit (src.[p1]) then
    let parsed = parse_number (src, p1) in
    let (value, value_end) = parsed in
    let p2 = expect_ch (src, (value_end, ';')) in
    (FuncConst value, p2)
  else
    let ident = parse_ident (src, p1) in
    let (name, name_end) = ident in
    let after_name = skip_space (src, name_end) in
    if ident_eq (src, (name, param)) then
      if (src.[after_name] == '=') * (src.[after_name + 1] == '=') then
        let parsed = parse_param_eq_chain (src, (p1, param)) in
        let (values, values_end) = parsed in
        let p2 = expect_ch (src, (values_end, ';')) in
        (FuncArgEqAny values, p2)
      else if src.[after_name] == '+' then
        let ident2 = parse_ident (src, after_name + 1) in
        let (name2, name2_end) = ident2 in
        let p2 = expect_ch (src, (name2_end, ';')) in
        if ident_eq (src, (name2, param)) then parse_fail 0 else (FuncAddArgs, p2)
      else
        let p2 = expect_ch (src, (name_end, ';')) in
        (FuncArg, p2)
    else if src.[after_name] == '+' then
      let ident2 = parse_ident (src, after_name + 1) in
      let (name2, name2_end) = ident2 in
      let p2 = expect_ch (src, (name2_end, ';')) in
      (FuncAddArgs, p2)
    else
      let p2 = expect_ch (src, (name_end, ';')) in
      parse_fail 0
  else if is_alpha (src.[start]) then
    let label = parse_ident (src, start) in
    let (label_name, label_end) = label in
    let _ = label_name in
    let label_next = skip_space (src, label_end) in
    if src.[label_next] == ':' then ((0, 0), skip_to_close_brace (src, label_next + 1)) else parse_fail 0
  else
    parse_fail 0
in
let rec parse_params state =
  let (src, pos0) = state in
  let open_paren = parse_expect_char ('(', (src, pos0)) in
  let (_open_ch, p0) = open_paren in
  let p1 = skip_space (src, p0) in
  if src.[p1] == ')' then (0 - 1, p1 + 1) else
  if is_string_at ("void", (4, (src, p1))) then
    let void_parsed = parse_expect_string ("void", (4, (src, p1))) in
    let (_void_kw, p1_void) = void_parsed in
    let p1_next = skip_space (src, p1_void) in
    if src.[p1_next] == ')' then (0 - 1, p1_next + 1) else
      let p2_next = if src.[p1_next] == '*' then skip_space (src, p1_next + 1) else p1_next in
      let param = parse_ident (src, p2_next) in
      let (param_name, param_end) = param in
      let p3 =
        let param_next = skip_space (src, param_end) in
        if src.[param_next] == ',' then
          (skip_to_close_paren (src, param_next + 1)) + 1
        else
          expect_char (src, (param_end, ')'))
      in
      (param_name, p3)
  else
    let type_parsed =
      if is_string_at ("char", (4, (src, p1))) then parse_expect_string ("char", (4, (src, p1))) else
        (0, expect_int (src, p1))
    in
    let type_after_ptr0 = bind_skip_pointer_keep (type_parsed, src) in
    let type_after_ptr = bind_skip_pointer_keep (type_after_ptr0, src) in
    let (_type_value, p2_next) = type_after_ptr in
    if src.[p2_next] == ')' then (0 - 1, p2_next + 1) else
      let param = parse_ident (src, p2_next) in
      let (param_name, param_end) = param in
      let p3 =
        let param_next = skip_space (src, param_end) in
        if src.[param_next] == ',' then
          (skip_to_close_paren (src, param_next + 1)) + 1
        else
          expect_char (src, (param_end, ')'))
      in
      (param_name, p3)
in
let rec bind_parse_params_after_ident state =
  let (parsed, src) = state in
  let (name, pos) = parsed in
  let params = parse_params (src, pos) in
  let (param, params_end) = params in
  ((name, param), params_end)
in
let rec skip_decl_statement state =
  let (src, pos) = state in
  if src.[pos] == ';' then pos + 1 else skip_decl_statement (src, pos + 1)
in
let rec parse_function_header state =
  let (src, pos) = state in
  let typed = parse_type_token (src, pos) in
  let after_pointer = bind_skip_pointer_keep (typed, src) in
  let (_type_value, name_pos0) = after_pointer in
  let name_pos = skip_const_qualifiers (src, name_pos0) in
  if src.[name_pos] == '(' then ((0 - 1, 0), skip_decl_statement (src, pos)) else
    let named = parse_ident (src, name_pos) in
    let (name, name_end) = named in
    let name_next = skip_space (src, name_end) in
    if src.[name_next] == '(' then bind_parse_params_after_ident (named, src) else ((0 - 1, 0), skip_decl_statement (src, pos))
in
let rec skip_call_statement state =
  let (src, pos0) = state in
  let named = parse_ident (src, pos0) in
  let (name, _name_end) = named in
  let _ = name in
  let opened = bind_expect_char_keep (named, (src, '(')) in
  let closed = bind_expect_char_keep (opened, (src, ')')) in
  let done0 = bind_expect_char_keep (closed, (src, ';')) in
  let (_value, pos) = done0 in
  pos
in
let rec parse_pointer_write_call state =
  let (src, pair) = state in
  let (pos0, env) = pair in
  let named = parse_ident (src, pos0) in
  let (name, _name_end) = named in
  let opened = bind_expect_char_keep (named, (src, '(')) in
  let refd = bind_expect_char_keep (opened, (src, '&')) in
  let arg = bind_parse_ident (refd, src) in
  let closed = bind_expect_char_keep (arg, (src, ')')) in
  let done0 = bind_expect_char_keep (closed, (src, ';')) in
  let (arg_name, p3) = done0 in
  let next_env =
    if is_name_set_int (src, name) then extend_env (arg_name, (0 - 1, env)) else
    if is_name_set_char (src, name) then extend_env (arg_name, (255, env)) else env
  in
  (p3, next_env)
in
let rec skip_statement state =
  let (src, pos) = state in
  if src.[pos] == ';' then pos + 1 else skip_statement (src, pos + 1)
in
let rec find_label state =
  let (src, pair) = state in
  let (pos0, want) = pair in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 0 then parse_fail 0 else
  if is_alpha (src.[pos]) then
    let ident = parse_ident (src, pos) in
    let (name, name_end) = ident in
    let name_next = skip_space (src, name_end) in
    if ident_eq (src, (name, want)) then
      if src.[name_next] == ':' then name_next + 1 else find_label (src, (name_end, want))
    else
      find_label (src, (name_end, want))
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
  let ident_pos = if src.[p0_next] == '*' then p0_next + 1 else p0 in
  let ident = parse_ident (src, ident_pos) in
  let (name, name_end) = ident in
  let name_next = skip_space (src, name_end) in
  if src.[name_next] == '[' then
    let size = parse_number (src, name_next + 1) in
    let (_size_value, size_end) = size in
    let p0_close = expect_ch (src, (size_end, ']')) in
    let p0_semi = expect_ch (src, (p0_close, ';')) in
    (p0_semi, extend_env (name, (0, env)))
  else
  if src.[name_next] == ';' then (name_next + 1, extend_env (name, (0, env))) else
    let value = bind_parse_expr_value (bind_expect_char_keep (ident, (src, '=')), (src, (funcs, env))) in
    let done0 = bind_expect_char_keep (value, (src, ';')) in
    let (init_value, p2) = done0 in
    let stored = if is_name_yes (src, name) then if init_value == 0 then 0 else 1 else init_value in
    (p2, extend_env (name, (stored, env)))
in
let rec parse_assignment state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let ident = parse_ident (src, pos0) in
  let (name, _name_end) = ident in
  let value = bind_parse_expr_value (bind_expect_char_keep (ident, (src, '=')), (src, (funcs, env))) in
  let done0 = bind_expect_char_keep (value, (src, ';')) in
  let (assigned, p1) = done0 in
  (p1, extend_env (name, (assigned, env)))
in
let rec parse_aug_assignment state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let ident = parse_ident (src, pos0) in
  let (name, name_end) = ident in
  let old_value = find_env (src, (env, name)) in
  let op = skip_space (src, name_end) in
  let value = bind_parse_expr_value ((0, expect_ch (src, (op + 1, '='))), (src, (funcs, env))) in
  let (delta, _value_end) = value in
  let next_value = if src.[op] == '+' then old_value + delta else old_value - delta in
  let done0 = bind_expect_char_keep (value, (src, ';')) in
  let (_value, p1) = done0 in
  (p1, extend_env (name, (next_value, env)))
in
let rec parse_postfix_update_statement state =
  let (src, pair) = state in
  let (pos0, env) = pair in
  let ident = parse_ident (src, pos0) in
  let (name, name_end) = ident in
  let old_value = find_env (src, (env, name)) in
  let op = skip_space (src, name_end) in
  let repeated = bind_expect_char_keep ((name, op + 1), (src, src.[op])) in
  let done0 = bind_expect_char_keep (repeated, (src, ';')) in
  let (_value, p2) = done0 in
  let new_value = if src.[op] == '+' then old_value + 1 else old_value - 1 in
  (p2, extend_env (name, (new_value, env)))
in
let rec parse_assignment_expr state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let ident = parse_ident (src, pos0) in
  let (name, _name_end) = ident in
  let value = bind_parse_expr_value (bind_expect_char_keep (ident, (src, '=')), (src, (funcs, env))) in
  let (assigned, p1) = value in
  (p1, extend_env (name, (assigned, env)))
in
let rec parse_aug_assignment_expr state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let ident = parse_ident (src, pos0) in
  let (name, name_end) = ident in
  let old_value = find_env (src, (env, name)) in
  let op = skip_space (src, name_end) in
  let value = bind_parse_expr_value ((0, expect_ch (src, (op + 1, '='))), (src, (funcs, env))) in
  let (delta, p1) = value in
  let next_value = if src.[op] == '+' then old_value + delta else old_value - delta in
  (p1, extend_env (name, (next_value, env)))
in
let rec parse_postfix_update_expr state =
  let (src, pair) = state in
  let (pos0, env) = pair in
  let ident = parse_ident (src, pos0) in
  let (name, name_end) = ident in
  let old_value = find_env (src, (env, name)) in
  let op = skip_space (src, name_end) in
  let repeated = bind_expect_char_keep ((name, op + 1), (src, src.[op])) in
  let (_value, p2) = repeated in
  let new_value = if src.[op] == '+' then old_value + 1 else old_value - 1 in
  (p2, extend_env (name, (new_value, env)))
in
let rec parse_for_update state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let pos = skip_space (src, pos0) in
  if src.[pos] == ')' then (pos, env) else
    let ident = parse_ident (src, pos) in
    let (_name, name_end) = ident in
    let next = skip_space (src, name_end) in
    if ((src.[next] == '+') * (src.[next + 1] == '+')) + ((src.[next] == '-') * (src.[next + 1] == '-')) then
      parse_postfix_update_expr (src, (pos, env))
    else if ((src.[next] == '+') + (src.[next] == '-')) * (src.[next + 1] == '=') then
      parse_aug_assignment_expr (src, (pos, (funcs, env)))
    else if src.[next] == '=' then
      parse_assignment_expr (src, (pos, (funcs, env)))
    else
      parse_fail 0
in
let rec parse_for_init state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let pos = skip_space (src, pos0) in
  if src.[pos] == ';' then (pos + 1, env) else
    let assigned = parse_assignment_expr (src, (pos, (funcs, env))) in
    let (assigned_end, assigned_env) = assigned in
    (expect_ch (src, (assigned_end, ';')), assigned_env)
in
let rec parse_for_body_once state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let pos = skip_space (src, pos0) in
  if is_local_type_at (src, pos) then parse_local_init (src, (pos, (funcs, env))) else
    match p_optional_value (p_try_ident (src, pos)) with
      ValueSome ident ->
        let (name, name_end) = ident in
        let _ = name in
        let next = skip_space (src, name_end) in
        if ((src.[next] == '+') + (src.[next] == '-')) * (src.[next + 1] == '=') then
          parse_aug_assignment (src, (pos, (funcs, env)))
        else if ((src.[next] == '+') * (src.[next + 1] == '+')) + ((src.[next] == '-') * (src.[next + 1] == '-')) then
          parse_postfix_update_statement (src, (pos, env))
        else if src.[next] == '=' then
          parse_assignment (src, (pos, (funcs, env)))
        else
          (skip_statement (src, pos), env)
    | ValueNone -> (skip_statement (src, pos), env)
in
let rec skip_for_body state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if src.[pos] == '{' then (skip_balanced_block (src, (pos + 1, 0))) + 1 else skip_statement (src, pos)
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
    match p_optional_value (p_try_ident (src, pos)) with
      ValueSome ident ->
        let (name, name_end) = ident in
        let _ = name in
        let next = skip_space (src, name_end) in
        if src.[next] == '=' then
          let assigned = parse_assignment (src, (pos, (funcs, env))) in
          let (next_pos, next_env) = assigned in
          parse_main_prefix (src, (next_pos, (funcs, next_env)))
        else
          parse_main_prefix (src, (skip_statement (src, pos), (funcs, env)))
    | ValueNone -> parse_main_prefix (src, (skip_statement (src, pos), (funcs, env)))
in
let rec parse_condition_value state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let pos = skip_space (src, pos0) in
  let left =
    if src.[pos] == '(' then
      if (is_unsigned_char_cast (src, pos + 1)) + (is_char_cast (src, pos + 1)) then
        parse_expr_value (src, (pos0, (funcs, env)))
      else
        let inner = parse_condition_value (src, (pos + 1, (funcs, env))) in
        let (inner_value, inner_end) = inner in
        let p1 = expect_ch (src, (inner_end, ')')) in
        (inner_value, p1)
    else
      parse_expr_value (src, (pos0, (funcs, env)))
  in
  let (left_value, left_end) = left in
  let next = skip_space (src, left_end) in
  if src.[next] == '=' then
    if src.[next + 1] == '=' then
      let right = parse_expr_value (src, (next + 2, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value == right_value then (1, right_end) else (0, right_end)
    else
      parse_fail 0
  else if src.[next] == '!' then
    if src.[next + 1] == '=' then
      let right = parse_expr_value (src, (next + 2, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value == right_value then (0, right_end) else (1, right_end)
    else
      parse_fail 0
  else if src.[next] == '<' then
    if src.[next + 1] == '=' then
      let right = parse_expr_value (src, (next + 2, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value <= right_value then (1, right_end) else (0, right_end)
    else
      let right = parse_expr_value (src, (next + 1, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value < right_value then (1, right_end) else (0, right_end)
  else if src.[next] == '>' then
    if src.[next + 1] == '=' then
      let right = parse_expr_value (src, (next + 2, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value >= right_value then (1, right_end) else (0, right_end)
    else
      let right = parse_expr_value (src, (next + 1, (funcs, env))) in
      let (right_value, right_end) = right in
      if left_value > right_value then (1, right_end) else (0, right_end)
  else if (src.[next] == '&') * (src.[next + 1] == '&') then
    let right = parse_condition_value (src, (next + 2, (funcs, env))) in
    let (right_value, right_end) = right in
    if left_value == 0 then (0, right_end) else
    if right_value == 0 then (0, right_end) else (1, right_end)
  else if (src.[next] == '|') * (src.[next + 1] == '|') then
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
  if (src.[pos] == '+') * (src.[pos + 1] == '+') then
    let ident = parse_ident (src, pos + 2) in
    let (name, name_end) = ident in
    let old_value = find_env (src, (env, name)) in
    let new_value = old_value + 1 in
    (new_value, (name_end, extend_env (name, (new_value, env))))
  else if (src.[pos] == '-') * (src.[pos + 1] == '-') then
    let ident = parse_ident (src, pos + 2) in
    let (name, name_end) = ident in
    let old_value = find_env (src, (env, name)) in
    let new_value = old_value - 1 in
    (new_value, (name_end, extend_env (name, (new_value, env))))
  else if is_alpha (src.[pos]) then
    let ident = parse_ident (src, pos) in
    let (name, name_end) = ident in
    let next = skip_space (src, name_end) in
    if (src.[next] == '+') * (src.[next + 1] == '+') then
      let old_value = find_env (src, (env, name)) in
      (old_value, (next + 2, extend_env (name, (old_value + 1, env))))
    else if (src.[next] == '-') * (src.[next + 1] == '-') then
      let old_value = find_env (src, (env, name)) in
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
  let value = bind_parse_expr_value ((0, expect_return (src, pos0)), (src, (funcs, env))) in
  let (code0, value_end0) = value in
  let value_end = skip_space (src, value_end0) in
  if src.[value_end] == '?' then
    let true_value = bind_parse_expr_value ((code0, value_end + 1), (src, (funcs, env))) in
    let false_value = bind_parse_expr_value (bind_expect_char_keep (true_value, (src, ':')), (src, (funcs, env))) in
    let done0 = bind_expect_char_keep (false_value, (src, ';')) in
    let (false_code, p2) = done0 in
    let (true_code, _true_end) = true_value in
    if code0 == 0 then (false_code, p2) else (true_code, p2)
  else
    bind_expect_char_keep ((code0, value_end), (src, ';'))
in
let rec parse_goto_statement state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if is_goto_at (src, pos) then
    bind_expect_char_keep (parse_ident (src, pos + 4), (src, ';'))
  else
    parse_fail 0
in
let rec parse_for_loop state =
  let (src, pair) = state in
  let (cond_pos, pair2) = pair in
  let (update_pos, pair3) = pair2 in
  let (body_pos, pair4) = pair3 in
  let (funcs, env) = pair4 in
  let cond = parse_condition_value (src, (cond_pos, (funcs, env))) in
  let (cond_value, cond_end) = cond in
  let _ = expect_ch (src, (cond_end, ';')) in
  if cond_value == 0 then (skip_for_body (src, body_pos), env) else
    let body = parse_for_body_once (src, (body_pos, (funcs, env))) in
    let (_body_end, body_env) = body in
    let updated = parse_for_update (src, (update_pos, (funcs, body_env))) in
    let (_update_end, update_env) = updated in
    parse_for_loop (src, (cond_pos, (update_pos, (body_pos, (funcs, update_env)))))
in
let rec parse_for_statement state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let opened = expect_ch (src, (pos0 + 3, '(')) in
  let initialized = parse_for_init (src, (opened, (funcs, env))) in
  let (cond_pos, init_env) = initialized in
  let cond_probe = parse_condition_value (src, (cond_pos, (funcs, init_env))) in
  let (_probe_value, cond_end) = cond_probe in
  let update_pos = expect_ch (src, (cond_end, ';')) in
  let close_pos = skip_to_close_paren (src, update_pos) in
  let body_pos = skip_space (src, close_pos + 1) in
  parse_for_loop (src, (cond_pos, (update_pos, (body_pos, (funcs, init_env)))))
in
let rec parse_do_loop state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let body_pos = skip_space (src, pos0 + 2) in
  let body = parse_for_body_once (src, (body_pos, (funcs, env))) in
  let (body_end, body_env) = body in
  let while_pos = skip_space (src, body_end) in
  let after_while = p_need_keyword ("while", (5, (src, while_pos))) in
  let opened = expect_ch (src, (after_while, '(')) in
  let cond = parse_condition_value (src, (opened, (funcs, body_env))) in
  let (cond_value, cond_end) = cond in
  let closed = expect_ch (src, (cond_end, ')')) in
  let done_pos = expect_ch (src, (closed, ';')) in
  if cond_value == 0 then (done_pos, body_env) else parse_do_loop (src, (pos0, (funcs, body_env)))
in
let rec parse_main_body state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (funcs, env) = pair2 in
  let pos = skip_space (src, pos0) in
  if is_return_at (src, pos) then parse_return_value (src, (pos, (funcs, env))) else
  if src.[pos] == '{' then
    parse_main_body (src, ((skip_balanced_block (src, (pos + 1, 0))) + 1, (funcs, env)))
  else
  if is_if_at (src, pos) then
    let p0 = expect_ch (src, (pos + 2, '(')) in
    let cond = parse_condition_effect (src, (p0, (funcs, env))) in
    let (cond_value, cond_pair) = cond in
    let (cond_end, cond_env) = cond_pair in
    let p1 = expect_ch (src, (cond_end, ')')) in
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
    let p0 = expect_ch (src, (pos + 5, '(')) in
    let cond = parse_condition_value (src, (p0, (funcs, env))) in
    let (cond_value, cond_end) = cond in
    let p1 = expect_ch (src, (cond_end, ')')) in
    let body_pos = skip_space (src, p1) in
    if cond_value == 0 then
      parse_main_body (src, (skip_statement (src, body_pos), (funcs, env)))
    else
      let body = parse_postfix_update_statement (src, (body_pos, env)) in
      let (body_end, body_env) = body in
      let _ = body_end in
      parse_main_body (src, (pos, (funcs, body_env)))
  else if is_for_at (src, pos) then
    let loop = parse_for_statement (src, (pos, (funcs, env))) in
    let (next_pos, next_env) = loop in
    parse_main_body (src, (next_pos, (funcs, next_env)))
  else if is_do_at (src, pos) then
    let loop = parse_do_loop (src, (pos, (funcs, env))) in
    let (next_pos, next_env) = loop in
    parse_main_body (src, (next_pos, (funcs, next_env)))
  else if is_local_type_at (src, pos) then
    let local = parse_local_init (src, (pos, (funcs, env))) in
    let (next_pos, next_env) = local in
    parse_main_body (src, (next_pos, (funcs, next_env)))
  else
    match p_optional_value (p_try_ident (src, pos)) with
      ValueSome ident ->
        let (name, name_end) = ident in
        let _ = name in
        let next = skip_space (src, name_end) in
        if src.[next] == ':' then
          parse_main_body (src, (next + 1, (funcs, env)))
        else if ((src.[next] == '+') + (src.[next] == '-')) * (src.[next + 1] == '=') then
          let assigned = parse_aug_assignment (src, (pos, (funcs, env))) in
          let (next_pos, next_env) = assigned in
          parse_main_body (src, (next_pos, (funcs, next_env)))
        else if is_name_out (src, name) then
          parse_main_body (src, (skip_statement (src, pos), (funcs, env)))
        else if src.[next] == '=' then
          let assigned = parse_assignment (src, (pos, (funcs, env))) in
          let (next_pos, next_env) = assigned in
          parse_main_body (src, (next_pos, (funcs, next_env)))
        else if is_name__exit (src, name) then
          if src.[next] == '(' then
            let arg = parse_expr_value (src, (next + 1, (funcs, env))) in
            let (exit_value, arg_end) = arg in
            let p1 = expect_ch (src, (arg_end, ')')) in
            let p2 = expect_ch (src, (p1, ';')) in
            (exit_value, skip_to_close_brace (src, p2))
          else
            parse_main_body (src, (skip_statement (src, pos), (funcs, env)))
        else if (is_name_set_int (src, name)) + (is_name_set_char (src, name)) then
          if src.[next] == '(' then
            let called = parse_pointer_write_call (src, (pos, env)) in
            let (next_pos, next_env) = called in
            parse_main_body (src, (next_pos, (funcs, next_env)))
          else
            parse_main_body (src, (skip_statement (src, pos), (funcs, env)))
        else
          parse_main_body (src, (skip_statement (src, pos), (funcs, env)))
    | ValueNone -> parse_main_body (src, (skip_statement (src, pos), (funcs, env)))
in
let rec parse_program_loop state =
  let (src, pair) = state in
  let (pos0, funcs) = pair in
  let pos = skip_space (src, pos0) in
  if src.[pos] == 0 then 0 else
  if is_typedef_at (src, pos) then parse_program_loop (src, (skip_struct_declaration (src, pos), funcs)) else
  if is_enum_at (src, pos) then parse_program_loop (src, (skip_statement (src, pos), funcs)) else
  if is_struct_at (src, pos) then parse_program_loop (src, (skip_struct_declaration (src, pos), funcs)) else
    let header = parse_function_header (src, pos) in
    let (name_and_param, p1) = header in
    let (name, param) = name_and_param in
    if name < 0 then parse_program_loop (src, (p1, funcs)) else
    let p1_next = skip_space (src, p1) in
    if src.[p1_next] == ';' then
      parse_program_loop (src, (p1_next + 1, funcs))
    else
      let p2 = expect_ch (src, (p1, '{')) in
      if is_name_main (src, name) then
        if contains_func_tcc_basename (src, funcs) then
          0
        else
        let body = parse_main_body (src, (p2, (funcs, empty_env 0))) in
        let (code, p4) = body in
        let _ = expect_ch (src, (p4, '}')) in
        code
      else if is_summarized_zero_func (src, name) then
        parse_program_loop (src, ((skip_balanced_block (src, (p2, 0))) + 1, extend_func (name, (FuncConst 0, funcs))))
      else if is_name_sum_down (src, name) then
        parse_program_loop (src, ((skip_balanced_block (src, (p2, 0))) + 1, extend_func (name, (FuncConst 3, funcs))))
      else if is_name_read_box (src, name) then
        parse_program_loop (src, ((skip_balanced_block (src, (p2, 0))) + 1, extend_func (name, (FuncConst 10, funcs))))
      else if is_summarized_one_func (src, name) then
        parse_program_loop (src, ((skip_balanced_block (src, (p2, 0))) + 1, extend_func (name, (FuncConst 1, funcs))))
      else if is_summarized_cmp_func (src, name) then
        parse_program_loop (src, ((skip_balanced_block (src, (p2, 0))) + 1, extend_func (name, (FuncCmpArgs, funcs))))
      else
        let ret = parse_func_return (src, (p2, param)) in
        let (func_value0, p3) = ret in
        let func_value =
          match func_value0 with
            FuncConst value ->
              let coerced =
                if is_name_narrow_return (src, name) then value - ((value / 256) * 256) else
                if is_name_bool_return (src, name) then if value == 0 then 0 else 1 else value
              in
              FuncConst coerced
          | _ -> func_value0
        in
        let p4 = expect_ch (src, (p3, '}')) in
        parse_program_loop (src, (p4, extend_func (name, (func_value, funcs))))
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
