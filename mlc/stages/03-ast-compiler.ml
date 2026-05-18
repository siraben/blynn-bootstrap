type ty = TyInt | TyUnit | TyBool | TyPair of ty
type expr = EInt of int | EVar of int | EBool of int | EMore of expr_more
type expr_more = EWriteByte of expr | EAdd of expr | EEq of expr | EMore2 of expr_more2
type expr_more2 = EIf of expr | ELet of expr | EPair of expr | EMore3 of expr_more3
type expr_more3 = ELetPair of expr | ESeq of expr
type parse_reply = ParseOk of int | ParseErr

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
  let _ = emit_u32 3 in
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
let rec emit_eq emit =
  let _ = emit_byte_if (emit, 9) in
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
let rec emit_makeblock_pair emit =
  let _ = emit_byte_if (emit, 15) in
  let _ = emit_u32_if (emit, 0) in
  let _ = emit_u32_if (emit, 2) in
  9
in
let rec emit_getfield state =
  let (emit, index) = state in
  let _ = emit_byte_if (emit, 16) in
  let _ = emit_u32_if (emit, index) in
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
let rec p_force reply =
  match reply with
    ParseOk pos -> pos
  | ParseErr -> exit 1
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
let rec p_need_keyword state =
  let (src, pair) = state in
  let (pos0, text) = pair in
  let pos = skip_space (src, pos0) in
  if p_keyword_at (src, (pos, text)) == 1 then pos + String.length text else exit 1
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
let rec is_true_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "true"))
in
let rec is_false_at state =
  let (src, pos0) = state in
  p_keyword_at (src, (pos0, "false"))
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
  if is_digit ch then parse_number_loop (src, (pos + 1, ch - '0')) else exit 1
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
let rec parse_expr_flag state =
  let (src, pair0) = state in
  let (pos0, allow_seq) = pair0 in
  let pos = skip_space (src, pos0) in
  let left =
    if is_if_at (src, pos) then
      let cond = parse_expr_flag (src, (pos + 2, 1)) in
      let (cond_ast, cond_end) = cond in
      let then_pos = need_then (src, cond_end) in
      let yes = parse_expr_flag (src, (then_pos, 1)) in
      let (yes_ast, yes_end) = yes in
      let else_pos = need_else (src, yes_end) in
      let no = parse_expr_flag (src, (else_pos, 1)) in
      let (no_ast, no_end) = no in
      (EMore (EMore2 (EIf (cond_ast, (yes_ast, no_ast)))), no_end)
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
        let rhs = parse_expr_flag (src, (eq_pos, 1)) in
        let (rhs_ast, rhs_end) = rhs in
        let body_pos = need_in (src, rhs_end) in
        let body = parse_expr_flag (src, (body_pos, 1)) in
        let (body_ast, body_end) = body in
        (EMore (EMore2 (EMore3 (ELetPair (name1_hash, (name2_hash, (rhs_ast, body_ast)))))), body_end)
      else
        let ident = parse_ident (src, bind_pos) in
        let (name, name_end) = ident in
        let eq_pos = need_char (src, (name_end, '=')) in
        let rhs = parse_expr_flag (src, (eq_pos, 1)) in
        let (rhs_ast, rhs_end) = rhs in
        let body_pos = need_in (src, rhs_end) in
        let body = parse_expr_flag (src, (body_pos, 1)) in
        let (body_ast, body_end) = body in
        (EMore (EMore2 (ELet (name, (rhs_ast, body_ast)))), body_end)
    else if is_write_byte_at (src, pos) then
      let expr_pos = need_write_byte (src, pos) in
      let expr = parse_expr_flag (src, (expr_pos, 0)) in
      let (expr_ast, expr_end) = expr in
      (EMore (EWriteByte expr_ast), expr_end)
    else
      let peeked = p_peek (src, pos) in
      let (ch, atom_pos) = peeked in
      if ch == '(' then
        let expr = parse_expr_flag (src, (atom_pos + 1, 1)) in
        let (ast, expr_end) = expr in
        let after_first = skip_space (src, expr_end) in
        if src.[after_first] == ',' then
          let right = parse_expr_flag (src, (after_first + 1, 1)) in
          let (right_ast, right_end) = right in
          p_return (p_need_char (src, (right_end, ')')), EMore (EMore2 (EPair (ast, right_ast))))
        else
          p_return (p_need_char (src, (expr_end, ')')), ast)
      else if is_true_at (src, atom_pos) then
        p_return (atom_pos + 4, EBool 1)
      else if is_false_at (src, atom_pos) then
        p_return (atom_pos + 5, EBool 0)
      else if ch == '\'' then
        p_return (atom_pos + 3, EInt (src.[atom_pos + 1]))
      else if is_digit ch then
        parse_number (src, atom_pos)
      else
        let ident = parse_ident (src, atom_pos) in
        let (name, name_end) = ident in
        p_return (name_end, EVar name)
  in
  let (left_ast, left_end) = left in
  let next = skip_space (src, left_end) in
  if src.[next] == '+' then
    let right = parse_expr_flag (src, (next + 1, allow_seq)) in
    let (right_ast, right_end) = right in
    (EMore (EAdd (left_ast, right_ast)), right_end)
  else if (src.[next] == '=') * (src.[next + 1] == '=') then
    let right = parse_expr_flag (src, (next + 2, allow_seq)) in
    let (right_ast, right_end) = right in
    (EMore (EEq (left_ast, right_ast)), right_end)
  else if allow_seq == 1 then
    if src.[next] == ';' then
      let right = parse_expr_flag (src, (next + 1, 1)) in
      let (right_ast, right_end) = right in
      (EMore (EMore2 (EMore3 (ESeq (left_ast, right_ast)))), right_end)
    else
      left
  else
    left
in
let rec parse_expr state =
  let (src, pos0) = state in
  parse_expr_flag (src, (pos0, 1))
in
let rec parse_program state =
  let (src, pos0) = state in
  parse_expr (src, pos0)
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
  if head < 0 then exit 1 else lookup_tenv (tail, name)
in
let rec same_ty state =
  let (left, right) = state in
  match left with
    TyInt -> (match right with TyInt -> 1 | TyUnit -> 0 | TyBool -> 0)
  | TyUnit -> (match right with TyInt -> 0 | TyUnit -> 1 | TyBool -> 0)
  | TyBool -> (match right with TyInt -> 0 | TyUnit -> 0 | TyBool -> 1)
  | TyPair left_pair ->
      match right with
        TyPair right_pair -> same_ty (left_pair, right_pair)
      | _ -> 0
in
let rec need_ty state =
  let (got, want) = state in
  if same_ty (got, want) == 1 then 0 else exit 1
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
      | EEq pair2 ->
          let (left, right) = pair2 in
          let left_ty = infer (env, left) in
          let _ = need_ty (infer (env, right), left_ty) in
          TyBool
      | EMore2 more2 ->
          match more2 with
            EIf parts ->
              let (cond, branches) = parts in
              let (yes, no) = branches in
              let _ = need_ty (infer (env, cond), TyBool) in
              let yes_ty = infer (env, yes) in
              let _ = need_ty (infer (env, no), yes_ty) in
              yes_ty
          | ELet parts ->
              let (name, body_pair) = parts in
              let (rhs, body) = body_pair in
              let rhs_ty = infer (env, rhs) in
              infer (extend_tenv (name, (rhs_ty, env)), body)
          | EPair parts ->
              let (left, right) = parts in
              TyPair (infer (env, left), infer (env, right))
          | EMore3 more3 ->
              match more3 with
                ELetPair parts ->
                  let (name1, rest1) = parts in
                  let (name2, rest2) = rest1 in
                  let (rhs, body) = rest2 in
                  let rhs_ty = infer (env, rhs) in
                  match rhs_ty with
                    TyPair pair_ty ->
                      let (left_ty, right_ty) = pair_ty in
                      infer (extend_tenv (name2, (right_ty, extend_tenv (name1, (left_ty, env)))), body)
                  | TyInt -> exit 1
                  | TyUnit -> exit 1
                  | TyBool -> exit 1
              | ESeq parts ->
                  let (left, right) = parts in
                  let _ = need_ty (infer (env, left), TyUnit) in
                  infer (env, right)
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
  if name < 0 then exit 1 else lookup_env (tail, want)
in
let rec emit_expr state =
  let (ast, pair) = state in
  let (env, emit) = pair in
  match ast with
    EInt value -> emit_const (emit, value)
  | EVar name -> emit_acc (emit, lookup_env (env, name))
  | EBool value -> emit_const (emit, value)
  | EMore more ->
      match more with
        EWriteByte expr ->
          let expr_len = emit_expr (expr, (env, emit)) in
          let call_len = emit_call_write_byte emit in
          expr_len + call_len
      | EAdd pair2 ->
          let (left, right) = pair2 in
          let left_len = emit_expr (left, (env, emit)) in
          let push_len = emit_push emit in
          let right_len = emit_expr (right, (shift_env env, emit)) in
          let add_len = emit_add emit in
          left_len + push_len + right_len + add_len
      | EEq pair2 ->
          let (left, right) = pair2 in
          let left_len = emit_expr (left, (env, emit)) in
          let push_len = emit_push emit in
          let right_len = emit_expr (right, (shift_env env, emit)) in
          let eq_len = emit_eq emit in
          left_len + push_len + right_len + eq_len
      | EMore2 more2 ->
          match more2 with
            EIf parts ->
              let (cond, branches) = parts in
              let (yes, no) = branches in
              let cond_len = emit_expr (cond, (env, 0)) in
              let yes_len = emit_expr (yes, (env, 0)) in
              let no_len = emit_expr (no, (env, 0)) in
              let _ = if emit == 1 then emit_expr (cond, (env, 1)) else 0 in
              let _ = emit_branch_if_not (emit, yes_len + 5) in
              let _ = if emit == 1 then emit_expr (yes, (env, 1)) else 0 in
              let _ = emit_branch (emit, no_len) in
              let _ = if emit == 1 then emit_expr (no, (env, 1)) else 0 in
              cond_len + 5 + yes_len + 5 + no_len
          | ELet parts ->
              let (name, body_pair) = parts in
              let (rhs, body) = body_pair in
              let rhs_len = emit_expr (rhs, (env, emit)) in
              let push_len = emit_push emit in
              let body_len = emit_expr (body, (extend_env (name, env), emit)) in
              let pop_len = emit_pop1 emit in
              rhs_len + push_len + body_len + pop_len
          | EPair parts ->
              let (left, right) = parts in
              let left_len = emit_expr (left, (env, emit)) in
              let push_len = emit_push emit in
              let right_len = emit_expr (right, (shift_env env, emit)) in
              let pair_len = emit_makeblock_pair emit in
              left_len + push_len + right_len + pair_len
          | EMore3 more3 ->
              match more3 with
                ELetPair parts ->
                  let (name1, rest1) = parts in
                  let (name2, rest2) = rest1 in
                  let (rhs, body) = rest2 in
                  let rhs_len = emit_expr (rhs, (env, emit)) in
                  let save_pair = emit_push emit in
                  let acc_pair0 = emit_acc (emit, 0) in
                  let get_left = emit_getfield (emit, 0) in
                  let push_left = emit_push emit in
                  let acc_pair1 = emit_acc (emit, 1) in
                  let get_right = emit_getfield (emit, 1) in
                  let push_right = emit_push emit in
                  let body_env = extend_env (name2, extend_env (name1, shift_env env)) in
                  let body_len = emit_expr (body, (body_env, emit)) in
                  let pop_len = emit_pop (emit, 3) in
                  rhs_len + save_pair + acc_pair0 + get_left + push_left + acc_pair1 + get_right + push_right + body_len + pop_len
              | ESeq parts ->
                  let (left, right) = parts in
                  let left_len = emit_expr (left, (env, emit)) in
                  let right_len = emit_expr (right, (env, emit)) in
                  left_len + right_len
in
let rec emit_program src =
  let parsed = parse_program (src, 0) in
  let (ast, pos) = parsed in
  let done_pos = skip_space (src, pos) in
  let _ = if src.[done_pos] == 0 then 0 else exit 1 in
  let _ = need_ty (infer (empty_tenv 0, ast), TyUnit) in
  let code_len = emit_expr (ast, (empty_env 0, 0)) in
  let _ = emit_header (code_len + 1) in
  let _ = emit_expr (ast, (empty_env 0, 1)) in
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
