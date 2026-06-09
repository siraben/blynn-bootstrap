(* ccc part 22: constant expressions; port of Hcc.ConstExpr. Used by the
   parser (enum initializers, _Static_assert) and the preprocessor (#if).
   Failure returns None and leaves a message in ce_err. *)

let ce_err = ref (bytes_create 0)

let ce_fail_str msg =
  ce_err := str_to_bytes msg;
  None

let ce_fail_bytes msg =
  ce_err := msg;
  None

let ce_binop_prec op =
  if bytes_eq_str op "||" then 3
  else if bytes_eq_str op "&&" then 4
  else if bytes_eq_str op "|" then 5
  else if bytes_eq_str op "^" then 6
  else if bytes_eq_str op "&" then 7
  else if bytes_eq_str op "==" || bytes_eq_str op "!=" then 8
  else if bytes_eq_str op "<" || bytes_eq_str op "<=" ||
          bytes_eq_str op ">" || bytes_eq_str op ">=" then 9
  else if bytes_eq_str op "<<" || bytes_eq_str op ">>" then 10
  else if bytes_eq_str op "+" || bytes_eq_str op "-" then 11
  else if bytes_eq_str op "*" then 12
  else 0 - 1

let ce_apply_op op a b =
  if bytes_eq_str op "+" then Some (a + b)
  else if bytes_eq_str op "-" then Some (a - b)
  else if bytes_eq_str op "*" then Some (a * b)
  else if bytes_eq_str op "<<" then Some (shift_left_int a (imax 0 b))
  else if bytes_eq_str op ">>" then Some (shift_right_int a (imax 0 b))
  else if bytes_eq_str op "<" then Some (bool_to_int (a < b))
  else if bytes_eq_str op "<=" then Some (bool_to_int (a <= b))
  else if bytes_eq_str op ">" then Some (bool_to_int (a > b))
  else if bytes_eq_str op ">=" then Some (bool_to_int (a >= b))
  else if bytes_eq_str op "==" then Some (bool_to_int (a = b))
  else if bytes_eq_str op "!=" then Some (bool_to_int (a <> b))
  else if bytes_eq_str op "&" then Some (bit_and_int a b)
  else if bytes_eq_str op "^" then Some (bit_xor_int a b)
  else if bytes_eq_str op "|" then Some (bit_or_int a b)
  else if bytes_eq_str op "&&" then Some (bool_to_int (a <> 0 && b <> 0))
  else if bytes_eq_str op "||" then Some (bool_to_int (a <> 0 || b <> 0))
  else None

let rec ce_assoc_lookup name env =
  match env with
  | [] -> None
  | (k, v) :: rest -> if bytes_eq k name then Some v else ce_assoc_lookup name rest

let rec ce_expression minprec env toks =
  match ce_unary env toks with
  | None -> None
  | Some (lhs, rest) -> ce_climb minprec env lhs rest

and ce_climb minprec env lhs toks =
  match toks with
  | [] -> Some (lhs, toks)
  | Tok (_, _, k) :: rest ->
      (match k with
       | TkPunct op ->
           let prec = ce_binop_prec op in
           if prec >= 0 && prec >= minprec then
             (match ce_expression (prec + 1) env rest with
              | None -> None
              | Some (rhs, rest2) ->
                  (match ce_apply_op op lhs rhs with
                   | None ->
                       (let b = buf_new 48 in
                        buf_add_str b "unhandled operator in constant expression: ";
                        buf_add_bytes b op;
                        ce_fail_bytes (buf_take b))
                   | Some v -> ce_climb minprec env v rest2))
           else Some (lhs, toks)
       | _ -> Some (lhs, toks))

and ce_unary env toks =
  match toks with
  | [] -> ce_fail_str "empty constant expression"
  | Tok (_, _, k) :: rest ->
      (match k with
       | TkPunct op ->
           if bytes_eq_str op "!" then
             (match ce_unary env rest with
              | None -> None
              | Some (v, r) -> Some (bool_to_int (v = 0), r))
           else if bytes_eq_str op "+" then ce_unary env rest
           else if bytes_eq_str op "-" then
             (match ce_unary env rest with
              | None -> None
              | Some (v, r) -> Some (0 - v, r))
           else if bytes_eq_str op "~" then
             (match ce_unary env rest with
              | None -> None
              | Some (v, r) -> Some (bit_not_int v, r))
           else ce_primary env toks
       | _ -> ce_primary env toks)

and ce_primary env toks =
  match toks with
  | [] -> ce_fail_str "empty constant expression"
  | Tok (_, _, k) :: rest ->
      (match k with
       | TkPunct p ->
           if bytes_eq_str p "(" then
             (match ce_expression 0 env rest with
              | None -> None
              | Some (v, r) ->
                  (match r with
                   | Tok (_, _, TkPunct p2) :: r2 ->
                       if bytes_eq_str p2 ")" then Some (v, r2)
                       else ce_fail_str "expected close paren in constant expression"
                   | _ -> ce_fail_str "expected close paren in constant expression"))
           else ce_fail_str "unsupported token in constant expression"
       | TkIdent name ->
           if bytes_eq_str name "defined" then ce_defined env rest
           else Some (opt_or (ce_assoc_lookup name env) 0, rest)
       | TkInt text -> Some (parse_int text, rest)
       | TkChar text -> Some (char_value text, rest)
       | _ -> ce_fail_str "unsupported token in constant expression")

and ce_defined _env toks =
  match toks with
  | Tok (_, _, TkPunct p) :: rest ->
      if bytes_eq_str p "(" then
        (match rest with
         | Tok (_, _, TkIdent name) :: Tok (_, _, TkPunct p2) :: r2 ->
             if bytes_eq_str p2 ")" then
               Some (bool_to_int (bytes_length name > 0), r2)
             else ce_fail_str "bad defined operator in #if expression"
         | _ -> ce_fail_str "bad defined operator in #if expression")
      else ce_fail_str "bad defined operator in #if expression"
  | Tok (_, _, TkIdent name) :: rest ->
      Some (bool_to_int (bytes_length name > 0), rest)
  | _ -> ce_fail_str "bad defined operator in #if expression"

(* returns Some (value, trailing tokens) or None with ce_err set *)
let parse_const_expr env toks = ce_expression 0 env toks
