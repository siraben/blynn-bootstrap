type ty = TyInt | TyUnit | TyBool | TyMore of ty_more
type ty_more = TyString | TyBytes | TyPair of ty
type expr = EInt of int | EVar of int | EBool of int | EMore of expr_more
type expr_more = EWriteByte of expr | EAdd of expr | ESub of expr | EMore2 of expr_more2
type expr_more2 = EMul of expr | EDiv of expr | EEq of expr | EMore3 of expr_more3
type expr_more3 = ENe of expr | ELt of expr | ELe of expr | EMore4 of expr_more4
type expr_more4 = EGt of expr | EGe of expr | EIf of expr | EMore5 of expr_more5
type expr_more5 = ELet of expr | EPair of expr | ELetPair of expr | EMore6 of expr_more6
type expr_more6 = ESeq of expr | EDebugByte of expr | EReadByte | EMore7 of expr_more7
type expr_more7 = EString of int | EStringLength of expr | EBytesCreate of expr | EMore8 of expr_more8
type expr_more8 = EBytesLength of expr | EIndex of expr | ESetIndex of expr | EMore9 of expr_more9
type expr_more9 = EDebugInt of expr | EUnit
type parse_reply = ParseOk of int | ParseErr
type expr_option = ExprSome of expr | ExprNone
type pos_option = PosSome of int | PosNone

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
let rec emit_call_read_byte emit =
  let const_len = emit_const (emit, 0) in
  let _ = emit_byte_if (emit, 14) in
  let _ = emit_u32_if (emit, 1) in
  let _ = emit_u32_if (emit, 0) in
  const_len + 9
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
let rec is_string_length_at state =
  let (src, pos0) = state in
  p_string_at (src, (pos0, "String.length"))
in
let rec is_bytes_create_at state =
  let (src, pos0) = state in
  p_string_at (src, (pos0, "Bytes.create"))
in
let rec is_bytes_length_at state =
  let (src, pos0) = state in
  p_string_at (src, (pos0, "Bytes.length"))
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
let rec skip_line state =
  let (src, pos) = state in
  if src.[pos] == 0 then pos else
  if src.[pos] == '\n' then pos + 1 else skip_line (src, pos + 1)
in
let rec skip_type_decls state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  if is_type_at (src, pos) then skip_type_decls (src, skip_line (src, pos)) else pos
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
let rec need_string_length state =
  let (src, pos0) = state in
  p_need_string (src, (pos0, "String.length"))
in
let rec need_bytes_create state =
  let (src, pos0) = state in
  p_need_string (src, (pos0, "Bytes.create"))
in
let rec need_bytes_length state =
  let (src, pos0) = state in
  p_need_string (src, (pos0, "Bytes.length"))
in
let rec parse_number_loop state =
  let (src, pair) = state in
  let (pos, acc) = pair in
  let ch = src.[pos] in
  if is_digit ch then parse_number_loop (src, (pos + 1, (acc * 10) + ch - '0')) else (EInt acc, pos)
in
let rec parse_number state =
  let (src, pos0) = state in
  let pos = skip_space (src, pos0) in
  let ch = src.[pos] in
  if is_digit ch then parse_number_loop (src, (pos + 1, ch - '0')) else fail 0
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
  if is_alpha ch then parse_ident_loop (src, (pos + 1, ch)) else fail 0
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
let rec read_byte_expr unit =
  let _ = unit in
  EMore (EMore2 (EMore3 (EMore4 (EMore5 (EMore6 EReadByte)))))
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
    let ident = parse_ident (src, pos) in
    let (name, name_end) = ident in
    (EVar name, name_end)
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
let rec parse_bytes_length_expr state =
  let (src, pos0) = state in
  let arg_pos = need_bytes_length (src, pos0) in
  let parsed_arg = parse_value_arg (src, arg_pos) in
  let (arg_ast, done_pos) = parsed_arg in
  (bytes_length_expr arg_ast, done_pos)
in
let rec parse_index_suffix state =
  let (src, pair) = state in
  let (base, pos0) = pair in
  let pos = skip_space (src, pos0) in
  if src.[pos] == '.' then
    if src.[pos + 1] == '[' then
      let index = parse_index_expr (src, pos + 2) in
      let (index_ast, index_end) = index in
      let close = p_need_char (src, (index_end, ']')) in
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
      (base, pos0)
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
          let (name1_hash, name1_end0) = name1 in
          let comma = need_char (src, (name1_end0, ',')) in
          let name2 = parse_ident (src, comma) in
          let (name2_hash, name2_end0) = name2 in
          let after_names = need_char (src, (name2_end0, ')')) in
          let eq_pos = need_char (src, (after_names, '=')) in
          let rhs = parse_expr_prec (src, (eq_pos, (1, (0, (0, EInt 0))))) in
          let (rhs_ast, rhs_end) = rhs in
          let body_pos = need_in (src, rhs_end) in
          let body = parse_expr_prec (src, (body_pos, (1, (0, (0, EInt 0))))) in
          let (body_ast, body_end) = body in
          (EMore (EMore2 (EMore3 (EMore4 (EMore5 (ELetPair (name1_hash, (name2_hash, (rhs_ast, body_ast)))))))), body_end)
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
      else if is_bytes_length_at (src, pos) then
        parse_bytes_length_expr (src, pos)
      else if is_read_byte_at (src, pos) then
        p_return (need_read_byte (src, pos), read_byte_expr 0)
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
        else if ch == '\'' then
          parse_char_literal (src, atom_pos)
        else if ch == '"' then
          let parsed_string = parse_string_literal (src, atom_pos) in
          let (string_ast, string_end) = parsed_string in
          parse_index_suffix (src, (string_ast, string_end))
        else if is_digit ch then
          parse_number (src, atom_pos)
        else
          let ident = parse_ident (src, atom_pos) in
          let (name, name_end) = ident in
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
    if src.[bind_pos] == '(' then
      let name1 = parse_ident (src, bind_pos + 1) in
      let (name1_hash, name1_end0) = name1 in
      let comma = need_char (src, (name1_end0, ',')) in
      let name2 = parse_ident (src, comma) in
      let (name2_hash, name2_end0) = name2 in
      let after_names = need_char (src, (name2_end0, ')')) in
      let eq_pos = need_char (src, (after_names, '=')) in
      let rhs = parse_expr_flag (src, (eq_pos, 0)) in
      let (rhs_ast, rhs_end) = rhs in
      let after_rhs = skip_space (src, rhs_end) in
      if is_in_at (src, after_rhs) then ExprSome (parse_expr (src, let_pos)) else
        let body = parse_program (src, after_rhs) in
        let (body_ast, body_end) = body in
        ExprSome (let_pair_expr (name1_hash, (name2_hash, (rhs_ast, body_ast))), body_end)
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
  let (env, name) = state in
  let (head, rest) = env in
  let (typ, tail) = rest in
  if head == name then typ else
  if head < 0 then fail 0 else lookup_tenv (tail, name)
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
      | TyPair left_pair ->
          match right with
            TyMore right_more ->
              (match right_more with TyPair right_pair -> same_ty (left_pair, right_pair) | _ -> 0)
          | _ -> 0
in
let rec need_ty state =
  let (got, want) = state in
  if same_ty (got, want) == 1 then 0 else fail 0
in
let rec infer state =
  let (env, ast) = state in
  match ast with
    EInt value -> let _ = value in TyInt
  | EVar name -> lookup_tenv (env, name)
  | EBool value -> let _ = value in TyBool
  | EMore more ->
      match more with
        EWriteByte expr ->
          let _ = need_ty (infer (env, expr), TyInt) in
          TyUnit
      | EAdd pair ->
          let (left, right) = pair in
          let _ = need_ty (infer (env, left), TyInt) in
          let _ = need_ty (infer (env, right), TyInt) in
          TyInt
      | ESub pair ->
          let (left, right) = pair in
          let _ = need_ty (infer (env, left), TyInt) in
          let _ = need_ty (infer (env, right), TyInt) in
          TyInt
      | EMore2 more2 ->
          match more2 with
            EMul pair ->
              let (left, right) = pair in
              let _ = need_ty (infer (env, left), TyInt) in
              let _ = need_ty (infer (env, right), TyInt) in
              TyInt
          | EDiv pair ->
              let (left, right) = pair in
              let _ = need_ty (infer (env, left), TyInt) in
              let _ = need_ty (infer (env, right), TyInt) in
              TyInt
          | EEq pair2 ->
              let (left, right) = pair2 in
              let left_ty = infer (env, left) in
              let _ = need_ty (infer (env, right), left_ty) in
              TyBool
          | EMore3 more3 ->
              match more3 with
                ENe pair2 ->
                  let (left, right) = pair2 in
                  let left_ty = infer (env, left) in
                  let _ = need_ty (infer (env, right), left_ty) in
                  TyBool
              | ELt pair ->
                  let (left, right) = pair in
                  let _ = need_ty (infer (env, left), TyInt) in
                  let _ = need_ty (infer (env, right), TyInt) in
                  TyBool
              | ELe pair ->
                  let (left, right) = pair in
                  let _ = need_ty (infer (env, left), TyInt) in
                  let _ = need_ty (infer (env, right), TyInt) in
                  TyBool
              | EMore4 more4 ->
                  match more4 with
                    EGt pair ->
                      let (left, right) = pair in
                      let _ = need_ty (infer (env, left), TyInt) in
                      let _ = need_ty (infer (env, right), TyInt) in
                      TyBool
                  | EGe pair ->
                      let (left, right) = pair in
                      let _ = need_ty (infer (env, left), TyInt) in
                      let _ = need_ty (infer (env, right), TyInt) in
                      TyBool
                  | EIf parts ->
                      let (cond, branches) = parts in
                      let (yes, no) = branches in
                      let _ = need_ty (infer (env, cond), TyBool) in
                      let yes_ty = infer (env, yes) in
                      let _ = need_ty (infer (env, no), yes_ty) in
                      yes_ty
                  | EMore5 more5 ->
                      match more5 with
                        ELet parts ->
                          let (name, body_pair) = parts in
                          let (rhs, body) = body_pair in
                          let rhs_ty = infer (env, rhs) in
                          infer (extend_tenv (name, (rhs_ty, env)), body)
                        | EPair parts ->
                            let (left, right) = parts in
                            TyMore (TyPair (infer (env, left), infer (env, right)))
                      | ELetPair parts ->
                          let (name1, rest1) = parts in
                          let (name2, rest2) = rest1 in
                          let (rhs, body) = rest2 in
                          let rhs_ty = infer (env, rhs) in
                          (match rhs_ty with
                            TyMore more ->
                              (match more with
                                TyPair pair_ty ->
                                  let (left_ty, right_ty) = pair_ty in
                                  infer (extend_tenv (name2, (right_ty, extend_tenv (name1, (left_ty, env)))), body)
                              | TyString -> fail 0
                              | TyBytes -> fail 0)
                          | TyInt -> fail 0
                          | TyUnit -> fail 0
                          | TyBool -> fail 0)
                      | EMore6 more6 ->
                          match more6 with
                            ESeq parts ->
                              let (left, right) = parts in
                              let _ = need_ty (infer (env, left), TyUnit) in
                              infer (env, right)
                          | EDebugByte expr ->
                              let _ = need_ty (infer (env, expr), TyInt) in
                              TyUnit
                            | EReadByte -> TyInt
                            | EMore7 more7 ->
                                match more7 with
                                  EString pos -> let _ = pos in TyMore TyString
                                | EStringLength expr ->
                                    let _ = need_ty (infer (env, expr), TyMore TyString) in
                                    TyInt
                                | EBytesCreate expr ->
                                    let _ = need_ty (infer (env, expr), TyInt) in
                                    TyMore TyBytes
                                | EMore8 more8 ->
                                    match more8 with
                                    EBytesLength expr ->
                                      let _ = need_ty (infer (env, expr), TyMore TyBytes) in
                                      TyInt
                                  | EIndex parts ->
                                      let (base, index) = parts in
                                      let base_ty = infer (env, base) in
                                      let _ = need_ty (infer (env, index), TyInt) in
                                      (match base_ty with
                                        TyMore more ->
                                          (match more with
                                            TyString -> TyInt
                                          | TyBytes -> TyInt
                                          | TyPair pair_ty -> let _ = pair_ty in fail 0)
                                      | TyInt -> fail 0
                                      | TyUnit -> fail 0
                                      | TyBool -> fail 0)
                                  | ESetIndex parts ->
                                      let (base, rest) = parts in
                                      let (index, value) = rest in
                                      let _ = need_ty (infer (env, base), TyMore TyBytes) in
                                      let _ = need_ty (infer (env, index), TyInt) in
                                      let _ = need_ty (infer (env, value), TyInt) in
                                      TyUnit
                                  | EMore9 more9 ->
                                      match more9 with
                                        EDebugInt expr ->
                                          let _ = need_ty (infer (env, expr), TyInt) in
                                          TyUnit
                                      | EUnit -> TyUnit
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
  let (env, want) = state in
  let (name, rest) = env in
  let (depth, tail) = rest in
  if name == want then depth else
  if name < 0 then fail 0 else lookup_env (tail, want)
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
  let (env, emit) = pair_src in
  match ast with
    EInt value -> emit_const (emit, value)
  | EVar name -> emit_acc (emit, lookup_env (env, name))
  | EBool value -> emit_const (emit, value)
  | EMore more ->
      match more with
        EWriteByte expr ->
          let expr_len = emit_expr (expr, (src, (env, emit))) in
          let call_len = emit_call_write_byte emit in
          expr_len + call_len
      | EAdd pair2 ->
          let (left, right) = pair2 in
          let left_len = emit_expr (left, (src, (env, emit))) in
          let push_len = emit_push emit in
          let right_len = emit_expr (right, (src, (shift_env env, emit))) in
          let add_len = emit_add emit in
          left_len + push_len + right_len + add_len
      | ESub pair2 ->
          let (left, right) = pair2 in
          let left_len = emit_expr (left, (src, (env, emit))) in
          let push_len = emit_push emit in
          let right_len = emit_expr (right, (src, (shift_env env, emit))) in
          let sub_len = emit_sub emit in
          left_len + push_len + right_len + sub_len
      | EMore2 more2 ->
          match more2 with
            EMul pair2 ->
              let (left, right) = pair2 in
              let left_len = emit_expr (left, (src, (env, emit))) in
              let push_len = emit_push emit in
              let right_len = emit_expr (right, (src, (shift_env env, emit))) in
              let mul_len = emit_mul emit in
              left_len + push_len + right_len + mul_len
          | EDiv pair2 ->
              let (left, right) = pair2 in
              let left_len = emit_expr (left, (src, (env, emit))) in
              let push_len = emit_push emit in
              let right_len = emit_expr (right, (src, (shift_env env, emit))) in
              let div_len = emit_div emit in
              left_len + push_len + right_len + div_len
          | EEq pair2 ->
              let (left, right) = pair2 in
              let left_len = emit_expr (left, (src, (env, emit))) in
              let push_len = emit_push emit in
              let right_len = emit_expr (right, (src, (shift_env env, emit))) in
              let eq_len = emit_eq emit in
              left_len + push_len + right_len + eq_len
          | EMore3 more3 ->
              match more3 with
                ENe pair2 ->
                  let (left, right) = pair2 in
                  let left_len = emit_expr (left, (src, (env, emit))) in
                  let push_len = emit_push emit in
                  let right_len = emit_expr (right, (src, (shift_env env, emit))) in
                  let ne_len = emit_ne emit in
                  left_len + push_len + right_len + ne_len
              | ELt pair2 ->
                  let (left, right) = pair2 in
                  let left_len = emit_expr (left, (src, (env, emit))) in
                  let push_len = emit_push emit in
                  let right_len = emit_expr (right, (src, (shift_env env, emit))) in
                  let lt_len = emit_lt emit in
                  left_len + push_len + right_len + lt_len
                | ELe pair2 ->
                    let (left, right) = pair2 in
                    let left_len = emit_expr (left, (src, (env, emit))) in
                    let push_len = emit_push emit in
                    let right_len = emit_expr (right, (src, (shift_env env, emit))) in
                    let le_len = emit_le emit in
                    left_len + push_len + right_len + le_len
              | EMore4 more4 ->
                  match more4 with
                    EGt pair2 ->
                      let (left, right) = pair2 in
                      let left_len = emit_expr (left, (src, (env, emit))) in
                      let push_len = emit_push emit in
                      let right_len = emit_expr (right, (src, (shift_env env, emit))) in
                      let gt_len = emit_gt emit in
                      left_len + push_len + right_len + gt_len
                  | EGe pair2 ->
                      let (left, right) = pair2 in
                      let left_len = emit_expr (left, (src, (env, emit))) in
                      let push_len = emit_push emit in
                      let right_len = emit_expr (right, (src, (shift_env env, emit))) in
                      let ge_len = emit_ge emit in
                      left_len + push_len + right_len + ge_len
                  | EIf parts ->
                      let (cond, branches) = parts in
                      let (yes, no) = branches in
                      let cond_len = emit_expr (cond, (src, (env, 0))) in
                      let yes_len = emit_expr (yes, (src, (env, 0))) in
                      let no_len = emit_expr (no, (src, (env, 0))) in
                      let _ = if emit == 1 then emit_expr (cond, (src, (env, 1))) else 0 in
                      let _ = emit_branch_if_not (emit, yes_len + 5) in
                      let _ = if emit == 1 then emit_expr (yes, (src, (env, 1))) else 0 in
                      let _ = emit_branch (emit, no_len) in
                      let _ = if emit == 1 then emit_expr (no, (src, (env, 1))) else 0 in
                      cond_len + 5 + yes_len + 5 + no_len
                  | EMore5 more5 ->
                      match more5 with
                        ELet parts ->
                          let (name, body_pair) = parts in
                          let (rhs, body) = body_pair in
                          let rhs_len = emit_expr (rhs, (src, (env, emit))) in
                          let push_len = emit_push emit in
                          let body_len = emit_expr (body, (src, (extend_env (name, env), emit))) in
                          let pop_len = emit_pop1 emit in
                          rhs_len + push_len + body_len + pop_len
                      | EPair parts ->
                          let (left, right) = parts in
                          let left_len = emit_expr (left, (src, (env, emit))) in
                          let push_len = emit_push emit in
                          let right_len = emit_expr (right, (src, (shift_env env, emit))) in
                          let pair_len = emit_makeblock_pair emit in
                          left_len + push_len + right_len + pair_len
                      | ELetPair parts ->
                          let (name1, rest1) = parts in
                          let (name2, rest2) = rest1 in
                          let (rhs, body) = rest2 in
                          let rhs_len = emit_expr (rhs, (src, (env, emit))) in
                          let save_pair = emit_push emit in
                          let acc_pair0 = emit_acc (emit, 0) in
                          let get_left = emit_getfield (emit, 0) in
                          let push_left = emit_push emit in
                          let acc_pair1 = emit_acc (emit, 1) in
                          let get_right = emit_getfield (emit, 1) in
                          let push_right = emit_push emit in
                          let body_env = extend_env (name2, extend_env (name1, shift_env env)) in
                          let body_len = emit_expr (body, (src, (body_env, emit))) in
                          let pop_len = emit_pop (emit, 3) in
                          rhs_len + save_pair + acc_pair0 + get_left + push_left + acc_pair1 + get_right + push_right + body_len + pop_len
                      | EMore6 more6 ->
                          match more6 with
                            ESeq parts ->
                              let (left, right) = parts in
                              let left_len = emit_expr (left, (src, (env, emit))) in
                              let right_len = emit_expr (right, (src, (env, emit))) in
                              left_len + right_len
                          | EDebugByte expr ->
                              let expr_len = emit_expr (expr, (src, (env, emit))) in
                              let call_len = emit_call_debug_byte emit in
                              expr_len + call_len
                            | EReadByte -> emit_call_read_byte emit
                            | EMore7 more7 ->
                                match more7 with
                                  EString pos -> emit_string_literal (src, (pos, emit))
                                  | EStringLength expr ->
                                      let expr_len = emit_expr (expr, (src, (env, emit))) in
                                      let size_len = emit_blocksize emit in
                                      expr_len + size_len
                                  | EBytesCreate expr ->
                                      let expr_len = emit_expr (expr, (src, (env, emit))) in
                                      let push_len = emit_push emit in
                                      let const_len = emit_const (emit, 0) in
                                      let block_len = emit_makeblock_dyn emit in
                                      expr_len + push_len + const_len + block_len
                                  | EMore8 more8 ->
                                      match more8 with
                                        EBytesLength expr ->
                                          let expr_len = emit_expr (expr, (src, (env, emit))) in
                                          let size_len = emit_blocksize emit in
                                          expr_len + size_len
                                      | EIndex parts ->
                                          let (base, index) = parts in
                                          let base_len = emit_expr (base, (src, (env, emit))) in
                                          let push_base = emit_push emit in
                                          let index_len = emit_expr (index, (src, (shift_env env, emit))) in
                                          let get_len = emit_getfield_dyn emit in
                                          base_len + push_base + index_len + get_len
                                      | ESetIndex parts ->
                                          let (base, rest) = parts in
                                          let (index, value) = rest in
                                          let base_len = emit_expr (base, (src, (env, emit))) in
                                          let push_base = emit_push emit in
                                          let index_len = emit_expr (index, (src, (shift_env env, emit))) in
                                          let push_index = emit_push emit in
                                          let value_len = emit_expr (value, (src, (shift_env (shift_env env), emit))) in
                                          let set_len = emit_setfield_dyn emit in
                                          base_len + push_base + index_len + push_index + value_len + set_len
                                      | EMore9 more9 ->
                                          match more9 with
                                            EDebugInt expr ->
                                              let expr_len = emit_expr (expr, (src, (env, emit))) in
                                              let call_len = emit_call_debug_int emit in
                                              expr_len + call_len
                                          | EUnit -> emit_const (emit, 0)
in
let rec emit_program src =
  let parsed = parse_program (src, 0) in
  let (ast, pos) = parsed in
  let done_pos = skip_space (src, pos) in
  let _ = if src.[done_pos] == 0 then 0 else fail 0 in
  let _ = need_ty (infer (empty_tenv 0, ast), TyUnit) in
  let code_len = emit_expr (ast, (src, (empty_env 0, 0))) in
  let _ = emit_header (code_len + 1) in
  let _ = emit_expr (ast, (src, (empty_env 0, 1))) in
  write_byte 0
in
let rec read_all state =
  let (buf, pos) = state in
  let ch = read_byte in
  if ch < 0 then pos else
    let _ = buf.[pos] <- ch in
    read_all (buf, pos + 1)
in
let source = Bytes.create 65536 in
let _ = read_all (source, 0) in
emit_program source
