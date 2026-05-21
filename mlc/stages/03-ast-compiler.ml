type ty = TyInt | TyUnit | TyBool | TyMore of ty_more
type ty_more = TyString | TyBytes | TyPair of ty | TyCell of ty | TyArray of ty | TyMore2 of ty_more2
type ty_more2 = TyFun of ty | TyAdt of int
type expr = EInt of int | EVar of int | EBool of int | EMore of expr_more
type expr_more = EWriteByte of expr | EAdd of expr | ESub of expr | EMore2 of expr_more2
type expr_more2 = EMul of expr | EDiv of expr | EEq of expr | EMore3 of expr_more3
type expr_more3 = ENe of expr | ELt of expr | ELe of expr | EMore4 of expr_more4
type expr_more4 = EGt of expr | EGe of expr | EIf of expr | EMore5 of expr_more5
type expr_more5 = ELet of expr | EPair of expr | ELetPair of expr | EMore6 of expr_more6
type expr_more6 = ESeq of expr | EDebugByte of expr | EExit of expr | EReadByte | EMore7 of expr_more7
type expr_more7 = EString of int | EStringLength of expr | EBytesCreate of expr | EMore8 of expr_more8
type expr_more8 = EBytesLength of expr | EIndex of expr | ESetIndex of expr | EMore9 of expr_more9
type expr_more9 = EDebugInt of expr | EUnit | EMore10 of expr_more10
type expr_more10 = ECellCreate of expr | ECellGet of expr | ECellSet of expr | EArrayCreate of expr | ELetRec of expr | EMore11 of expr_more11
type expr_more11 = ECall of expr | EConstr of int | EConstrArg of expr | EMatch of expr | ERecord of expr | ERecord3 of expr | EField of expr
type match_cases = MatchCase of expr | MatchEnd
type parse_reply = ParseOk of int | ParseErr
type expr_option = ExprSome of expr | ExprNone
type pos_option = PosSome of int | PosNone
type value_reply = ValueOk of int | ValueErr
type value_option = ValueSome of int | ValueNone
type expr_reply = ExprOk of expr | ExprErr

let rec byte n =
  n - ((n / 256) * 256)
in
let rec emit_u32 n =
  let _ = write_byte (byte n) in
  let _ = write_byte (byte (n / 256)) in
  let _ = write_byte (byte (n / 65536)) in
  write_byte (byte (n / 16777216))
in
let rec emit_header len =
  let _ = write_byte 'M' in
  let _ = write_byte 'Z' in
  let _ = write_byte 'B' in
  let _ = write_byte 'C' in
  let _ = emit_u32 1 in
  let _ = emit_u32 len in
  let _ = emit_u32 5 in
  emit_u32 0
in
let rec emit_byte_if state =
  let (emit, value) = state in
  if emit == 1 then write_byte value else 0
in
let rec emit_u32_if state =
  let (emit, value) = state in
  if emit == 1 then emit_u32 value else 0
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
  let const_len = emit_const (emit, 0) in
  let _ = emit_byte_if (emit, 14) in
  let _ = emit_u32_if (emit, 1) in
  let _ = emit_u32_if (emit, 0) in
  const_len + 9
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
let rec emit_makeblock_pair emit =
  let _ = emit_byte_if (emit, 15) in
  let _ = emit_u32_if (emit, 0) in
  let _ = emit_u32_if (emit, 2) in
  9
in
let rec emit_makeblock state =
  let (emit, size) = state in
  let _ = emit_byte_if (emit, 15) in
  let _ = emit_u32_if (emit, 0) in
  let _ = emit_u32_if (emit, size) in
  9
in
let rec emit_makeblock_tag state =
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
let rec emit_getfield_dyn emit =
  let _ = emit_byte_if (emit, 25) in
  1
in
let rec emit_setfield_dyn emit =
  let _ = emit_byte_if (emit, 26) in
  1
in
let rec emit_setfield state =
  let (emit, index) = state in
  let _ = emit_byte_if (emit, 17) in
  let _ = emit_u32_if (emit, index) in
  5
in
let rec emit_gettag emit =
  let _ = emit_byte_if (emit, 18) in
  1
in
let rec emit_blocksize emit =
  let _ = emit_byte_if (emit, 27) in
  1
in
let rec emit_makeblock_dyn emit =
  let _ = emit_byte_if (emit, 28) in
  let _ = emit_u32_if (emit, 0) in
  5
in
let rec is_space ch =
  if ch == ' ' then 1 else
  if ch == '\t' then 1 else
  if ch == '\n' then 1 else
  if ch == 13 then 1 else 0
in
let rec is_digit ch =
  if ch < '0' then 0 else if ch > '9' then 0 else 1
in
let rec is_alpha ch =
  if ch == '_' then 1 else
  if ch < 'A' then 0 else
  if ch <= 'Z' then 1 else
  if ch < 'a' then 0 else
  if ch <= 'z' then 1 else 0
in
let rec is_upper ch =
  if ch < 'A' then 0 else if ch <= 'Z' then 1 else 0
in
let rec is_ident ch =
  if is_alpha ch then 1 else is_digit ch
in
let rec skip_space state =
  let (src, pos) = state in
  if is_space (src.[pos]) then skip_space (src, pos + 1) else pos
in
let rec fail unit =
  exit 1
in
let rec p_force reply =
  match reply with
    ParseOk pos -> pos
  | ParseErr -> fail 0
in
let rec p_force_value reply =
  match reply with
    ValueOk parsed -> parsed
  | ValueErr -> fail 0
in
let rec p_optional_value reply =
  match reply with
    ValueOk parsed -> ValueSome parsed
  | ValueErr -> ValueNone
in
let rec p_force_expr reply =
  match reply with
    ExprOk parsed -> parsed
  | ExprErr -> fail 0
in
let rec p_return state =
  let (pos, value) = state in
  (value, pos)
in
let rec p_peek state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  (src.[pos], pos)
in
let rec p_try_char state =
  let (src, pair) = state in
  let (pos0, want) = pair in
  let peeked = p_peek (src, pos0) in
  let (got, pos) = peeked in
  if got == want then ParseOk (pos + 1) else ParseErr
in
let rec p_need_char state =
  p_force (p_try_char state)
in
let rec need_char state =
  p_need_char state
in
let rec p_try_string_loop state =
  let (src, pair) = state in
  let (pos, pair2) = pair in
  let (text, index) = pair2 in
  if index == String.length text then ParseOk (pos + index) else
  if src.[pos + index] == text.[index] then p_try_string_loop (src, (pos, (text, index + 1))) else ParseErr
in
let rec p_try_string state =
  let (src, pair) = state in
  let (pos0, text) = pair in
  let pos = skip_space (src, pos0) in
  p_try_string_loop (src, (pos, (text, 0)))
in
let rec p_string_at state =
  match p_try_string state with
    ParseOk pos -> let _ = pos in 1
  | ParseErr -> 0
in
let rec p_keyword_at state =
  let (src, pair) = state in
  let (pos0, text) = pair in
  let pos = skip_space (src, pos0) in
  let reply = p_try_string_loop (src, (pos, (text, 0))) in
  match reply with
    ParseOk end_pos -> 1 - (is_ident (src.[end_pos]))
  | ParseErr -> 0
in
let rec p_need_string state =
  p_force (p_try_string state)
in
let rec p_try_keyword state =
  let (src, pair) = state in
  let (pos0, text) = pair in
  let pos = skip_space (src, pos0) in
  if p_keyword_at (src, (pos, text)) == 1 then ParseOk (pos + String.length text) else ParseErr
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
let rec p_need_keyword state =
  p_force (p_try_keyword state)
in
let rec is_if_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "if"))
in
let rec is_then_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "then"))
in
let rec is_else_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "else"))
in
let rec is_let_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "let"))
in
let rec is_in_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "in"))
in
let rec is_write_byte_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "write_byte"))
in
let rec is_write_string_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "write_string"))
in
let rec is_debug_byte_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "debug_byte"))
in
let rec is_debug_string_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "debug_string"))
in
let rec is_debug_printf_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "debug_printf"))
in
let rec is_debug_int_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "debug_int"))
in
let rec is_read_byte_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "read_byte"))
in
let rec is_exit_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "exit"))
in
let rec is_string_length_at state =
  let (src, pos0) = state in
  p_string_at (src, (pos0, "String.length"))
in
let rec is_bytes_create_at state =
  let (src, pos0) = state in
  p_string_at (src, (pos0, "Bytes.create"))
in
let rec is_array_create_at state =
  let (src, pos0) = state in
  p_string_at (src, (pos0, "Array.create"))
in
let rec is_bytes_length_at state =
  let (src, pos0) = state in
  p_string_at (src, (pos0, "Bytes.length"))
in
let rec is_cell_create_at state =
  let (src, pos0) = state in
  p_string_at (src, (pos0, "Cell.create"))
in
let rec is_cell_get_at state =
  let (src, pos0) = state in
  p_string_at (src, (pos0, "Cell.get"))
in
let rec is_cell_set_at state =
  let (src, pos0) = state in
  p_string_at (src, (pos0, "Cell.set"))
in
let rec is_true_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "true"))
in
let rec is_false_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "false"))
in
let rec is_type_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "type"))
in
let rec is_match_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "match"))
in
let rec is_with_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "with"))
in
let rec is_of_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "of"))
in
let rec is_rec_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "rec"))
in
let rec is_and_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "and"))
in
let rec is_reserved_expr_at state =
  let (src, pos0) = state in
  if is_if_at (src, pos0) then 1 else
  if is_let_at (src, pos0) then 1 else
  if is_rec_at (src, pos0) then 1 else
  if is_and_at (src, pos0) then 1 else
  if is_in_at (src, pos0) then 1 else
  if is_then_at (src, pos0) then 1 else
  if is_else_at (src, pos0) then 1 else
  if is_true_at (src, pos0) then 1 else
  if is_false_at (src, pos0) then 1 else
  if is_type_at (src, pos0) then 1 else
  if is_match_at (src, pos0) then 1 else
  if is_with_at (src, pos0) then 1 else
  if is_write_byte_at (src, pos0) then 1 else
  if is_write_string_at (src, pos0) then 1 else
  if is_debug_byte_at (src, pos0) then 1 else
  if is_debug_string_at (src, pos0) then 1 else
  if is_debug_printf_at (src, pos0) then 1 else
  if is_debug_int_at (src, pos0) then 1 else
  if is_exit_at (src, pos0) then 1 else
  if is_read_byte_at (src, pos0) then 1 else
  if is_string_length_at (src, pos0) then 1 else
  if is_bytes_create_at (src, pos0) then 1 else
  if is_array_create_at (src, pos0) then 1 else
  if is_bytes_length_at (src, pos0) then 1 else
  if is_cell_create_at (src, pos0) then 1 else
  if is_cell_get_at (src, pos0) then 1 else
  if is_cell_set_at (src, pos0) then 1 else 0
in
let rec skip_line state =
  let (src, pos) = state in
  if src.[pos] == 0 then pos else
  if src.[pos] == '\n' then pos + 1 else skip_line (src, pos + 1)
in
let rec skip_inline_space state =
  let (src, pos) = state in
  if src.[pos] == ' ' then skip_inline_space (src, pos + 1) else
  if src.[pos] == '\t' then skip_inline_space (src, pos + 1) else pos
in
let rec skip_type_decls state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if is_type_at (src, pos) then skip_type_decls (src, skip_line (src, pos)) else pos
in
let rec need_of state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "of"))
in
let rec need_with state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "with"))
in
let rec need_arrow state =
  let (src, pos0) = state in
  p_need_string (src, (pos0, "->"))
in
let rec need_then state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "then"))
in
let rec need_else state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "else"))
in
let rec need_in state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "in"))
in
let rec need_write_byte state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "write_byte"))
in
let rec need_write_string state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "write_string"))
in
let rec need_debug_byte state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "debug_byte"))
in
let rec need_debug_string state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "debug_string"))
in
let rec need_debug_printf state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "debug_printf"))
in
let rec need_debug_int state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "debug_int"))
in
let rec need_read_byte state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "read_byte"))
in
let rec need_exit state =
  let (src, pos0) = state in
  p_need_keyword (src, (pos0, "exit"))
in
let rec need_string_length state =
  let (src, pos0) = state in
  p_need_string (src, (pos0, "String.length"))
in
let rec need_bytes_create state =
  let (src, pos0) = state in
  p_need_string (src, (pos0, "Bytes.create"))
in
let rec need_array_create state =
  let (src, pos0) = state in
  p_need_string (src, (pos0, "Array.create"))
in
let rec need_bytes_length state =
  let (src, pos0) = state in
  p_need_string (src, (pos0, "Bytes.length"))
in
let rec need_cell_create state =
  let (src, pos0) = state in
  p_need_string (src, (pos0, "Cell.create"))
in
let rec need_cell_get state =
  let (src, pos0) = state in
  p_need_string (src, (pos0, "Cell.get"))
in
let rec need_cell_set state =
  let (src, pos0) = state in
  p_need_string (src, (pos0, "Cell.set"))
in
let rec parse_number_loop state =
  let (src, pair) = state in
  let (pos, acc) = pair in
  let ch = src.[pos] in
  if is_digit ch then parse_number_loop (src, (pos + 1, (acc * 10) + ch - '0')) else (EInt acc, pos)
in
let rec p_try_number state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let ch = src.[pos] in
  if is_digit ch then ExprOk (parse_number_loop (src, (pos + 1, ch - '0'))) else ExprErr
in
let rec parse_number state =
  p_force_expr (p_try_number state)
in
let rec parse_ident_loop state =
  let (src, pair) = state in
  let (start, pos) = pair in
  let ch = src.[pos] in
  if is_ident ch then parse_ident_loop (src, (start, pos + 1)) else (start, pos)
in
let rec ident_eq_loop state =
  let (src, pair) = state in
  let (left, right) = pair in
  if is_ident (src.[left]) == 0 then
    if is_ident (src.[right]) == 1 then 0 else 1
  else
  if is_ident (src.[right]) == 0 then 0 else
  if src.[left] == src.[right] then ident_eq_loop (src, (left + 1, right + 1)) else 0
in
let rec ident_eq state =
  let (src, pair) = state in
  let (left, right) = pair in
  ident_eq_loop (src, (left, right))
in
let rec is_wild_name state =
  let (src, name) = state in
  if src.[name] == '_' then 1 - (is_ident (src.[name + 1])) else 0
in
let rec p_try_ident state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let ch = src.[pos] in
  if is_alpha ch then ValueOk (parse_ident_loop (src, (pos, pos + 1))) else ValueErr
in
let rec parse_ident state =
  p_force_value (p_try_ident state)
in
let rec parse_match_bind state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if (src.[pos] == '-') * (src.[pos + 1] == '>') then (0, (0 - 1, (0 - 1, pos))) else
  if src.[pos] == '(' then
    let first_pos = skip_space (src, pos + 1) in
    if src.[first_pos] == '(' then
      let name1 = parse_ident (src, first_pos + 1) in
      let (name1_pos, name1_end) = name1 in
      let comma1 = need_char (src, (name1_end, ',')) in
      let name2 = parse_ident (src, comma1) in
      let (name2_pos, name2_end) = name2 in
      let close_pair = need_char (src, (name2_end, ')')) in
      let comma2 = need_char (src, (close_pair, ',')) in
      let name3 = parse_ident (src, comma2) in
      let (name3_pos, name3_end) = name3 in
      let done_pos = need_char (src, (name3_end, ')')) in
      (3, (name1_pos, ((name2_pos, name3_pos), done_pos)))
    else
      let name1 = parse_ident (src, first_pos) in
      let (name1_pos, name1_end) = name1 in
      let comma = need_char (src, (name1_end, ',')) in
      let second_pos = skip_space (src, comma) in
      if src.[second_pos] == '(' then
        let name2 = parse_ident (src, second_pos + 1) in
        let (name2_pos, name2_end) = name2 in
        let comma2 = need_char (src, (name2_end, ',')) in
        let name3 = parse_ident (src, comma2) in
        let (name3_pos, name3_end) = name3 in
        let close_pair = need_char (src, (name3_end, ')')) in
        let done_pos = need_char (src, (close_pair, ')')) in
        (4, (name1_pos, ((name2_pos, name3_pos), done_pos)))
      else
        let name2 = parse_ident (src, second_pos) in
        let (name2_pos, name2_end) = name2 in
        let done_pos = need_char (src, (name2_end, ')')) in
        (2, (name1_pos, (name2_pos, done_pos)))
  else
    let name = parse_ident (src, pos) in
    let (name_pos, done_pos) = name in
    (1, (name_pos, (0 - 1, done_pos)))
in
let rec unit_expr dummy =
  let _ = dummy in
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EMore8 (EMore9 EUnit))))))))
in
let rec write_byte_expr ch =
  EMore (EWriteByte (EInt ch))
in
let rec debug_byte_expr ch =
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EDebugByte (EInt ch)))))))
in
let rec debug_int_expr expr =
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EMore8 (EMore9 (EDebugInt expr)))))))))
in
let rec string_expr pos =
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EString pos)))))))
in
let rec string_length_expr expr =
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EStringLength expr)))))))
in
let rec bytes_create_expr expr =
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EBytesCreate expr)))))))
in
let rec bytes_length_expr expr =
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EMore8 (EBytesLength expr))))))))
in
let rec index_expr state =
  let (base, index) = state in
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EMore8 (EIndex (base, index)))))))))
in
let rec set_index_expr state =
  let (base, rest) = state in
  let (index, value) = rest in
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EMore8 (ESetIndex (base, (index, value))))))))))
in
let rec cell_create_expr expr =
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EMore8 (EMore9 (EMore10 (ECellCreate expr))))))))))
in
let rec cell_get_expr expr =
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EMore8 (EMore9 (EMore10 (ECellGet expr))))))))))
in
let rec cell_set_expr state =
  let (cell, value) = state in
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EMore8 (EMore9 (EMore10 (ECellSet (cell, value)))))))))))
in
let rec array_create_expr state =
  let (size, init) = state in
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EMore8 (EMore9 (EMore10 (EArrayCreate (size, init)))))))))))
in
let rec more10_expr expr =
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EMore7 (EMore8 (EMore9 (EMore10 expr)))))))))
in
let rec constr_expr name =
  more10_expr (EMore11 (EConstr name))
in
let rec constr_arg_expr state =
  let (name, arg) = state in
  more10_expr (EMore11 (EConstrArg (name, arg)))
in
let rec match_expr state =
  more10_expr (EMore11 (EMatch state))
in
let rec record_expr state =
  more10_expr (EMore11 (ERecord state))
in
let rec record3_expr state =
  more10_expr (EMore11 (ERecord3 state))
in
let rec field_expr state =
  more10_expr (EMore11 (EField state))
in
let rec match_case_expr state =
  let (case_name, rest1) = state in
  let (case_bind_kind, rest2) = rest1 in
  let (case_bind_name, rest3) = rest2 in
  let (case_bind_name2, rest4) = rest3 in
  let (case_body, case_tail) = rest4 in
  MatchCase (case_name, (case_bind_kind, (case_bind_name, (case_bind_name2, (case_body, case_tail)))))
in
let rec let_rec_expr state =
  more10_expr (ELetRec (1, state))
in
let rec let_rec2_expr state =
  more10_expr (ELetRec (2, state))
in
let rec let_rec3_expr state =
  more10_expr (ELetRec (3, state))
in
let rec call_expr state =
  let (name, arg) = state in
  more10_expr (EMore11 (ECall (name, arg)))
in
let rec read_byte_expr unit =
  let _ = unit in
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 EReadByte)))))
in
let rec exit_expr expr =
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EExit expr))))))
in
let rec seq_expr state =
  let (left, right) = state in
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (ESeq (left, right)))))))
in
let rec let_expr state =
  let (name, pair) = state in
  let (rhs, body) = pair in
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (ELet (name, (rhs, body)))))))
in
let rec let_pair_expr state =
  let (name1, rest1) = state in
  let (name2, rest2) = rest1 in
  let (rhs, body) = rest2 in
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (ELetPair (name1, (name2, (rhs, body))))))))
in
let rec parse_string_escape state =
  let (src, pos) = state in
  let ch = src.[pos] in
  if ch == 'n' then ('\n', pos + 1) else
  if ch == 't' then ('\t', pos + 1) else
    (ch, pos + 1)
in
let rec parse_string_char state =
  let (src, pos) = state in
  let ch = src.[pos] in
  if ch == '\\' then parse_string_escape (src, pos + 1) else (ch, pos + 1)
in
let rec parse_char_literal state =
  let (src, pos0) = state in
  let pos = pos0 + 1 in
  let parsed = parse_string_char (src, pos) in
  let (ch, next_pos) = parsed in
  p_return (p_need_char (src, (next_pos, '\'')), EInt ch)
in
let rec parse_string_length_loop state =
  let (src, pair) = state in
  let (pos, count) = pair in
  if src.[pos] == '"' then (count, pos + 1) else
    let parsed = parse_string_char (src, pos) in
    let (ch, next_pos) = parsed in
    let _ = ch in
    parse_string_length_loop (src, (next_pos, count + 1))
in
let rec parse_string_length_literal state =
  let (src, pos0) = state in
  let arg_pos = skip_space (src, need_string_length (src, pos0)) in
  if src.[arg_pos] == '"' then
    let parsed = parse_string_length_loop (src, (arg_pos + 1, 0)) in
    let (len, done_pos) = parsed in
    (EInt len, done_pos)
  else
    fail 0
in
let rec parse_string_literal state =
  let (src, pos0) = state in
  let parsed = parse_string_length_loop (src, (pos0 + 1, 0)) in
  let (len, done_pos) = parsed in
  let _ = len in
  (string_expr pos0, done_pos)
in
let rec parse_write_string_loop state =
  let (src, pair) = state in
  let (pos, pair2) = pair in
  let (has_expr, acc) = pair2 in
  if src.[pos] == '"' then
    if has_expr == 1 then (acc, pos + 1) else (unit_expr 0, pos + 1)
  else
    let parsed = parse_string_char (src, pos) in
    let (ch, next_pos) = parsed in
    let byte_ast = write_byte_expr ch in
    if has_expr == 1 then parse_write_string_loop (src, (next_pos, (1, seq_expr (acc, byte_ast)))) else
      parse_write_string_loop (src, (next_pos, (1, byte_ast)))
in
let rec parse_write_string state =
  let (src, pos0) = state in
  let str_pos0 = need_write_string (src, pos0) in
  let str_pos = skip_space (src, str_pos0) in
  if src.[str_pos] == '"' then parse_write_string_loop (src, (str_pos + 1, (0, unit_expr 0))) else fail 0
in
let rec parse_debug_string_loop state =
  let (src, pair) = state in
  let (pos, pair2) = pair in
  let (has_expr, acc) = pair2 in
  if src.[pos] == '"' then
    if has_expr == 1 then (acc, pos + 1) else (unit_expr 0, pos + 1)
  else
    let parsed = parse_string_char (src, pos) in
    let (ch, next_pos) = parsed in
    let byte_ast = debug_byte_expr ch in
    if has_expr == 1 then parse_debug_string_loop (src, (next_pos, (1, seq_expr (acc, byte_ast)))) else
      parse_debug_string_loop (src, (next_pos, (1, byte_ast)))
in
let rec parse_debug_string state =
  let (src, pos0) = state in
  let str_pos0 = need_debug_string (src, pos0) in
  let str_pos = skip_space (src, str_pos0) in
  if src.[str_pos] == '"' then parse_debug_string_loop (src, (str_pos + 1, (0, unit_expr 0))) else fail 0
in
let rec parse_debug_printf_prefix_loop state =
  let (src, pair) = state in
  let (pos, pair2) = pair in
  let (has_expr, acc) = pair2 in
  if src.[pos] == '"' then fail 0 else
  if (src.[pos] == '%') * (src.[pos + 1] == 'd') then
    if has_expr == 1 then (acc, pos + 2) else (unit_expr 0, pos + 2)
  else
    let parsed = parse_string_char (src, pos) in
    let (ch, next_pos) = parsed in
    let byte_ast = debug_byte_expr ch in
    if has_expr == 1 then parse_debug_printf_prefix_loop (src, (next_pos, (1, seq_expr (acc, byte_ast)))) else
      parse_debug_printf_prefix_loop (src, (next_pos, (1, byte_ast)))
in
let rec parse_debug_printf_suffix_loop state =
  let (src, pair) = state in
  let (pos, pair2) = pair in
  let (has_expr, acc) = pair2 in
  if src.[pos] == '"' then
    if has_expr == 1 then (acc, pos + 1) else (unit_expr 0, pos + 1)
  else
    let parsed = parse_string_char (src, pos) in
    let (ch, next_pos) = parsed in
    let byte_ast = debug_byte_expr ch in
    if has_expr == 1 then parse_debug_printf_suffix_loop (src, (next_pos, (1, seq_expr (acc, byte_ast)))) else
      parse_debug_printf_suffix_loop (src, (next_pos, (1, byte_ast)))
in
let rec parse_debug_printf_format state =
  let (src, pos0) = state in
  let str_pos0 = need_debug_printf (src, pos0) in
  let str_pos = skip_space (src, str_pos0) in
  if src.[str_pos] == '"' then
    let prefix = parse_debug_printf_prefix_loop (src, (str_pos + 1, (0, unit_expr 0))) in
    let (prefix_ast, suffix_pos) = prefix in
    let suffix = parse_debug_printf_suffix_loop (src, (suffix_pos, (0, unit_expr 0))) in
    let (suffix_ast, expr_pos) = suffix in
    (prefix_ast, (suffix_ast, expr_pos))
  else
    fail 0
in
let rec add_expr state =
  let (left, right) = state in
  EMore (EAdd (left, right))
in
let rec sub_expr state =
  let (left, right) = state in
  EMore (ESub (left, right))
in
let rec mul_expr state =
  let (left, right) = state in
  EMore (EMore2 (EMul (left, right)))
in
let rec div_expr state =
  let (left, right) = state in
  EMore (EMore2 (EDiv (left, right)))
in
let rec parse_value_arg state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let ch = src.[pos] in
  if ch == '"' then
    parse_string_literal (src, pos)
  else if ch == '\'' then
    parse_char_literal (src, pos)
  else if is_digit ch then
    parse_number (src, pos)
  else
    match p_optional_value (p_try_ident (src, pos)) with
      ValueSome ident ->
        let (name, name_end) = ident in
        (EVar name, name_end)
    | ValueNone -> fail 0
in
let rec starts_call_arg state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let ch = src.[pos] in
  if ch == '(' then 1 else
  if ch == '"' then 1 else
  if ch == '\'' then 1 else
  if is_digit ch then 1 else
  if is_alpha ch then
    if is_reserved_expr_at (src, pos) == 1 then 0 else 1
  else 0
in
let rec parse_index_binop state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if src.[pos] == '+' then (1, (pos + 1, 1)) else
  if src.[pos] == '-' then (2, (pos + 1, 1)) else
  if src.[pos] == '*' then (3, (pos + 1, 2)) else
  if src.[pos] == '/' then (4, (pos + 1, 2)) else
    (0, (pos, 0))
in
let rec make_index_binop state =
  let (op, pair) = state in
  let (left, right) = pair in
  if op == 1 then add_expr (left, right) else
  if op == 2 then sub_expr (left, right) else
  if op == 3 then mul_expr (left, right) else
  if op == 4 then div_expr (left, right) else fail 0
in
let rec parse_index_expr_prec state =
  let (src, pair0) = state in
  let (pos0, pair1) = pair0 in
  let (min_prec, pair2) = pair1 in
  let (has_left, left_ast0) = pair2 in
  if has_left == 0 then
    let left = parse_value_arg (src, pos0) in
    let (left_ast, left_end) = left in
    parse_index_expr_prec (src, (left_end, (min_prec, (1, left_ast))))
  else
    let parsed_op = parse_index_binop (src, pos0) in
    let (op, op_rest) = parsed_op in
    let (op_end, prec) = op_rest in
    if op == 0 then
      (left_ast0, pos0)
    else if prec < min_prec then
      (left_ast0, pos0)
    else
      let right = parse_index_expr_prec (src, (op_end, (prec + 1, (0, EInt 0)))) in
      let (right_ast, right_end) = right in
      let next_left = make_index_binop (op, (left_ast0, right_ast)) in
      parse_index_expr_prec (src, (right_end, (min_prec, (1, next_left))))
in
let rec parse_index_expr state =
  let (src, pos0) = state in
  parse_index_expr_prec (src, (pos0, (0, (0, EInt 0))))
in
let rec parse_call_arg state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if src.[pos] == '(' then
    let inner_pos = skip_space (src, pos + 1) in
    let inner =
      if src.[inner_pos] == '(' then parse_call_arg (src, inner_pos) else
      if is_upper (src.[inner_pos]) == 1 then
        let ctor = parse_ident (src, inner_pos) in
        let (name, name_end) = ctor in
        if starts_call_arg (src, name_end) == 1 then
          let arg = parse_call_arg (src, name_end) in
          let (arg_ast, arg_end) = arg in
          (constr_arg_expr (name, arg_ast), arg_end)
        else
          (constr_expr name, name_end)
      else
        parse_index_expr (src, inner_pos)
    in
    let (inner_ast, inner_end) = inner in
    let after_first = skip_space (src, inner_end) in
    if src.[after_first] == ',' then
      let right_pos = skip_space (src, after_first + 1) in
      let right =
        if src.[right_pos] == '(' then parse_call_arg (src, right_pos) else
        if is_upper (src.[right_pos]) == 1 then
          let ctor = parse_ident (src, right_pos) in
          let (name, name_end) = ctor in
          if starts_call_arg (src, name_end) == 1 then
            let arg = parse_call_arg (src, name_end) in
            let (arg_ast, arg_end) = arg in
            (constr_arg_expr (name, arg_ast), arg_end)
          else
            (constr_expr name, name_end)
        else
          parse_index_expr (src, right_pos)
      in
      let (right_ast, right_end) = right in
      (EMore (EMore2 (EMore3 (EMore4 (EMore5 (EPair (inner_ast, right_ast)))))), p_need_char (src, (right_end, ')')))
    else
      (inner_ast, p_need_char (src, (inner_end, ')')))
  else
    parse_value_arg (src, pos)
in
let rec parse_string_length_expr state =
  let (src, pos0) = state in
  let arg_pos = need_string_length (src, pos0) in
  let parsed_arg = parse_value_arg (src, arg_pos) in
  let (arg_ast, done_pos) = parsed_arg in
  (string_length_expr arg_ast, done_pos)
in
let rec parse_bytes_create_expr state =
  let (src, pos0) = state in
  let arg_pos = need_bytes_create (src, pos0) in
  let parsed_arg = parse_index_expr (src, arg_pos) in
  let (arg_ast, done_pos) = parsed_arg in
  (bytes_create_expr arg_ast, done_pos)
in
let rec parse_array_create_expr state =
  let (src, pos0) = state in
  let size_pos = need_array_create (src, pos0) in
  let parsed_size = parse_index_expr (src, size_pos) in
  let (size_ast, init_pos) = parsed_size in
  let parsed_init = parse_index_expr (src, init_pos) in
  let (init_ast, done_pos) = parsed_init in
  (array_create_expr (size_ast, init_ast), done_pos)
in
let rec parse_bytes_length_expr state =
  let (src, pos0) = state in
  let arg_pos = need_bytes_length (src, pos0) in
  let parsed_arg = parse_value_arg (src, arg_pos) in
  let (arg_ast, done_pos) = parsed_arg in
  (bytes_length_expr arg_ast, done_pos)
in
let rec parse_cell_create_expr state =
  let (src, pos0) = state in
  let arg_pos = need_cell_create (src, pos0) in
  let parsed_arg = parse_index_expr (src, arg_pos) in
  let (arg_ast, done_pos) = parsed_arg in
  (cell_create_expr arg_ast, done_pos)
in
let rec parse_cell_get_expr state =
  let (src, pos0) = state in
  let arg_pos = need_cell_get (src, pos0) in
  let parsed_arg = parse_value_arg (src, arg_pos) in
  let (arg_ast, done_pos) = parsed_arg in
  (cell_get_expr arg_ast, done_pos)
in
let rec parse_cell_set_expr state =
  let (src, pos0) = state in
  let cell_pos = need_cell_set (src, pos0) in
  let parsed_cell = parse_value_arg (src, cell_pos) in
  let (cell_ast, value_pos) = parsed_cell in
  let parsed_value = parse_index_expr (src, value_pos) in
  let (value_ast, done_pos) = parsed_value in
  (cell_set_expr (cell_ast, value_ast), done_pos)
in
let rec parse_index_suffix state =
  let (src, pair) = state in
  let (base, pos0) = pair in
  let pos = skip_space (src, pos0) in
  if src.[pos] == '.' then
    let open_ch = src.[pos + 1] in
    if (open_ch == '[') + (open_ch == '(') then
      let close_ch = if open_ch == '[' then ']' else ')' in
      let index = parse_index_expr (src, pos + 2) in
      let (index_ast, index_end) = index in
      let close = p_need_char (src, (index_end, close_ch)) in
      let after_close = skip_space (src, close) in
      if src.[after_close] == '<' then
        if src.[after_close + 1] == '-' then
          let value = parse_index_expr (src, after_close + 2) in
          let (value_ast, value_end) = value in
          (set_index_expr (base, (index_ast, value_ast)), value_end)
        else
          fail 0
      else
        (index_expr (base, index_ast), close)
    else
      let field = parse_ident (src, pos + 1) in
      let (field_name, field_end) = field in
      (field_expr (base, field_name), field_end)
  else
    (base, pos0)
in
let rec parse_binop state =
  let (src, pair) = state in
  let (pos0, allow_seq) = pair in
  let pos = skip_space (src, pos0) in
  if (src.[pos] == ';') * allow_seq then (1, (pos + 1, 0)) else
  if src.[pos] == '=' then
    if src.[pos + 1] == '=' then (2, (pos + 2, 1)) else (2, (pos + 1, 1))
  else
  if (src.[pos] == '!') * (src.[pos + 1] == '=') then (3, (pos + 2, 1)) else
  if src.[pos] == '<' then
    if src.[pos + 1] == '=' then (5, (pos + 2, 1)) else (4, (pos + 1, 1))
  else if src.[pos] == '>' then
    if src.[pos + 1] == '=' then (7, (pos + 2, 1)) else (6, (pos + 1, 1))
  else if src.[pos] == '+' then (8, (pos + 1, 2)) else
  if src.[pos] == '-' then (9, (pos + 1, 2)) else
  if src.[pos] == '*' then (10, (pos + 1, 3)) else
  if src.[pos] == '/' then (11, (pos + 1, 3)) else
    (0, (pos, 0))
in
let rec make_binop state =
  let (op, pair) = state in
  let (left, right) = pair in
  if op == 1 then EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (ESeq (left, right))))))) else
  if op == 2 then EMore (EMore2 (EEq (left, right))) else
  if op == 3 then EMore (EMore2 (EMore3 (ENe (left, right)))) else
  if op == 4 then EMore (EMore2 (EMore3 (ELt (left, right)))) else
  if op == 5 then EMore (EMore2 (EMore3 (ELe (left, right)))) else
  if op == 6 then EMore (EMore2 (EMore3 (EMore4 (EGt (left, right))))) else
  if op == 7 then EMore (EMore2 (EMore3 (EMore4 (EGe (left, right))))) else
  if op == 8 then add_expr (left, right) else
  if op == 9 then sub_expr (left, right) else
  if op == 10 then mul_expr (left, right) else
  if op == 11 then div_expr (left, right) else fail 0
in
let rec parse_expr_prec state =
  let (src, pair0) = state in
  let (pos0, pair1) = pair0 in
  let (allow_seq, pair2) = pair1 in
  let (min_prec, pair3) = pair2 in
  let (has_left, left_ast0) = pair3 in
  if has_left == 0 then
    let pos = skip_space (src, pos0) in
    let left =
      if is_if_at (src, pos) then
        let cond = parse_expr_prec (src, (pos + 2, (1, (0, (0, EInt 0))))) in
        let (cond_ast, cond_end) = cond in
        let then_pos = need_then (src, cond_end) in
        let yes = parse_expr_prec (src, (then_pos, (1, (0, (0, EInt 0))))) in
        let (yes_ast, yes_end) = yes in
        let else_pos = need_else (src, yes_end) in
        let no = parse_expr_prec (src, (else_pos, (1, (0, (0, EInt 0))))) in
        let (no_ast, no_end) = no in
        (EMore (EMore2 (EMore3 (EMore4 (EIf (cond_ast, (yes_ast, no_ast)))))), no_end)
      else if is_let_at (src, pos) then
        let bind_pos = skip_space (src, pos + 3) in
        if src.[bind_pos] == '(' then
          let name1 = parse_ident (src, bind_pos + 1) in
          let (name1_pos, name1_end0) = name1 in
          let comma = need_char (src, (name1_end0, ',')) in
          let name2 = parse_ident (src, comma) in
          let (name2_pos, name2_end0) = name2 in
          let after_names = need_char (src, (name2_end0, ')')) in
          let eq_pos = need_char (src, (after_names, '=')) in
          let rhs = parse_expr_prec (src, (eq_pos, (1, (0, (0, EInt 0))))) in
          let (rhs_ast, rhs_end) = rhs in
          let body_pos = need_in (src, rhs_end) in
          let body = parse_expr_prec (src, (body_pos, (1, (0, (0, EInt 0))))) in
          let (body_ast, body_end) = body in
          (EMore (EMore2 (EMore3 (EMore4 (EMore5 (ELetPair (name1_pos, (name2_pos, (rhs_ast, body_ast)))))))), body_end)
        else
          let ident = parse_ident (src, bind_pos) in
          let (name, name_end) = ident in
          let eq_pos = need_char (src, (name_end, '=')) in
          let rhs = parse_expr_prec (src, (eq_pos, (1, (0, (0, EInt 0))))) in
          let (rhs_ast, rhs_end) = rhs in
          let body_pos = need_in (src, rhs_end) in
          let body = parse_expr_prec (src, (body_pos, (1, (0, (0, EInt 0))))) in
          let (body_ast, body_end) = body in
          (EMore (EMore2 (EMore3 (EMore4 (EMore5 (ELet (name, (rhs_ast, body_ast))))))), body_end)
      else if is_write_byte_at (src, pos) then
        let expr_pos = need_write_byte (src, pos) in
        let expr = parse_expr_prec (src, (expr_pos, (0, (0, (0, EInt 0))))) in
        let (expr_ast, expr_end) = expr in
        (EMore (EWriteByte expr_ast), expr_end)
      else if is_write_string_at (src, pos) then
        parse_write_string (src, pos)
      else if is_debug_byte_at (src, pos) then
        let expr_pos = need_debug_byte (src, pos) in
        let expr = parse_expr_prec (src, (expr_pos, (0, (0, (0, EInt 0))))) in
        let (expr_ast, expr_end) = expr in
        (EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 (EDebugByte expr_ast)))))), expr_end)
      else if is_debug_int_at (src, pos) then
        let expr_pos = need_debug_int (src, pos) in
        let expr = parse_expr_prec (src, (expr_pos, (0, (0, (0, EInt 0))))) in
        let (expr_ast, expr_end) = expr in
        (debug_int_expr expr_ast, expr_end)
      else if is_debug_printf_at (src, pos) then
        let fmt = parse_debug_printf_format (src, pos) in
        let (prefix_ast, rest) = fmt in
        let (suffix_ast, expr_pos) = rest in
        let expr = parse_expr_prec (src, (expr_pos, (0, (0, (0, EInt 0))))) in
        let (expr_ast, expr_end) = expr in
        (seq_expr (prefix_ast, seq_expr (debug_int_expr expr_ast, suffix_ast)), expr_end)
      else if is_debug_string_at (src, pos) then
        parse_debug_string (src, pos)
      else if is_string_length_at (src, pos) then
        parse_string_length_expr (src, pos)
      else if is_bytes_create_at (src, pos) then
        parse_bytes_create_expr (src, pos)
      else if is_array_create_at (src, pos) then
        parse_array_create_expr (src, pos)
      else if is_bytes_length_at (src, pos) then
        parse_bytes_length_expr (src, pos)
      else if is_cell_create_at (src, pos) then
        parse_cell_create_expr (src, pos)
      else if is_cell_get_at (src, pos) then
        parse_cell_get_expr (src, pos)
      else if is_cell_set_at (src, pos) then
        parse_cell_set_expr (src, pos)
      else if is_read_byte_at (src, pos) then
        p_return (need_read_byte (src, pos), read_byte_expr 0)
      else if is_exit_at (src, pos) then
        let expr_pos = need_exit (src, pos) in
        let expr = parse_expr_prec (src, (expr_pos, (0, (0, (0, EInt 0))))) in
        let (expr_ast, expr_end) = expr in
        (exit_expr expr_ast, expr_end)
      else if is_match_at (src, pos) then
        let scrutinee = parse_expr_prec (src, (pos + 5, (0, (0, (0, EInt 0))))) in
        let (scrutinee_ast, scrutinee_end) = scrutinee in
        let cases_pos = p_need_char (src, (need_with (src, scrutinee_end), '|')) in
        let parsed_cases = parse_match_cases (src, cases_pos) in
        let (cases_ast, cases_end) = parsed_cases in
        (match_expr (scrutinee_ast, cases_ast), cases_end)
      else
        let peeked = p_peek (src, pos) in
        let (ch, atom_pos) = peeked in
        if ch == '-' then
          let rhs = parse_expr_prec (src, (atom_pos + 1, (allow_seq, (4, (0, EInt 0))))) in
          let (rhs_ast, rhs_end) = rhs in
          (EMore (ESub (EInt 0, rhs_ast)), rhs_end)
        else if ch == '!' then
          let rhs = parse_expr_prec (src, (atom_pos + 1, (allow_seq, (4, (0, EInt 0))))) in
          let (rhs_ast, rhs_end) = rhs in
          (EMore (EMore2 (EEq (rhs_ast, EBool 0))), rhs_end)
        else if ch == '(' then
          let inner_pos = skip_space (src, atom_pos + 1) in
          if src.[inner_pos] == ')' then
            p_return (inner_pos + 1, unit_expr 0)
          else
            let expr = parse_expr_prec (src, (atom_pos + 1, (1, (0, (0, EInt 0))))) in
            let (ast, expr_end) = expr in
            let after_first = skip_space (src, expr_end) in
            if src.[after_first] == ',' then
              let right = parse_expr_prec (src, (after_first + 1, (1, (0, (0, EInt 0))))) in
              let (right_ast, right_end) = right in
              p_return (p_need_char (src, (right_end, ')')), EMore (EMore2 (EMore3 (EMore4 (EMore5 (EPair (ast, right_ast)))))))
            else
              p_return (p_need_char (src, (expr_end, ')')), ast)
        else if is_true_at (src, atom_pos) then
          p_return (atom_pos + 4, EBool 1)
        else if is_false_at (src, atom_pos) then
          p_return (atom_pos + 5, EBool 0)
        else if ch == '{' then
          let field1 = parse_ident (src, atom_pos + 1) in
          let (field1_name, field1_end) = field1 in
          let eq1 = p_need_char (src, (field1_end, '=')) in
          let value1 = parse_expr_prec (src, (eq1, (0, (0, (0, EInt 0))))) in
          let (value1_ast, value1_end) = value1 in
          let semi1 = p_need_char (src, (value1_end, ';')) in
          let field2 = parse_ident (src, semi1) in
          let (field2_name, field2_end) = field2 in
          let eq2 = p_need_char (src, (field2_end, '=')) in
          let value2 = parse_expr_prec (src, (eq2, (0, (0, (0, EInt 0))))) in
          let (value2_ast, value2_end) = value2 in
          let maybe_close = p_optional_pos (p_try_char (src, (value2_end, '}')), value2_end) in
          let (has_close, after_value2) = maybe_close in
          if has_close == 1 then
            (record_expr (field1_name, (value1_ast, (field2_name, value2_ast))), after_value2)
          else
            let semi2 = p_need_char (src, (value2_end, ';')) in
            let field3 = parse_ident (src, semi2) in
            let (field3_name, field3_end) = field3 in
            let eq3 = p_need_char (src, (field3_end, '=')) in
            let value3 = parse_expr_prec (src, (eq3, (0, (0, (0, EInt 0))))) in
            let (value3_ast, value3_end) = value3 in
            let done_pos = p_need_char (src, (value3_end, '}')) in
            (record3_expr (field1_name, (value1_ast, (field2_name, (value2_ast, (field3_name, value3_ast))))), done_pos)
        else if ch == '\'' then
          parse_char_literal (src, atom_pos)
        else if ch == '"' then
          let parsed_string = parse_string_literal (src, atom_pos) in
          let (string_ast, string_end) = parsed_string in
          parse_index_suffix (src, (string_ast, string_end))
        else if is_digit ch then
          parse_number (src, atom_pos)
        else if is_upper ch == 1 then
          let ctor = parse_ident (src, atom_pos) in
          let (name, name_end) = ctor in
          if starts_call_arg (src, name_end) == 1 then
            let arg = parse_call_arg (src, name_end) in
            let (arg_ast, arg_end) = arg in
            p_return (arg_end, constr_arg_expr (name, arg_ast))
          else
            p_return (name_end, constr_expr name)
        else
          let ident = parse_ident (src, atom_pos) in
          let (name, name_end) = ident in
          if starts_call_arg (src, name_end) == 1 then
            let arg = parse_call_arg (src, name_end) in
            let (arg_ast, arg_end) = arg in
            parse_index_suffix (src, (call_expr (name, arg_ast), arg_end))
          else
            parse_index_suffix (src, (EVar name, name_end))
    in
    let (left_ast, left_end) = left in
    parse_expr_prec (src, (left_end, (allow_seq, (min_prec, (1, left_ast)))))
  else
    let parsed_op = parse_binop (src, (pos0, allow_seq)) in
    let (op, op_rest) = parsed_op in
    let (op_end, prec) = op_rest in
    if op == 0 then
      (left_ast0, pos0)
    else if prec < min_prec then
      (left_ast0, pos0)
    else
      let right = parse_expr_prec (src, (op_end, (allow_seq, (prec + 1, (0, EInt 0))))) in
      let (right_ast, right_end) = right in
      let next_left = make_binop (op, (left_ast0, right_ast)) in
      parse_expr_prec (src, (right_end, (allow_seq, (min_prec, (1, next_left)))))
and parse_match_cases state =
  let (src, pos0) = state in
  let case_pat = parse_ident (src, pos0) in
  let (case_name, case_pat_end) = case_pat in
  let case_bind = parse_match_bind (src, case_pat_end) in
  let (case_bind_kind, case_bind_pair) = case_bind in
  let (case_bind_name, case_bind_rest) = case_bind_pair in
  let (case_bind_name2, case_pat_done) = case_bind_rest in
  let case_body = parse_expr_prec (src, (need_arrow (src, case_pat_done), (0, (0, (0, EInt 0))))) in
  let (case_body_ast, case_body_end) = case_body in
  let tail_bar = p_optional_pos (p_try_char (src, (case_body_end, '|')), case_body_end) in
  let (has_tail, tail_pos) = tail_bar in
  if has_tail == 1 then
    let parsed_tail = parse_match_cases (src, tail_pos) in
    let (tail_ast, tail_end) = parsed_tail in
    (match_case_expr (case_name, (case_bind_kind, (case_bind_name, (case_bind_name2, (case_body_ast, tail_ast))))), tail_end)
  else
    (match_case_expr (case_name, (case_bind_kind, (case_bind_name, (case_bind_name2, (case_body_ast, MatchEnd))))), case_body_end)
in
let rec parse_expr_flag state =
  let (src, pair) = state in
  let (pos0, allow_seq) = pair in
  parse_expr_prec (src, (pos0, (allow_seq, (0, (0, EInt 0)))))
in
let rec parse_expr state =
  let (src, pos0) = state in
  parse_expr_flag (src, (pos0, 1))
in
let rec p_expr_or_parse state =
  let (reply, pair) = state in
  let (src, pos) = pair in
  match reply with
    ExprSome parsed -> parsed
  | ExprNone -> parse_expr (src, pos)
in
let rec skip_program_types state =
  let (src, pos0) = state in
  (src, skip_type_decls (src, pos0))
in
let rec top_let_start state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let parsed = p_optional_pos (p_try_keyword (src, (pos, "let")), pos) in
  let (has_let, after_let) = parsed in
  (has_let, (pos, after_let))
in
let rec top_let_has_let state =
  let parsed = top_let_start state in
  let (has_let, pair) = parsed in
  let _ = pair in
  has_let
in
let rec top_let_bind_state_opt state =
  let (src, pos0) = state in
  let parsed = top_let_start (src, pos0) in
  let (has_let, pair) = parsed in
  let (let_pos, after_let) = pair in
  let _ = has_let in
  (src, (let_pos, skip_space (src, after_let)))
in
let rec parse_program state =
  p_expr_or_parse (parse_top_let (skip_program_types state), skip_program_types state)
and parse_top_let state =
  if top_let_has_let state == 1 then parse_top_let_binding (top_let_bind_state_opt state) else ExprNone
and parse_top_let_binding state =
  let (src, pair) = state in
  let (let_pos, bind_pos) = pair in
    if is_rec_at (src, bind_pos) == 1 then
      let fname = parse_ident (src, bind_pos + 3) in
      let (fname_pos, fname_end) = fname in
      let param = parse_ident (src, fname_end) in
      let (param_pos, param_end) = param in
      let eq_pos = need_char (src, (param_end, '=')) in
      let fn_body = parse_expr_flag (src, (eq_pos, 0)) in
      let (fn_body_ast, fn_body_end) = fn_body in
      let after_fn = skip_space (src, fn_body_end) in
      if is_and_at (src, after_fn) == 1 then
        let sname = parse_ident (src, after_fn + 3) in
        let (sname_pos, sname_end) = sname in
        let sparam = parse_ident (src, sname_end) in
        let (sparam_pos, sparam_end) = sparam in
        let seq_pos = need_char (src, (sparam_end, '=')) in
        let s_body = parse_expr_flag (src, (seq_pos, 0)) in
        let (s_body_ast, s_body_end) = s_body in
        let after_s = skip_space (src, s_body_end) in
        if is_and_at (src, after_s) == 1 then
          let tname = parse_ident (src, after_s + 3) in
          let (tname_pos, tname_end) = tname in
          let tparam = parse_ident (src, tname_end) in
          let (tparam_pos, tparam_end) = tparam in
          let teq_pos = need_char (src, (tparam_end, '=')) in
          let t_body = parse_expr_flag (src, (teq_pos, 0)) in
          let (t_body_ast, t_body_end) = t_body in
          let after_t = skip_space (src, t_body_end) in
          let body_pos = if is_in_at (src, after_t) then need_in (src, t_body_end) else after_t in
          let body = parse_program (src, body_pos) in
          let (body_ast, body_end) = body in
          ExprSome (let_rec3_expr (fname_pos, (param_pos, (fn_body_ast, (sname_pos, (sparam_pos, (s_body_ast, (tname_pos, (tparam_pos, (t_body_ast, body_ast))))))))), body_end)
        else
          let body_pos = if is_in_at (src, after_s) then need_in (src, s_body_end) else after_s in
          let body = parse_program (src, body_pos) in
          let (body_ast, body_end) = body in
          ExprSome (let_rec2_expr (fname_pos, (param_pos, (fn_body_ast, (sname_pos, (sparam_pos, (s_body_ast, body_ast)))))), body_end)
      else
        let body_pos = if is_in_at (src, after_fn) then need_in (src, fn_body_end) else after_fn in
        let body = parse_program (src, body_pos) in
        let (body_ast, body_end) = body in
        ExprSome (let_rec_expr (fname_pos, (param_pos, (fn_body_ast, body_ast))), body_end)
    else if src.[bind_pos] == '(' then
      let name1 = parse_ident (src, bind_pos + 1) in
      let (name1_pos, name1_end0) = name1 in
      let comma = need_char (src, (name1_end0, ',')) in
      let name2 = parse_ident (src, comma) in
      let (name2_pos, name2_end0) = name2 in
      let after_names = need_char (src, (name2_end0, ')')) in
      let eq_pos = need_char (src, (after_names, '=')) in
      let rhs = parse_expr_flag (src, (eq_pos, 0)) in
      let (rhs_ast, rhs_end) = rhs in
      let after_rhs = skip_space (src, rhs_end) in
      if is_in_at (src, after_rhs) then ExprSome (parse_expr (src, let_pos)) else
        let body = parse_program (src, after_rhs) in
        let (body_ast, body_end) = body in
        ExprSome (let_pair_expr (name1_pos, (name2_pos, (rhs_ast, body_ast))), body_end)
    else
      let ident = parse_ident (src, bind_pos) in
      let (name, name_end) = ident in
      let eq_pos = need_char (src, (name_end, '=')) in
      let rhs = parse_expr_flag (src, (eq_pos, 0)) in
      let (rhs_ast, rhs_end) = rhs in
      let after_rhs = skip_space (src, rhs_end) in
      if is_in_at (src, after_rhs) then ExprSome (parse_expr (src, let_pos)) else
        let body = parse_program (src, after_rhs) in
        let (body_ast, body_end) = body in
        ExprSome (let_expr (name, (rhs_ast, body_ast)), body_end)
in
let rec empty_tenv unit =
  let _ = unit in
  (0 - 1, (TyInt, 0))
in
let rec extend_tenv state =
  let (name, pair) = state in
  let (typ, env) = pair in
  (name, (typ, env))
in
let rec lookup_tenv state =
  let (src, pair) = state in
  let (env, name) = pair in
  let (head, rest) = env in
  let (typ, tail) = rest in
  if head < 0 then fail 0 else
  if ident_eq (src, (head, name)) == 1 then typ else lookup_tenv (src, (tail, name))
in
let rec empty_ctors unit =
  let _ = unit in
  (0 - 1, (0, 0))
in
let rec pack_ctor state =
  let (tag, kind) = state in
  (tag * 4) + kind
in
let rec ctor_tag packed =
  packed / 4
in
let rec ctor_kind packed =
  packed - ((packed / 4) * 4)
in
let rec ctor_has_arg packed =
  if ctor_kind packed == 1 then 1 else 0
in
let rec ctor_is_field packed =
  if ctor_kind packed == 2 then 1 else 0
in
let rec field_index packed =
  let tag = ctor_tag packed in
  tag - ((tag / 8) * 8)
in
let rec extend_ctor state =
  let (name, pair) = state in
  let (packed, ctors) = pair in
  (name, (packed, ctors))
in
let rec find_ctor state =
  let (src, pair) = state in
  let (ctors, want) = pair in
  let (name, rest) = ctors in
  let (packed, tail) = rest in
  if name < 0 then 0 - 1 else
  if ident_eq (src, (name, want)) == 1 then packed else find_ctor (src, (tail, want))
in
let rec lookup_ctor state =
  let packed = find_ctor state in
  if packed < 0 then fail 0 else packed
in
let rec empty_tnames unit =
  let _ = unit in
  (0 - 1, (0, 0))
in
let rec extend_tname state =
  let (name, pair) = state in
  let (type_id, names) = pair in
  (name, (type_id, names))
in
let rec lookup_tname state =
  let (src, pair) = state in
  let (names, want) = pair in
  let (name, rest) = names in
  let (type_id, tail) = rest in
  if name < 0 then fail 0 else
  if ident_eq (src, (name, want)) == 1 then type_id else lookup_tname (src, (tail, want))
in
let rec parse_type_atom state =
  let (src, pair) = state in
  let (pos0, pair0) = pair in
  let (type_id, type_names) = pair0 in
  let pos = skip_space (src, pos0) in
  if src.[pos] == '(' then
    let left = parse_type_atom (src, (pos + 1, (type_id, type_names))) in
    let (left_ty, left_end) = left in
    let star = need_char (src, (left_end, '*')) in
    let right = parse_type_atom (src, (star, (type_id, type_names))) in
    let (right_ty, right_end) = right in
    (TyMore (TyPair (left_ty, right_ty)), need_char (src, (right_end, ')')))
  else
  if p_keyword_at (src, (pos, "int")) == 1 then (TyInt, p_need_keyword (src, (pos, "int"))) else
  if p_keyword_at (src, (pos, "bool")) == 1 then (TyBool, p_need_keyword (src, (pos, "bool"))) else
  if p_keyword_at (src, (pos, "string")) == 1 then (TyMore TyString, p_need_keyword (src, (pos, "string"))) else
  if p_keyword_at (src, (pos, "bytes")) == 1 then (TyMore TyBytes, p_need_keyword (src, (pos, "bytes"))) else
    let parsed = parse_ident (src, pos) in
    let (name, done_pos) = parsed in
    (TyMore (TyMore2 (TyAdt (lookup_tname (src, (type_names, name))))), done_pos)
in
let rec parse_type_expr state =
  let (src, pair) = state in
  let (pos0, pair0) = pair in
  let (type_id, type_names) = pair0 in
  let left = parse_type_atom (src, (pos0, (type_id, type_names))) in
  let (left_ty, left_end) = left in
  let next = skip_space (src, left_end) in
  if src.[next] == '*' then
    let right = parse_type_expr (src, (next + 1, (type_id, type_names))) in
    let (right_ty, done_pos) = right in
    (TyMore (TyPair (left_ty, right_ty)), done_pos)
  else
    (left_ty, left_end)
in
let rec parse_type_ctors state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (type_id, pair3) = pair2 in
  let (type_names, pair4) = pair3 in
  let (tag, pair5) = pair4 in
  let (tenv, ctors) = pair5 in
  let pos1 = skip_space (src, pos0) in
  let pos = if src.[pos1] == '|' then skip_space (src, pos1 + 1) else pos1 in
  let parsed_name = parse_ident (src, pos) in
  let (name, name_end) = parsed_name in
  let after_name = skip_space (src, name_end) in
  let parsed_ctor =
    if is_of_at (src, after_name) == 1 then
      let arg_ty = parse_type_expr (src, (need_of (src, after_name), (type_id, type_names))) in
      let (inner_ty, done_pos) = arg_ty in
      let result_ty = TyMore (TyMore2 (TyAdt type_id)) in
      let ctor_ty = TyMore (TyMore2 (TyFun (TyMore (TyPair (inner_ty, result_ty))))) in
      (done_pos, (1, ctor_ty))
    else
      (after_name, (0, TyMore (TyMore2 (TyAdt type_id))))
  in
  let (done_pos, ctor_pair) = parsed_ctor in
  let (has_arg, ctor_ty) = ctor_pair in
  let next_tenv = extend_tenv (name, (ctor_ty, tenv)) in
  let next_ctors = extend_ctor (name, (pack_ctor (tag, has_arg), ctors)) in
  let next = skip_inline_space (src, done_pos) in
  if src.[next] == '|' then parse_type_ctors (src, (next, (type_id, (type_names, (tag + 1, (next_tenv, next_ctors)))))) else
    (next, (next_tenv, next_ctors))
in
let rec parse_record_fields state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (type_id, pair3) = pair2 in
  let (type_names, pair4) = pair3 in
  let (index, pair5) = pair4 in
  let (tenv, ctors) = pair5 in
  let pos = skip_space (src, pos0) in
  if src.[pos] == '}' then (pos + 1, (tenv, ctors)) else
    let field = parse_ident (src, pos) in
    let (field_name, field_end) = field in
    let colon = p_need_char (src, (field_end, ':')) in
    let parsed_type = parse_type_expr (src, (colon, (type_id, type_names))) in
    let (field_ty, field_type_end) = parsed_type in
    let record_ty = TyMore (TyMore2 (TyAdt type_id)) in
    let field_sig = TyMore (TyMore2 (TyFun (TyMore (TyPair (record_ty, field_ty))))) in
    let next_tenv = extend_tenv (field_name, (field_sig, tenv)) in
    let next_ctors = extend_ctor (field_name, (pack_ctor (((type_id * 8) + index), 2), ctors)) in
    let next = skip_space (src, field_type_end) in
    if src.[next] == ';' then
      parse_record_fields (src, (next + 1, (type_id, (type_names, (index + 1, (next_tenv, next_ctors))))))
    else if src.[next] == '}' then
      (next + 1, (next_tenv, next_ctors))
    else
      fail 0
in
let rec parse_type_decls state =
  let (src, pair) = state in
  let (pos0, pair2) = pair in
  let (type_id, pair3) = pair2 in
  let (type_names, pair4) = pair3 in
  let (tenv, ctors) = pair4 in
  let pos = skip_space (src, pos0) in
  if is_type_at (src, pos) == 1 then
    let type_pos = p_need_keyword (src, (pos, "type")) in
    let type_name = parse_ident (src, type_pos) in
    let (type_name_pos, type_name_end) = type_name in
    let next_type_names = extend_tname (type_name_pos, (type_id, type_names)) in
    let eq_pos = need_char (src, (type_name_end, '=')) in
    let after_eq = skip_space (src, eq_pos) in
    let parsed =
      if src.[after_eq] == '{' then
        parse_record_fields (src, (after_eq + 1, (type_id, (next_type_names, (0, (tenv, ctors))))))
      else
        parse_type_ctors (src, (eq_pos, (type_id, (next_type_names, (0, (tenv, ctors))))))
    in
    let (next_pos, next_envs) = parsed in
    let (next_tenv, next_ctors) = next_envs in
    parse_type_decls (src, (next_pos, (type_id + 1, (next_type_names, (next_tenv, next_ctors)))))
  else
    (pos, (tenv, ctors))
in
let rec same_ty state =
  let (left, right) = state in
  match left with
    TyInt -> (match right with TyInt -> 1 | _ -> 0)
  | TyUnit -> (match right with TyUnit -> 1 | _ -> 0)
  | TyBool -> (match right with TyBool -> 1 | _ -> 0)
  | TyMore left_more ->
      match left_more with
        TyString -> (match right with TyMore right_more -> (match right_more with TyString -> 1 | _ -> 0) | _ -> 0)
      | TyBytes -> (match right with TyMore right_more -> (match right_more with TyBytes -> 1 | _ -> 0) | _ -> 0)
      | TyCell left_inner ->
          (match right with
            TyMore right_more ->
              (match right_more with TyCell right_inner -> same_ty (left_inner, right_inner) | _ -> 0)
          | _ -> 0)
      | TyArray left_inner ->
          (match right with
            TyMore right_more ->
              (match right_more with TyArray right_inner -> same_ty (left_inner, right_inner) | _ -> 0)
          | _ -> 0)
      | TyMore2 left_more2 ->
          (match left_more2 with
            TyFun left_fun ->
              (match right with
                TyMore right_more ->
                  (match right_more with
                    TyMore2 right_more2 ->
                      (match right_more2 with TyFun right_fun -> same_ty (left_fun, right_fun) | _ -> 0)
                  | _ -> 0)
              | _ -> 0)
          | TyAdt left_id ->
              (match right with
                TyMore right_more ->
                  (match right_more with
                    TyMore2 right_more2 ->
                      (match right_more2 with TyAdt right_id -> if left_id == right_id then 1 else 0 | _ -> 0)
                  | _ -> 0)
              | _ -> 0))
      | TyPair left_pair ->
          match right with
            TyMore right_more ->
              (match right_more with
                TyPair right_pair ->
                  let (left1, left2) = left_pair in
                  let (right1, right2) = right_pair in
                  if same_ty (left1, right1) == 1 then same_ty (left2, right2) else 0
              | _ -> 0)
          | _ -> 0
in
let rec need_ty state =
  let (got, want) = state in
  if same_ty (got, want) == 1 then 0 else fail 0
in
let rec field_record_ty ty =
  match ty with
    TyMore more ->
      (match more with
        TyMore2 more2 ->
          (match more2 with
            TyFun fn_pair ->
              (match fn_pair with
                TyMore fn_more ->
                  (match fn_more with
                    TyPair arg_ret ->
                      let (record_ty, _field_ty) = arg_ret in
                      record_ty
                  | _ -> fail 0)
              | _ -> fail 0)
          | _ -> fail 0)
      | _ -> fail 0)
  | _ -> fail 0
in
let rec field_value_ty ty =
  match ty with
    TyMore more ->
      (match more with
        TyMore2 more2 ->
          (match more2 with
            TyFun fn_pair ->
              (match fn_pair with
                TyMore fn_more ->
                  (match fn_more with
                    TyPair arg_ret ->
                      let (_record_ty, field_ty) = arg_ret in
                      field_ty
                  | _ -> fail 0)
              | _ -> fail 0)
          | _ -> fail 0)
      | _ -> fail 0)
  | _ -> fail 0
in
let rec extend_tenv_if_named state =
  let (src, pair0) = state in
  let (name, pair1) = pair0 in
  let (typ, env) = pair1 in
  if is_wild_name (src, name) == 1 then env else extend_tenv (name, (typ, env))
in
let rec match_case_tenv state =
  let (src, pair0) = state in
  let (env, pair1) = pair0 in
  let (scrutinee_ty, pair2) = pair1 in
  let (ctor_name, pair3) = pair2 in
  let (bind_kind, pair4) = pair3 in
  let (bind_name, bind_name2) = pair4 in
  let ctor_ty = lookup_tenv (src, (env, ctor_name)) in
  match ctor_ty with
    TyMore more ->
      (match more with
        TyMore2 more2 ->
          (match more2 with
            TyFun fn_pair ->
              (match fn_pair with
                TyMore fn_more ->
                  (match fn_more with
                    TyPair arg_ret ->
                      let (arg_ty, ret_ty) = arg_ret in
                      let _ = need_ty (ret_ty, scrutinee_ty) in
                      if bind_kind == 1 then extend_tenv_if_named (src, (bind_name, (arg_ty, env))) else
                      if bind_kind == 2 then
                        (match arg_ty with
                          TyMore arg_more ->
                            (match arg_more with
                              TyPair pair_ty ->
                                let (left_ty, right_ty) = pair_ty in
                                let env1 = extend_tenv_if_named (src, (bind_name, (left_ty, env))) in
                                extend_tenv_if_named (src, (bind_name2, (right_ty, env1)))
                            | _ -> fail 0)
                        | _ -> fail 0)
                      else if bind_kind == 3 then
                        (match arg_ty with
                          TyMore arg_more ->
                            (match arg_more with
                              TyPair pair_ty ->
                                let (nested_ty, right_ty) = pair_ty in
                                (match nested_ty with
                                  TyMore nested_more ->
                                    (match nested_more with
                                      TyPair nested_pair_ty ->
                                        let (left_ty, middle_ty) = nested_pair_ty in
                                        let (middle_name, right_name) = bind_name2 in
                                        let env1 = extend_tenv_if_named (src, (bind_name, (left_ty, env))) in
                                        let env2 = extend_tenv_if_named (src, (middle_name, (middle_ty, env1))) in
                                        extend_tenv_if_named (src, (right_name, (right_ty, env2)))
                                    | _ -> fail 0)
                                | _ -> fail 0)
                            | _ -> fail 0)
                        | _ -> fail 0)
                      else if bind_kind == 4 then
                        (match arg_ty with
                          TyMore arg_more ->
                            (match arg_more with
                              TyPair pair_ty ->
                                let (left_ty, nested_ty) = pair_ty in
                                (match nested_ty with
                                  TyMore nested_more ->
                                    (match nested_more with
                                      TyPair nested_pair_ty ->
                                        let (middle_ty, right_ty) = nested_pair_ty in
                                        let (middle_name, right_name) = bind_name2 in
                                        let env1 = extend_tenv_if_named (src, (bind_name, (left_ty, env))) in
                                        let env2 = extend_tenv_if_named (src, (middle_name, (middle_ty, env1))) in
                                        extend_tenv_if_named (src, (right_name, (right_ty, env2)))
                                    | _ -> fail 0)
                                | _ -> fail 0)
                            | _ -> fail 0)
                        | _ -> fail 0)
                      else fail 0
                  | _ -> fail 0)
              | _ -> fail 0)
          | TyAdt id ->
              let _ = id in
              let _ = if bind_kind == 0 then 0 else fail 0 in
              let _ = need_ty (ctor_ty, scrutinee_ty) in
              env)
      | _ ->
          let _ = if bind_kind == 0 then 0 else fail 0 in
          let _ = need_ty (ctor_ty, scrutinee_ty) in
          env)
  | _ ->
      let _ = if bind_kind == 0 then 0 else fail 0 in
      let _ = need_ty (ctor_ty, scrutinee_ty) in
      env
in
let rec match_case2_tenv state =
  let (src, pair0) = state in
  let (env, pair1) = pair0 in
  let (scrutinee_ty, pair2) = pair1 in
  let (case_name, pair3) = pair2 in
  let (bind_kind, pair4) = pair3 in
  let (bind_name, bind_name2) = pair4 in
  let _ = bind_name2 in
  if is_wild_name (src, case_name) == 1 then
    let _ = if bind_kind == 0 then 0 else fail 0 in
    env
  else if is_upper (src.[case_name]) == 1 then
    match_case_tenv (src, (env, (scrutinee_ty, (case_name, (bind_kind, (bind_name, bind_name2))))))
  else
    let _ = if bind_kind == 0 then 0 else fail 0 in
    extend_tenv (case_name, (scrutinee_ty, env))
in
let rec infer state =
  let (src, pair0) = state in
  let (env, ast) = pair0 in
  match ast with
    EInt value -> let _ = value in TyInt
  | EVar name -> lookup_tenv (src, (env, name))
  | EBool value -> let _ = value in TyBool
  | EMore more ->
      match more with
        EWriteByte expr ->
          let _ = need_ty (infer (src, (env, expr)), TyInt) in
          TyUnit
      | EAdd pair ->
          let (left, right) = pair in
          let _ = need_ty (infer (src, (env, left)), TyInt) in
          let _ = need_ty (infer (src, (env, right)), TyInt) in
          TyInt
      | ESub pair ->
          let (left, right) = pair in
          let _ = need_ty (infer (src, (env, left)), TyInt) in
          let _ = need_ty (infer (src, (env, right)), TyInt) in
          TyInt
      | EMore2 more2 ->
          match more2 with
            EMul pair ->
              let (left, right) = pair in
              let _ = need_ty (infer (src, (env, left)), TyInt) in
              let _ = need_ty (infer (src, (env, right)), TyInt) in
              TyInt
          | EDiv pair ->
              let (left, right) = pair in
              let _ = need_ty (infer (src, (env, left)), TyInt) in
              let _ = need_ty (infer (src, (env, right)), TyInt) in
              TyInt
          | EEq pair2 ->
              let (left, right) = pair2 in
              let left_ty = infer (src, (env, left)) in
              let _ = need_ty (infer (src, (env, right)), left_ty) in
              TyBool
          | EMore3 more3 ->
              match more3 with
                ENe pair2 ->
                  let (left, right) = pair2 in
                  let left_ty = infer (src, (env, left)) in
                  let _ = need_ty (infer (src, (env, right)), left_ty) in
                  TyBool
              | ELt pair ->
                  let (left, right) = pair in
                  let _ = need_ty (infer (src, (env, left)), TyInt) in
                  let _ = need_ty (infer (src, (env, right)), TyInt) in
                  TyBool
              | ELe pair ->
                  let (left, right) = pair in
                  let _ = need_ty (infer (src, (env, left)), TyInt) in
                  let _ = need_ty (infer (src, (env, right)), TyInt) in
                  TyBool
              | EMore4 more4 ->
                  match more4 with
                    EGt pair ->
                      let (left, right) = pair in
                      let _ = need_ty (infer (src, (env, left)), TyInt) in
                      let _ = need_ty (infer (src, (env, right)), TyInt) in
                      TyBool
                  | EGe pair ->
                      let (left, right) = pair in
                      let _ = need_ty (infer (src, (env, left)), TyInt) in
                      let _ = need_ty (infer (src, (env, right)), TyInt) in
                      TyBool
                  | EIf parts ->
                      let (cond, branches) = parts in
                      let (yes, no) = branches in
                      let _ = need_ty (infer (src, (env, cond)), TyBool) in
                      let yes_ty = infer (src, (env, yes)) in
                      let _ = need_ty (infer (src, (env, no)), yes_ty) in
                      yes_ty
                  | EMore5 more5 ->
                      match more5 with
                        ELet parts ->
                          let (name, body_pair) = parts in
                          let (rhs, body) = body_pair in
                          let rhs_ty = infer (src, (env, rhs)) in
                          infer (src, (extend_tenv_if_named (src, (name, (rhs_ty, env))), body))
                        | EPair parts ->
                            let (left, right) = parts in
                            TyMore (TyPair (infer (src, (env, left)), infer (src, (env, right))))
                      | ELetPair parts ->
                          let (name1, rest1) = parts in
                          let (name2, rest2) = rest1 in
                          let (rhs, body) = rest2 in
                          let rhs_ty = infer (src, (env, rhs)) in
                          (match rhs_ty with
                            TyMore more ->
                              (match more with
                                TyPair pair_ty ->
                                  let (left_ty, right_ty) = pair_ty in
                                  let env1 = extend_tenv_if_named (src, (name1, (left_ty, env))) in
                                  infer (src, (extend_tenv_if_named (src, (name2, (right_ty, env1))), body))
                              | TyString -> fail 0
                              | TyBytes -> fail 0
                              | TyCell inner -> let _ = inner in fail 0
                              | TyArray inner -> let _ = inner in fail 0
                              | TyMore2 more2 -> let _ = more2 in fail 0)
                          | TyInt -> fail 0
                          | TyUnit -> fail 0
                          | TyBool -> fail 0)
                      | EMore6 more6 ->
                          match more6 with
                            ESeq parts ->
                              let (left, right) = parts in
                              let _ = need_ty (infer (src, (env, left)), TyUnit) in
                              infer (src, (env, right))
                          | EDebugByte expr ->
                              let _ = need_ty (infer (src, (env, expr)), TyInt) in
                              TyUnit
                          | EExit expr ->
                              let _ = need_ty (infer (src, (env, expr)), TyInt) in
                              TyUnit
                            | EReadByte -> TyInt
                            | EMore7 more7 ->
                                match more7 with
                                  EString pos -> let _ = pos in TyMore TyString
                                | EStringLength expr ->
                                    let _ = need_ty (infer (src, (env, expr)), TyMore TyString) in
                                    TyInt
                                | EBytesCreate expr ->
                                    let _ = need_ty (infer (src, (env, expr)), TyInt) in
                                    TyMore TyBytes
                                | EMore8 more8 ->
                                    match more8 with
                                    EBytesLength expr ->
                                      let _ = need_ty (infer (src, (env, expr)), TyMore TyBytes) in
                                      TyInt
                                  | EIndex parts ->
                                      let (base, index) = parts in
                                      let base_ty = infer (src, (env, base)) in
                                      let _ = need_ty (infer (src, (env, index)), TyInt) in
                                      (match base_ty with
                                        TyMore more ->
                                          (match more with
                                            TyString -> TyInt
                                          | TyBytes -> TyInt
                                          | TyArray inner -> inner
                                          | TyPair pair_ty -> let _ = pair_ty in fail 0
                                          | TyCell inner -> let _ = inner in fail 0
                                          | TyMore2 more2 -> let _ = more2 in fail 0)
                                      | TyInt -> fail 0
                                      | TyUnit -> fail 0
                                      | TyBool -> fail 0)
                                  | ESetIndex parts ->
                                      let (base, rest) = parts in
                                      let (index, value) = rest in
                                      let base_ty = infer (src, (env, base)) in
                                      let _ = need_ty (infer (src, (env, index)), TyInt) in
                                      (match base_ty with
                                        TyMore more ->
                                          (match more with
                                            TyBytes ->
                                              let _ = need_ty (infer (src, (env, value)), TyInt) in
                                              TyUnit
                                          | TyArray inner ->
                                              let _ = need_ty (infer (src, (env, value)), inner) in
                                              TyUnit
                                          | TyString -> fail 0
                                          | TyPair pair_ty -> let _ = pair_ty in fail 0
                                          | TyCell inner -> let _ = inner in fail 0
                                          | TyMore2 more2 -> let _ = more2 in fail 0)
                                      | TyInt -> fail 0
                                      | TyUnit -> fail 0
                                      | TyBool -> fail 0)
                                  | EMore9 more9 ->
                                      match more9 with
                                        EDebugInt expr ->
                                          let _ = need_ty (infer (src, (env, expr)), TyInt) in
                                          TyUnit
                                      | EUnit -> TyUnit
                                      | EMore10 more10 ->
                                          match more10 with
                                            ECellCreate expr ->
                                              TyMore (TyCell (infer (src, (env, expr))))
                                          | ECellGet expr ->
                                              let cell_ty = infer (src, (env, expr)) in
                                              (match cell_ty with
                                                TyMore more ->
                                                  (match more with
                                                    TyCell inner -> inner
                                                  | TyString -> fail 0
                                                  | TyBytes -> fail 0
                                                  | TyPair pair_ty -> let _ = pair_ty in fail 0
                                                  | TyArray inner -> let _ = inner in fail 0
                                                  | TyMore2 more2 -> let _ = more2 in fail 0)
                                              | TyInt -> fail 0
                                              | TyUnit -> fail 0
                                              | TyBool -> fail 0)
                                          | ECellSet parts ->
                                              let (cell, value) = parts in
                                              let cell_ty = infer (src, (env, cell)) in
                                              (match cell_ty with
                                                TyMore more ->
                                                  (match more with
                                                    TyCell inner ->
                                                      let _ = need_ty (infer (src, (env, value)), inner) in
                                                      TyUnit
                                                  | TyString -> fail 0
                                                  | TyBytes -> fail 0
                                                  | TyPair pair_ty -> let _ = pair_ty in fail 0
                                                  | TyArray inner -> let _ = inner in fail 0
                                                  | TyMore2 more2 -> let _ = more2 in fail 0)
                                              | TyInt -> fail 0
                                              | TyUnit -> fail 0
                                              | TyBool -> fail 0)
                                          | EArrayCreate parts ->
                                              let (size, init) = parts in
                                              let _ = need_ty (infer (src, (env, size)), TyInt) in
                                              TyMore (TyArray (infer (src, (env, init))))
                                          | ELetRec parts ->
                                              let fn_sig = TyMore (TyMore2 (TyFun (TyMore (TyPair (TyInt, TyInt))))) in
                                              let (count, payload) = parts in
                                              if count == 1 then
                                                let (name, rest1) = payload in
                                                let (param, rest2) = rest1 in
                                                let (fn_body, body) = rest2 in
                                                let fn_env = extend_tenv (name, (fn_sig, env)) in
                                                let body_env = extend_tenv (param, (TyInt, fn_env)) in
                                                let _ = need_ty (infer (src, (body_env, fn_body)), TyInt) in
                                                infer (src, (fn_env, body))
                                              else if count == 2 then
                                                let (name1, rest1) = payload in
                                                let (param1, rest2) = rest1 in
                                                let (body1, rest3) = rest2 in
                                                let (name2, rest4) = rest3 in
                                                let (param2, rest5) = rest4 in
                                                let (body2, final) = rest5 in
                                                let fn_env1 = extend_tenv (name1, (fn_sig, env)) in
                                                let fn_env = extend_tenv (name2, (fn_sig, fn_env1)) in
                                                let body_env1 = extend_tenv (param1, (TyInt, fn_env)) in
                                                let body_env2 = extend_tenv (param2, (TyInt, fn_env)) in
                                                let _ = need_ty (infer (src, (body_env1, body1)), TyInt) in
                                                let _ = need_ty (infer (src, (body_env2, body2)), TyInt) in
                                                infer (src, (fn_env, final))
                                              else if count == 3 then
                                                let (name1, rest1) = payload in
                                                let (param1, rest2) = rest1 in
                                                let (body1, rest3) = rest2 in
                                                let (name2, rest4) = rest3 in
                                                let (param2, rest5) = rest4 in
                                                let (body2, rest6) = rest5 in
                                                let (name3, rest7) = rest6 in
                                                let (param3, rest8) = rest7 in
                                                let (body3, final) = rest8 in
                                                let fn_env1 = extend_tenv (name1, (fn_sig, env)) in
                                                let fn_env2 = extend_tenv (name2, (fn_sig, fn_env1)) in
                                                let fn_env = extend_tenv (name3, (fn_sig, fn_env2)) in
                                                let body_env1 = extend_tenv (param1, (TyInt, fn_env)) in
                                                let body_env2 = extend_tenv (param2, (TyInt, fn_env)) in
                                                let body_env3 = extend_tenv (param3, (TyInt, fn_env)) in
                                                let _ = need_ty (infer (src, (body_env1, body1)), TyInt) in
                                                let _ = need_ty (infer (src, (body_env2, body2)), TyInt) in
                                                let _ = need_ty (infer (src, (body_env3, body3)), TyInt) in
                                                infer (src, (fn_env, final))
                                              else fail 0
                                          | EMore11 more11 ->
                                              match more11 with
                                                ECall parts ->
                                                  let (name, arg) = parts in
                                                  let fn_ty = lookup_tenv (src, (env, name)) in
                                                  (match fn_ty with
                                                    TyMore more ->
                                                      (match more with
                                                        TyMore2 more2 ->
                                                          (match more2 with
                                                            TyFun fn_pair ->
                                                              (match fn_pair with
                                                                TyMore fn_more ->
                                                                  (match fn_more with
                                                                    TyPair arg_ret ->
                                                                      let (arg_ty, ret_ty) = arg_ret in
                                                                      let _ = need_ty (infer (src, (env, arg)), arg_ty) in
                                                                      ret_ty
                                                                  | _ -> fail 0)
                                                              | _ -> fail 0)
                                                          | TyAdt id -> let _ = id in fail 0)
                                                      | _ -> fail 0)
                                                  | _ -> fail 0)
                                              | EConstr name ->
                                                  lookup_tenv (src, (env, name))
                                              | EConstrArg parts ->
                                                  let (name, arg) = parts in
                                                  let ctor_ty = lookup_tenv (src, (env, name)) in
                                                  (match ctor_ty with
                                                    TyMore more ->
                                                      (match more with
                                                        TyMore2 more2 ->
                                                          (match more2 with
                                                            TyFun fn_pair ->
                                                              (match fn_pair with
                                                                TyMore fn_more ->
                                                                  (match fn_more with
                                                                    TyPair arg_ret ->
                                                                      let (arg_ty, ret_ty) = arg_ret in
                                                                      let _ = need_ty (infer (src, (env, arg)), arg_ty) in
                                                                      ret_ty
                                                                  | _ -> fail 0)
                                                              | _ -> fail 0)
                                                          | TyAdt id -> let _ = id in fail 0)
                                                      | _ -> fail 0)
                                                  | _ -> fail 0)
                                              | EMatch parts ->
                                                  let (scrutinee, cases) = parts in
                                                  let scrutinee_ty = infer (src, (env, scrutinee)) in
                                                  infer_match_cases (src, (env, (scrutinee_ty, cases)))
                                              | ERecord parts ->
                                                  let (field1, rest1) = parts in
                                                  let (value1, rest2) = rest1 in
                                                  let (field2, value2) = rest2 in
                                                  let field1_ty = lookup_tenv (src, (env, field1)) in
                                                  let field2_ty = lookup_tenv (src, (env, field2)) in
                                                  let record_ty = field_record_ty field1_ty in
                                                  let _ = need_ty (field_record_ty field2_ty, record_ty) in
                                                  let _ = need_ty (infer (src, (env, value1)), field_value_ty field1_ty) in
                                                  let _ = need_ty (infer (src, (env, value2)), field_value_ty field2_ty) in
                                                  record_ty
                                              | ERecord3 parts ->
                                                  let (field1, rest1) = parts in
                                                  let (value1, rest2) = rest1 in
                                                  let (field2, rest3) = rest2 in
                                                  let (value2, rest4) = rest3 in
                                                  let (field3, value3) = rest4 in
                                                  let field1_ty = lookup_tenv (src, (env, field1)) in
                                                  let field2_ty = lookup_tenv (src, (env, field2)) in
                                                  let field3_ty = lookup_tenv (src, (env, field3)) in
                                                  let record_ty = field_record_ty field1_ty in
                                                  let _ = need_ty (field_record_ty field2_ty, record_ty) in
                                                  let _ = need_ty (field_record_ty field3_ty, record_ty) in
                                                  let _ = need_ty (infer (src, (env, value1)), field_value_ty field1_ty) in
                                                  let _ = need_ty (infer (src, (env, value2)), field_value_ty field2_ty) in
                                                  let _ = need_ty (infer (src, (env, value3)), field_value_ty field3_ty) in
                                                  record_ty
                                              | EField parts ->
                                                  let (base, field) = parts in
                                                  let field_ty = lookup_tenv (src, (env, field)) in
                                                  let _ = need_ty (infer (src, (env, base)), field_record_ty field_ty) in
                                                  field_value_ty field_ty
and infer_match_cases state =
  let (src, pair0) = state in
  let (env, pair1) = pair0 in
  let (scrutinee_ty, cases) = pair1 in
  match cases with
    MatchEnd -> fail 0
  | MatchCase parts ->
      let (case_name, rest2) = parts in
      let (case_bind_kind, rest3) = rest2 in
      let (case_bind, rest4) = rest3 in
      let (case_bind2, rest5) = rest4 in
      let (case_body, case_tail) = rest5 in
      let is_final =
        match case_tail with
          MatchEnd -> 1
        | MatchCase tail_parts -> let _ = tail_parts in 0
      in
      let case_env =
        if is_final == 1 then
          match_case2_tenv (src, (env, (scrutinee_ty, (case_name, (case_bind_kind, (case_bind, case_bind2))))))
        else
          let _ = if is_upper (src.[case_name]) == 1 then 0 else fail 0 in
          match_case_tenv (src, (env, (scrutinee_ty, (case_name, (case_bind_kind, (case_bind, case_bind2))))))
      in
      let case_ty = infer (src, (case_env, case_body)) in
      (match case_tail with
        MatchEnd -> case_ty
      | MatchCase tail_parts ->
          let _ = tail_parts in
          let _ = need_ty (infer_match_cases (src, (env, (scrutinee_ty, case_tail))), case_ty) in
          case_ty)
in
let rec empty_env unit =
  let _ = unit in
  (0 - 1, (0, 0))
in
let rec shift_env env =
  let (name, rest) = env in
  let (depth, tail) = rest in
  if name < 0 then env else (name, (depth + 1, shift_env tail))
in
let rec extend_env state =
  let (name, env) = state in
  (name, (0, shift_env env))
in
let rec lookup_env state =
  let (src, pair) = state in
  let (env, want) = pair in
  let (name, rest) = env in
  let (depth, tail) = rest in
  if name < 0 then fail 0 else
  if ident_eq (src, (name, want)) == 1 then depth else lookup_env (src, (tail, want))
in
let rec empty_fenv unit =
  let _ = unit in
  (0 - 1, (0, 0))
in
let rec extend_fenv state =
  let (name, pair) = state in
  let (target, funcs) = pair in
  (name, (target, funcs))
in
let rec lookup_fenv state =
  let (src, pair) = state in
  let (funcs, want) = pair in
  let (name, rest) = funcs in
  let (target, tail) = rest in
  if name < 0 then fail 0 else
  if ident_eq (src, (name, want)) == 1 then target else lookup_fenv (src, (tail, want))
in
let rec bind_env_at_if_named state =
  let (src, pair0) = state in
  let (name, pair1) = pair0 in
  let (depth, env) = pair1 in
  if is_wild_name (src, name) == 1 then env else (name, (depth, env))
in
let rec match_case_env state =
  let (src, pair00) = state in
  let (has_arg, pair0) = pair00 in
  let (bind_kind, pair) = pair0 in
  let (bind_name, pair2) = pair in
  let (bind_name2, env) = pair2 in
  if has_arg == 1 then
    if bind_kind == 1 then
      if is_wild_name (src, bind_name) == 1 then shift_env (shift_env env) else extend_env (bind_name, shift_env env)
    else
    if bind_kind == 2 then
      let base = shift_env (shift_env (shift_env (shift_env env))) in
      let env1 = bind_env_at_if_named (src, (bind_name, (1, base))) in
      bind_env_at_if_named (src, (bind_name2, (0, env1)))
    else
    if bind_kind == 3 then
      let base = shift_env (shift_env (shift_env (shift_env (shift_env (shift_env env))))) in
      let (middle_name, right_name) = bind_name2 in
      let env1 = bind_env_at_if_named (src, (bind_name, (2, base))) in
      let env2 = bind_env_at_if_named (src, (middle_name, (1, env1))) in
      bind_env_at_if_named (src, (right_name, (0, env2)))
    else
    if bind_kind == 4 then
      let base = shift_env (shift_env (shift_env (shift_env (shift_env (shift_env env))))) in
      let (middle_name, right_name) = bind_name2 in
      let env1 = bind_env_at_if_named (src, (bind_name, (3, base))) in
      let env2 = bind_env_at_if_named (src, (middle_name, (1, env1))) in
      bind_env_at_if_named (src, (right_name, (0, env2)))
    else fail 0
  else
    let _ = if bind_kind == 0 then 0 else fail 0 in
    shift_env env
in
let rec match_fallback_env state =
  let (src, pair) = state in
  let (name, env) = pair in
  if is_wild_name (src, name) == 1 then shift_env env else extend_env (name, env)
in
let rec emit_match_payload state =
  let (emit, pair) = state in
  let (has_arg, bind_kind) = pair in
  if has_arg == 1 then
    if bind_kind == 3 then
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
      let _ = emit_push emit in
      55
    else if bind_kind == 4 then
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
      let _ = emit_push emit in
      55
    else if bind_kind == 2 then
      let _ = emit_acc (emit, 0) in
      let _ = emit_getfield (emit, 0) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 0) in
      let _ = emit_getfield (emit, 0) in
      let _ = emit_push emit in
      let _ = emit_acc (emit, 1) in
      let _ = emit_getfield (emit, 1) in
      let _ = emit_push emit in
      33
    else
      let _ = emit_acc (emit, 0) in
      let _ = emit_getfield (emit, 0) in
      let _ = emit_push emit in
      11
  else 0
in
let rec emit_match_pop state =
  let (emit, pair) = state in
  let (has_arg, bind_kind) = pair in
  if has_arg == 1 then
    if (bind_kind == 3) + (bind_kind == 4) then emit_pop (emit, 6) else
    if bind_kind == 2 then emit_pop (emit, 4) else emit_pop (emit, 2)
  else emit_pop1 emit
in
let rec emit_string_tail state =
  let (src, pair) = state in
  let (pos, emit) = pair in
  if src.[pos] == '"' then (0, pos + 1) else
    let parsed = parse_string_char (src, pos) in
    let (ch, next_pos) = parsed in
    let push_len = emit_push emit in
    let const_len = emit_const (emit, ch) in
    let rest = emit_string_tail (src, (next_pos, emit)) in
    let (rest_len, done_pos) = rest in
    (push_len + const_len + rest_len, done_pos)
in
let rec emit_string_literal state =
  let (src, pair) = state in
  let (pos, emit) = pair in
  let parsed_len = parse_string_length_loop (src, (pos + 1, 0)) in
  let (len, end_pos) = parsed_len in
  let _ = end_pos in
  if len == 0 then
    emit_makeblock (emit, 0)
  else
    let first = parse_string_char (src, pos + 1) in
    let (ch, next_pos) = first in
    let const_len = emit_const (emit, ch) in
    let tail = emit_string_tail (src, (next_pos, emit)) in
    let (tail_len, done_pos) = tail in
    let _ = done_pos in
    let block_len = emit_makeblock (emit, len) in
    const_len + tail_len + block_len
in
let rec emit_expr state =
  let (ast, pair) = state in
  let (src, pair_src) = pair in
  let (env, pair_env) = pair_src in
  let (ctors, pair_ctors) = pair_env in
  let (funcs, pair_funcs) = pair_ctors in
  let (base_pos, emit) = pair_funcs in
  match ast with
    EInt value -> emit_const (emit, value)
  | EVar name -> emit_acc (emit, lookup_env (src, (env, name)))
  | EBool value -> emit_const (emit, value)
  | EMore more ->
      match more with
        EWriteByte expr ->
          let expr_len = emit_expr (expr, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
          let call_len = emit_call_write_byte emit in
          expr_len + call_len
      | EAdd pair2 ->
          let (left, right) = pair2 in
          let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
          let push_len = emit_push emit in
          let right_len = emit_expr (right, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
          let add_len = emit_add emit in
          left_len + push_len + right_len + add_len
      | ESub pair2 ->
          let (left, right) = pair2 in
          let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
          let push_len = emit_push emit in
          let right_len = emit_expr (right, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
          let sub_len = emit_sub emit in
          left_len + push_len + right_len + sub_len
      | EMore2 more2 ->
          match more2 with
            EMul pair2 ->
              let (left, right) = pair2 in
              let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
              let push_len = emit_push emit in
              let right_len = emit_expr (right, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
              let mul_len = emit_mul emit in
              left_len + push_len + right_len + mul_len
          | EDiv pair2 ->
              let (left, right) = pair2 in
              let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
              let push_len = emit_push emit in
              let right_len = emit_expr (right, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
              let div_len = emit_div emit in
              left_len + push_len + right_len + div_len
          | EEq pair2 ->
              let (left, right) = pair2 in
              let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
              let push_len = emit_push emit in
              let right_len = emit_expr (right, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
              let eq_len = emit_eq emit in
              left_len + push_len + right_len + eq_len
          | EMore3 more3 ->
              match more3 with
                ENe pair2 ->
                  let (left, right) = pair2 in
                  let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                  let push_len = emit_push emit in
                  let right_len = emit_expr (right, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                  let ne_len = emit_ne emit in
                  left_len + push_len + right_len + ne_len
              | ELt pair2 ->
                  let (left, right) = pair2 in
                  let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                  let push_len = emit_push emit in
                  let right_len = emit_expr (right, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                  let lt_len = emit_lt emit in
                  left_len + push_len + right_len + lt_len
                | ELe pair2 ->
                    let (left, right) = pair2 in
                    let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                    let push_len = emit_push emit in
                    let right_len = emit_expr (right, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                    let le_len = emit_le emit in
                    left_len + push_len + right_len + le_len
              | EMore4 more4 ->
                  match more4 with
                    EGt pair2 ->
                      let (left, right) = pair2 in
                      let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                      let push_len = emit_push emit in
                      let right_len = emit_expr (right, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                      let gt_len = emit_gt emit in
                      left_len + push_len + right_len + gt_len
                  | EGe pair2 ->
                      let (left, right) = pair2 in
                      let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                      let push_len = emit_push emit in
                      let right_len = emit_expr (right, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                      let ge_len = emit_ge emit in
                      left_len + push_len + right_len + ge_len
                  | EIf parts ->
                      let (cond, branches) = parts in
                      let (yes, no) = branches in
                      let cond_len = emit_expr (cond, (src, (env, (ctors, (funcs, (base_pos, 0)))))) in
                      let yes_len = emit_expr (yes, (src, (env, (ctors, (funcs, (base_pos, 0)))))) in
                      let no_len = emit_expr (no, (src, (env, (ctors, (funcs, (base_pos, 0)))))) in
                      let _ = if emit == 1 then emit_expr (cond, (src, (env, (ctors, (funcs, (base_pos, 1)))))) else 0 in
                      let _ = emit_branch_if_not (emit, yes_len + 5) in
                      let _ = if emit == 1 then emit_expr (yes, (src, (env, (ctors, (funcs, (base_pos, 1)))))) else 0 in
                      let _ = emit_branch (emit, no_len) in
                      let _ = if emit == 1 then emit_expr (no, (src, (env, (ctors, (funcs, (base_pos, 1)))))) else 0 in
                      cond_len + 5 + yes_len + 5 + no_len
                  | EMore5 more5 ->
                      match more5 with
                        ELet parts ->
                          let (name, body_pair) = parts in
                          let (rhs, body) = body_pair in
                          let rhs_len = emit_expr (rhs, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                          let push_len = emit_push emit in
                          let body_env = bind_env_at_if_named (src, (name, (0, shift_env env))) in
                          let body_len = emit_expr (body, (src, (body_env, (ctors, (funcs, (base_pos + rhs_len + push_len, emit)))))) in
                          let pop_len = emit_pop1 emit in
                          rhs_len + push_len + body_len + pop_len
                      | EPair parts ->
                          let (left, right) = parts in
                          let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                          let push_len = emit_push emit in
                          let right_len = emit_expr (right, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                          let pair_len = emit_makeblock_pair emit in
                          left_len + push_len + right_len + pair_len
                      | ELetPair parts ->
                          let (name1, rest1) = parts in
                          let (name2, rest2) = rest1 in
                          let (rhs, body) = rest2 in
                          let rhs_len = emit_expr (rhs, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                          let save_pair = emit_push emit in
                          let acc_pair0 = emit_acc (emit, 0) in
                          let get_left = emit_getfield (emit, 0) in
                          let push_left = emit_push emit in
                          let acc_pair1 = emit_acc (emit, 1) in
                          let get_right = emit_getfield (emit, 1) in
                          let push_right = emit_push emit in
                          let body_base = shift_env (shift_env (shift_env env)) in
                          let body_env1 = bind_env_at_if_named (src, (name1, (1, body_base))) in
                          let body_env = bind_env_at_if_named (src, (name2, (0, body_env1))) in
                          let body_len = emit_expr (body, (src, (body_env, (ctors, (funcs, (base_pos + rhs_len + save_pair + acc_pair0 + get_left + push_left + acc_pair1 + get_right + push_right, emit)))))) in
                          let pop_len = emit_pop (emit, 3) in
                          rhs_len + save_pair + acc_pair0 + get_left + push_left + acc_pair1 + get_right + push_right + body_len + pop_len
                      | EMore6 more6 ->
                          match more6 with
                            ESeq parts ->
                              let (left, right) = parts in
                              let left_len = emit_expr (left, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                              let right_len = emit_expr (right, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                              left_len + right_len
                          | EDebugByte expr ->
                              let expr_len = emit_expr (expr, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                              let call_len = emit_call_debug_byte emit in
                              expr_len + call_len
                          | EExit expr ->
                              let expr_len = emit_expr (expr, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                              let call_len = emit_call_exit emit in
                              expr_len + call_len
                            | EReadByte -> emit_call_read_byte emit
                            | EMore7 more7 ->
                                match more7 with
                                  EString pos -> emit_string_literal (src, (pos, emit))
                                  | EStringLength expr ->
                                      let expr_len = emit_expr (expr, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                      let size_len = emit_blocksize emit in
                                      expr_len + size_len
                                  | EBytesCreate expr ->
                                      let expr_len = emit_expr (expr, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                      let push_len = emit_push emit in
                                      let const_len = emit_const (emit, 0) in
                                      let block_len = emit_makeblock_dyn emit in
                                      expr_len + push_len + const_len + block_len
                                  | EMore8 more8 ->
                                      match more8 with
                                        EBytesLength expr ->
                                          let expr_len = emit_expr (expr, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                          let size_len = emit_blocksize emit in
                                          expr_len + size_len
                                      | EIndex parts ->
                                          let (base, index) = parts in
                                          let base_len = emit_expr (base, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                          let push_base = emit_push emit in
                                          let index_len = emit_expr (index, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                                          let get_len = emit_getfield_dyn emit in
                                          base_len + push_base + index_len + get_len
                                      | ESetIndex parts ->
                                          let (base, rest) = parts in
                                          let (index, value) = rest in
                                          let base_len = emit_expr (base, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                          let push_base = emit_push emit in
                                          let index_len = emit_expr (index, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                                          let push_index = emit_push emit in
                                          let value_len = emit_expr (value, (src, (shift_env (shift_env env), (ctors, (funcs, (base_pos, emit)))))) in
                                          let set_len = emit_setfield_dyn emit in
                                          base_len + push_base + index_len + push_index + value_len + set_len
                                      | EMore9 more9 ->
                                          match more9 with
                                            EDebugInt expr ->
                                              let expr_len = emit_expr (expr, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                              let call_len = emit_call_debug_int emit in
                                              expr_len + call_len
                                          | EUnit -> emit_const (emit, 0)
                                          | EMore10 more10 ->
                                              match more10 with
                                                ECellCreate expr ->
                                                  let expr_len = emit_expr (expr, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                                  let block_len = emit_makeblock (emit, 1) in
                                                  expr_len + block_len
                                              | ECellGet expr ->
                                                  let expr_len = emit_expr (expr, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                                  let field_len = emit_getfield (emit, 0) in
                                                  expr_len + field_len
                                              | ECellSet parts ->
                                                  let (cell, value) = parts in
                                                  let cell_len = emit_expr (cell, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                                  let push_cell = emit_push emit in
                                                  let value_len = emit_expr (value, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                                                  let set_len = emit_setfield (emit, 0) in
                                                  cell_len + push_cell + value_len + set_len
                                              | EArrayCreate parts ->
                                                  let (size, init) = parts in
                                                  let size_len = emit_expr (size, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                                  let push_len = emit_push emit in
                                                  let init_len = emit_expr (init, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                                                  let block_len = emit_makeblock_dyn emit in
                                                  size_len + push_len + init_len + block_len
                                              | ELetRec parts ->
                                                  let (count, payload) = parts in
                                                  if count == 1 then
                                                    let (name, rest1) = payload in
                                                    let (param, rest2) = rest1 in
                                                    let (fn_body, body) = rest2 in
                                                    let fn_env = extend_env (param, env) in
                                                    let target = base_pos + 5 in
                                                    let next_funcs = extend_fenv (name, (target, funcs)) in
                                                    let fn_body_len = emit_expr (fn_body, (src, (fn_env, (ctors, (next_funcs, (target + 1, 0)))))) in
                                                    let fn_total = 1 + fn_body_len + 5 + 1 in
                                                    let body_len = emit_expr (body, (src, (env, (ctors, (next_funcs, (base_pos + 5 + fn_total, 0)))))) in
                                                    let _ =
                                                      if emit == 1 then
                                                        let _ = emit_branch (1, fn_total) in
                                                        let _ = emit_push 1 in
                                                        let _ = emit_expr (fn_body, (src, (fn_env, (ctors, (next_funcs, (target + 1, 1)))))) in
                                                        let _ = emit_pop1 1 in
                                                        let _ = emit_return 1 in
                                                        emit_expr (body, (src, (env, (ctors, (next_funcs, (base_pos + 5 + fn_total, 1))))))
                                                      else 0
                                                    in
                                                    5 + fn_total + body_len
                                                  else if count == 2 then
                                                    let (name1, rest1) = payload in
                                                    let (param1, rest2) = rest1 in
                                                    let (body1, rest3) = rest2 in
                                                    let (name2, rest4) = rest3 in
                                                    let (param2, rest5) = rest4 in
                                                    let (body2, final) = rest5 in
                                                    let env1 = extend_env (param1, env) in
                                                    let env2 = extend_env (param2, env) in
                                                    let target1 = base_pos + 5 in
                                                    let funcs1 = extend_fenv (name1, (target1, funcs)) in
                                                    let body1_len = emit_expr (body1, (src, (env1, (ctors, (funcs1, (target1 + 1, 0)))))) in
                                                    let total1 = 1 + body1_len + 5 + 1 in
                                                    let target2 = target1 + total1 in
                                                    let next_funcs = extend_fenv (name2, (target2, funcs1)) in
                                                    let body2_len = emit_expr (body2, (src, (env2, (ctors, (next_funcs, (target2 + 1, 0)))))) in
                                                    let total2 = 1 + body2_len + 5 + 1 in
                                                    let final_len = emit_expr (final, (src, (env, (ctors, (next_funcs, (base_pos + 5 + total1 + total2, 0)))))) in
                                                    let _ =
                                                      if emit == 1 then
                                                        let _ = emit_branch (1, total1 + total2) in
                                                        let _ = emit_push 1 in
                                                        let _ = emit_expr (body1, (src, (env1, (ctors, (next_funcs, (target1 + 1, 1)))))) in
                                                        let _ = emit_pop1 1 in
                                                        let _ = emit_return 1 in
                                                        let _ = emit_push 1 in
                                                        let _ = emit_expr (body2, (src, (env2, (ctors, (next_funcs, (target2 + 1, 1)))))) in
                                                        let _ = emit_pop1 1 in
                                                        let _ = emit_return 1 in
                                                        emit_expr (final, (src, (env, (ctors, (next_funcs, (base_pos + 5 + total1 + total2, 1))))))
                                                      else 0
                                                    in
                                                    5 + total1 + total2 + final_len
                                                  else if count == 3 then
                                                    let (name1, rest1) = payload in
                                                    let (param1, rest2) = rest1 in
                                                    let (body1, rest3) = rest2 in
                                                    let (name2, rest4) = rest3 in
                                                    let (param2, rest5) = rest4 in
                                                    let (body2, rest6) = rest5 in
                                                    let (name3, rest7) = rest6 in
                                                    let (param3, rest8) = rest7 in
                                                    let (body3, final) = rest8 in
                                                    let env1 = extend_env (param1, env) in
                                                    let env2 = extend_env (param2, env) in
                                                    let env3 = extend_env (param3, env) in
                                                    let target1 = base_pos + 5 in
                                                    let funcs1 = extend_fenv (name1, (target1, funcs)) in
                                                    let body1_len = emit_expr (body1, (src, (env1, (ctors, (funcs1, (target1 + 1, 0)))))) in
                                                    let total1 = 1 + body1_len + 5 + 1 in
                                                    let target2 = target1 + total1 in
                                                    let funcs2 = extend_fenv (name2, (target2, funcs1)) in
                                                    let body2_len = emit_expr (body2, (src, (env2, (ctors, (funcs2, (target2 + 1, 0)))))) in
                                                    let total2 = 1 + body2_len + 5 + 1 in
                                                    let target3 = target2 + total2 in
                                                    let next_funcs = extend_fenv (name3, (target3, funcs2)) in
                                                    let body3_len = emit_expr (body3, (src, (env3, (ctors, (next_funcs, (target3 + 1, 0)))))) in
                                                    let total3 = 1 + body3_len + 5 + 1 in
                                                    let final_len = emit_expr (final, (src, (env, (ctors, (next_funcs, (base_pos + 5 + total1 + total2 + total3, 0)))))) in
                                                    let _ =
                                                      if emit == 1 then
                                                        let _ = emit_branch (1, total1 + total2 + total3) in
                                                        let _ = emit_push 1 in
                                                        let _ = emit_expr (body1, (src, (env1, (ctors, (next_funcs, (target1 + 1, 1)))))) in
                                                        let _ = emit_pop1 1 in
                                                        let _ = emit_return 1 in
                                                        let _ = emit_push 1 in
                                                        let _ = emit_expr (body2, (src, (env2, (ctors, (next_funcs, (target2 + 1, 1)))))) in
                                                        let _ = emit_pop1 1 in
                                                        let _ = emit_return 1 in
                                                        let _ = emit_push 1 in
                                                        let _ = emit_expr (body3, (src, (env3, (ctors, (next_funcs, (target3 + 1, 1)))))) in
                                                        let _ = emit_pop1 1 in
                                                        let _ = emit_return 1 in
                                                        emit_expr (final, (src, (env, (ctors, (next_funcs, (base_pos + 5 + total1 + total2 + total3, 1))))))
                                                      else 0
                                                    in
                                                    5 + total1 + total2 + total3 + final_len
                                                  else fail 0
                                              | EMore11 more11 ->
                                                  match more11 with
                                                    ECall parts ->
                                                      let (name, arg) = parts in
                                                      let arg_len = emit_expr (arg, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                                      let target =
                                                        if emit == 1 then lookup_fenv (src, (funcs, name)) else 0
                                                      in
                                                      let call_len = emit_call (emit, target) in
                                                      arg_len + call_len
                                                  | EConstr name ->
                                                      let packed = lookup_ctor (src, (ctors, name)) in
                                                      if ctor_has_arg packed == 1 then fail 0 else
                                                        emit_makeblock_tag (emit, (ctor_tag packed, 0))
                                                  | EConstrArg parts ->
                                                      let (name, arg) = parts in
                                                      let packed = lookup_ctor (src, (ctors, name)) in
                                                      if ctor_has_arg packed == 0 then fail 0 else
                                                        let arg_len = emit_expr (arg, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                                        let block_len = emit_makeblock_tag (emit, (ctor_tag packed, 1)) in
                                                        arg_len + block_len
                                                  | EMatch parts ->
                                                      let (scrutinee, cases) = parts in
                                                      let scrutinee_len = emit_expr (scrutinee, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                                      let push_scrutinee = emit_push emit in
                                                      let cases_len = emit_match_cases (cases, (src, (env, (ctors, (funcs, (base_pos + scrutinee_len + push_scrutinee, emit)))))) in
                                                      scrutinee_len + push_scrutinee + cases_len
                                                  | ERecord parts ->
                                                      let (field1, rest1) = parts in
                                                      let (value1, rest2) = rest1 in
                                                      let (field2, value2) = rest2 in
                                                      let field1_info = lookup_ctor (src, (ctors, field1)) in
                                                      let field2_info = lookup_ctor (src, (ctors, field2)) in
                                                      let _ = if ctor_is_field field1_info == 1 then 0 else fail 0 in
                                                      let _ = if ctor_is_field field2_info == 1 then 0 else fail 0 in
                                                      let _ = if field_index field1_info == 0 then 0 else fail 0 in
                                                      let _ = if field_index field2_info == 1 then 0 else fail 0 in
                                                      let value1_len = emit_expr (value1, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                                      let push1 = emit_push emit in
                                                      let value2_len = emit_expr (value2, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                                                      let block_len = emit_makeblock (emit, 2) in
                                                      value1_len + push1 + value2_len + block_len
                                                  | ERecord3 parts ->
                                                      let (field1, rest1) = parts in
                                                      let (value1, rest2) = rest1 in
                                                      let (field2, rest3) = rest2 in
                                                      let (value2, rest4) = rest3 in
                                                      let (field3, value3) = rest4 in
                                                      let field1_info = lookup_ctor (src, (ctors, field1)) in
                                                      let field2_info = lookup_ctor (src, (ctors, field2)) in
                                                      let field3_info = lookup_ctor (src, (ctors, field3)) in
                                                      let _ = if ctor_is_field field1_info == 1 then 0 else fail 0 in
                                                      let _ = if ctor_is_field field2_info == 1 then 0 else fail 0 in
                                                      let _ = if ctor_is_field field3_info == 1 then 0 else fail 0 in
                                                      let _ = if field_index field1_info == 0 then 0 else fail 0 in
                                                      let _ = if field_index field2_info == 1 then 0 else fail 0 in
                                                      let _ = if field_index field3_info == 2 then 0 else fail 0 in
                                                      let value1_len = emit_expr (value1, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                                      let push1 = emit_push emit in
                                                      let value2_len = emit_expr (value2, (src, (shift_env env, (ctors, (funcs, (base_pos, emit)))))) in
                                                      let push2 = emit_push emit in
                                                      let value3_len = emit_expr (value3, (src, (shift_env (shift_env env), (ctors, (funcs, (base_pos, emit)))))) in
                                                      let block_len = emit_makeblock (emit, 3) in
                                                      value1_len + push1 + value2_len + push2 + value3_len + block_len
                                                  | EField parts ->
                                                      let (base, field) = parts in
                                                      let field_info = lookup_ctor (src, (ctors, field)) in
                                                      let _ = if ctor_is_field field_info == 1 then 0 else fail 0 in
                                                      let base_len = emit_expr (base, (src, (env, (ctors, (funcs, (base_pos, emit)))))) in
                                                      let get_len = emit_getfield (emit, field_index field_info) in
                                                      base_len + get_len
and emit_match_cases state =
  let (cases, rest0) = state in
  let (src, rest1) = rest0 in
  let (env, rest2) = rest1 in
  let (ctors, rest3) = rest2 in
  let (funcs, rest4) = rest3 in
  let (base_pos, emit) = rest4 in
  match cases with
    MatchEnd -> fail 0
  | MatchCase parts ->
      let (case_name, rest5) = parts in
      let (case_bind_kind, rest6) = rest5 in
      let (case_bind, rest7) = rest6 in
      let (case_bind2, rest8) = rest7 in
      let (case_body, case_tail) = rest8 in
      let is_final =
        match case_tail with
          MatchEnd -> 1
        | MatchCase tail_parts -> let _ = tail_parts in 0
      in
      let case_found =
        if is_final == 1 then
          if is_upper (src.[case_name]) == 1 then find_ctor (src, (ctors, case_name)) else 0 - 1
        else
          if is_upper (src.[case_name]) == 1 then lookup_ctor (src, (ctors, case_name)) else fail 0
      in
      let case_has_arg = if case_found < 0 then 0 else ctor_has_arg case_found in
      let case_env =
        if is_final == 1 then
          if case_found < 0 then
            let _ = if case_bind_kind == 0 then 0 else fail 0 in
            match_fallback_env (src, (case_name, env))
          else
            match_case_env (src, (case_has_arg, (case_bind_kind, (case_bind, (case_bind2, env)))))
        else
          match_case_env (src, (case_has_arg, (case_bind_kind, (case_bind, (case_bind2, env)))))
      in
      let test_len = if is_final == 1 then 0 else 18 in
      let case_payload_len = emit_match_payload (0, (case_has_arg, case_bind_kind)) in
      let case_body_len = emit_expr (case_body, (src, (case_env, (ctors, (funcs, (base_pos + test_len + case_payload_len, 0)))))) in
      let case_pop_len = emit_match_pop (0, (case_has_arg, case_bind_kind)) in
      let case_total = case_payload_len + case_body_len + case_pop_len in
      if is_final == 1 then
        let _ =
          if emit == 1 then
            let _ = emit_match_payload (1, (case_has_arg, case_bind_kind)) in
            let _ = emit_expr (case_body, (src, (case_env, (ctors, (funcs, (base_pos + case_payload_len, 1)))))) in
            emit_match_pop (1, (case_has_arg, case_bind_kind))
          else 0
        in
        case_total
      else
        let tail_base = base_pos + 18 + case_total + 5 in
        let tail_len = emit_match_cases (case_tail, (src, (env, (ctors, (funcs, (tail_base, 0)))))) in
        let _ =
          if emit == 1 then
            let _ = emit_acc (1, 0) in
            let _ = emit_gettag 1 in
            let _ = emit_push 1 in
            let _ = emit_const (1, ctor_tag case_found) in
            let _ = emit_eq 1 in
            let _ = emit_branch_if_not (1, case_total + 5) in
            let _ = emit_match_payload (1, (case_has_arg, case_bind_kind)) in
            let _ = emit_expr (case_body, (src, (case_env, (ctors, (funcs, (base_pos + 18 + case_payload_len, 1)))))) in
            let _ = emit_match_pop (1, (case_has_arg, case_bind_kind)) in
            let _ = emit_branch (1, tail_len) in
            emit_match_cases (case_tail, (src, (env, (ctors, (funcs, (tail_base, 1))))))
          else 0
        in
        18 + case_total + 5 + tail_len
in
let rec emit_program src =
  let parsed_types = parse_type_decls (src, (0, (0, (empty_tnames 0, (empty_tenv 0, empty_ctors 0))))) in
  let (body_pos, envs) = parsed_types in
  let (tenv, ctors) = envs in
  let parsed = parse_program (src, body_pos) in
  let (ast, pos) = parsed in
  let done_pos = skip_space (src, pos) in
  let _ = if src.[done_pos] == 0 then 0 else fail 0 in
  let _ = need_ty (infer (src, (tenv, ast)), TyUnit) in
  let code_len = emit_expr (ast, (src, (empty_env 0, (ctors, (empty_fenv 0, (0, 0)))))) in
  let _ = emit_header (code_len + 1) in
  let _ = emit_expr (ast, (src, (empty_env 0, (ctors, (empty_fenv 0, (0, 1)))))) in
  write_byte 0
in
let rec read_all state =
  let (buf, pos) = state in
  let ch = read_byte in
  if ch < 0 then pos else
    let _ = buf.[pos] <- ch in
    read_all (buf, pos + 1)
in
let source = Bytes.create 196608 in
let _ = read_all (source, 0) in
emit_program source
