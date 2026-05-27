type token =
  | Ident of string
  | Int_lit of int
  | Char_lit of int
  | String_lit of string
  | Sym of string
  | Eof

exception Compile_error of string
exception Parse_error of string
exception Exit_code of int

let fail msg = raise (Compile_error msg)

let is_space = function ' ' | '\n' | '\r' | '\t' -> true | _ -> false
let is_digit ch = '0' <= ch && ch <= '9'
let is_alpha ch = ch = '_' || ('A' <= ch && ch <= 'Z') || ('a' <= ch && ch <= 'z')
let is_ident ch = is_alpha ch || is_digit ch

let char_code_at src pos =
  if pos >= String.length src then 0 else Char.code src.[pos]

let hex_value ch =
  if '0' <= ch && ch <= '9' then Char.code ch - Char.code '0'
  else if 'A' <= ch && ch <= 'F' then Char.code ch - Char.code 'A' + 10
  else if 'a' <= ch && ch <= 'f' then Char.code ch - Char.code 'a' + 10
  else fail "bad hex digit"

let rec skip_block_comment src pos =
  if pos + 1 >= String.length src then fail "unterminated block comment"
  else if src.[pos] = '*' && src.[pos + 1] = '/' then pos + 2
  else skip_block_comment src (pos + 1)

let rec skip_line src pos =
  if pos >= String.length src then pos
  else if src.[pos] = '\n' then pos + 1
  else skip_line src (pos + 1)

let rec skip_ws src pos =
  if pos >= String.length src then pos
  else if is_space src.[pos] then skip_ws src (pos + 1)
  else if src.[pos] = '#' then skip_ws src (skip_line src (pos + 1))
  else if pos + 1 < String.length src && src.[pos] = '/' && src.[pos + 1] = '*' then
    skip_ws src (skip_block_comment src (pos + 2))
  else if pos + 1 < String.length src && src.[pos] = '/' && src.[pos + 1] = '/' then
    skip_ws src (skip_line src (pos + 2))
  else pos

let parse_escape src pos =
  if pos >= String.length src then fail "unterminated escape";
  match src.[pos] with
  | 'a' -> (7, pos + 1)
  | 'b' -> (8, pos + 1)
  | 'n' -> (10, pos + 1)
  | 'r' -> (13, pos + 1)
  | 't' -> (9, pos + 1)
  | 'x' ->
      let rec loop p acc =
        if p < String.length src && (is_digit src.[p] || ('a' <= src.[p] && src.[p] <= 'f') || ('A' <= src.[p] && src.[p] <= 'F')) then
          loop (p + 1) ((acc * 16) + hex_value src.[p])
        else (acc, p)
      in
      loop (pos + 1) 0
  | ch when '0' <= ch && ch <= '7' ->
      let rec loop p count acc =
        if count < 3 && p < String.length src && '0' <= src.[p] && src.[p] <= '7' then
          loop (p + 1) (count + 1) ((acc * 8) + Char.code src.[p] - Char.code '0')
        else (acc, p)
      in
      loop pos 0 0
  | ch -> (Char.code ch, pos + 1)

let lex_number src pos =
  let len = String.length src in
  let rec suffix p =
    if p < len then
      match src.[p] with
      | 'u' | 'U' | 'l' | 'L' -> suffix (p + 1)
      | _ -> p
    else p
  in
  if pos + 1 < len && src.[pos] = '0' && (src.[pos + 1] = 'x' || src.[pos + 1] = 'X') then
    let rec loop p acc =
      if p < len && (is_digit src.[p] || ('a' <= src.[p] && src.[p] <= 'f') || ('A' <= src.[p] && src.[p] <= 'F')) then
        loop (p + 1) ((acc * 16) + hex_value src.[p])
      else (Int_lit acc, suffix p)
    in
    loop (pos + 2) 0
  else
    let rec loop p acc =
      if p < len && is_digit src.[p] then
        loop (p + 1) ((acc * 10) + Char.code src.[p] - Char.code '0')
      else (Int_lit acc, suffix p)
    in
    loop pos 0

let lex_char src pos =
  let value, pos1 =
    if pos + 1 < String.length src && src.[pos + 1] = '\\' then parse_escape src (pos + 2)
    else (char_code_at src (pos + 1), pos + 2)
  in
  if pos1 >= String.length src || src.[pos1] <> '\'' then fail "unterminated char literal";
  (Char_lit value, pos1 + 1)

let lex_string src pos =
  let b = Buffer.create 16 in
  let rec loop p =
    if p >= String.length src then fail "unterminated string literal"
    else if src.[p] = '"' then (String_lit (Buffer.contents b), p + 1)
    else if src.[p] = '\\' then
      let value, next = parse_escape src (p + 1) in
      Buffer.add_char b (Char.chr (value land 255));
      loop next
    else (
      Buffer.add_char b src.[p];
      loop (p + 1))
  in
  loop (pos + 1)

let multi_symbols =
  [ "=="; "!="; "<="; ">="; "&&"; "||"; "<<"; ">>"; "++"; "--"; "+="; "-="; "->" ]

let lex src =
  let rec loop pos acc =
    let pos = skip_ws src pos in
    if pos >= String.length src then List.rev (Eof :: acc)
    else
      let ch = src.[pos] in
      if is_alpha ch then
        let rec ident_end p = if p < String.length src && is_ident src.[p] then ident_end (p + 1) else p in
        let stop = ident_end (pos + 1) in
        loop stop (Ident (String.sub src pos (stop - pos)) :: acc)
      else if is_digit ch then
        let tok, next = lex_number src pos in
        loop next (tok :: acc)
      else if ch = '\'' then
        let tok, next = lex_char src pos in
        loop next (tok :: acc)
      else if ch = '"' then
        let tok, next = lex_string src pos in
        loop next (tok :: acc)
      else
        let found =
          List.find_opt
            (fun op -> pos + String.length op <= String.length src && String.sub src pos (String.length op) = op)
            multi_symbols
        in
        match found with
        | Some op -> loop (pos + String.length op) (Sym op :: acc)
        | None -> loop (pos + 1) (Sym (String.make 1 ch) :: acc)
  in
  Array.of_list (loop 0 [])

type parser_state = { tokens : token array; pos : int }
type 'a parser = parser_state -> ('a * parser_state, string) result

let return value state = Ok (value, state)
let bind parser next state = match parser state with Ok (value, state') -> next value state' | Error msg -> Error msg
let ( let* ) = bind

let peek state =
  if state.pos < Array.length state.tokens then state.tokens.(state.pos) else Eof

let advance state = { state with pos = state.pos + 1 }

let satisfy f expected state =
  match f (peek state) with
  | Some value -> Ok (value, advance state)
  | None -> Error expected

let expect_sym text =
  satisfy (function Sym got when got = text -> Some () | _ -> None) ("expected " ^ text)

let expect_ident =
  satisfy (function Ident name -> Some name | _ -> None) "expected identifier"

let optional parser state =
  match parser state with Ok (value, state') -> Ok (Some value, state') | Error _ -> Ok (None, state)

let run parser tokens =
  match parser { tokens; pos = 0 } with
  | Ok (value, _) -> value
  | Error msg -> raise (Parse_error msg)

type c_type = TInt | TChar | TSignedChar | TUnsignedChar | TUnsigned | TVoid | TOther of string | TPtr of c_type

type binop = Add | Sub | Mul | Div | Mod | Eq | Ne | Lt | Le | Gt | Ge | Land | Lor | Shl | Shr
type unop = Neg | Not | Deref | Addr

type expr =
  | EInt of int
  | EVar of string
  | EString of string
  | EUnary of unop * expr
  | EBinary of binop * expr * expr
  | ECall of string * expr list
  | ECast of c_type * expr

type simple_stmt =
  | SExpr of expr
  | SAssign of string * expr
  | SAugAssign of string * binop * expr
  | SPost of string * int
  | SDecl of string * expr option
  | SEmpty

type stmt =
  | Simple of simple_stmt
  | Return of expr option
  | If of expr * stmt * stmt option
  | While of expr * stmt
  | For of simple_stmt option * expr option * simple_stmt option * stmt
  | Goto of string
  | Label of string
  | Block of stmt list

type func = { name : string; params : string list; body : stmt list; ret_type : c_type }
type program = func list

let rec starts_type = function
  | Ident ("int" | "char" | "signed" | "unsigned" | "void" | "long" | "short" | "_Bool" | "static" | "const" | "struct") -> true
  | _ -> false

let rec parse_type state =
  let rec qualifiers st =
    match peek st with
    | Ident ("static" | "const") -> qualifiers (advance st)
    | _ -> st
  in
  let state = qualifiers state in
  let base, state =
    match peek state with
    | Ident "signed" ->
        let st = advance state in
        (match peek st with Ident "char" -> (TSignedChar, advance st) | _ -> (TInt, st))
    | Ident "unsigned" ->
        let st = advance state in
        (match peek st with
        | Ident "char" -> (TUnsignedChar, advance st)
        | Ident ("short" | "long" | "int") -> (TUnsigned, advance st)
        | _ -> (TUnsigned, st))
    | Ident "char" -> (TChar, advance state)
    | Ident "int" -> (TInt, advance state)
    | Ident "void" -> (TVoid, advance state)
    | Ident ("long" | "short" | "_Bool") as tok ->
        (match tok with Ident name -> (TOther name, advance state) | _ -> assert false)
    | Ident "struct" ->
        let st = advance state in
        (match peek st with Ident name -> (TOther ("struct " ^ name), advance st) | _ -> (TOther "struct", st))
    | Ident name -> (TOther name, advance state)
    | _ -> raise (Parse_error "expected type")
  in
  let rec ptr ty st = match peek st with Sym "*" -> ptr (TPtr ty) (advance st) | _ -> (ty, st) in
  ptr base state

let rec parse_expr state = parse_binop 1 state

and parse_primary state =
  match peek state with
  | Int_lit n -> (EInt n, advance state)
  | Char_lit n -> (EInt n, advance state)
  | String_lit s -> (EString s, advance state)
  | Ident name ->
      let state = advance state in
      (match peek state with
      | Sym "(" ->
          let args, state = parse_arg_list (advance state) in
          (ECall (name, args), state)
      | _ -> (EVar name, state))
  | Sym "(" ->
      let state1 = advance state in
      if starts_type (peek state1) then
        let ty, state2 = parse_type state1 in
        let state3 =
          match expect_sym ")" state2 with
          | Ok ((), st) -> st
          | Error msg -> raise (Parse_error msg)
        in
        let rhs, state4 = parse_unary state3 in
        (ECast (ty, rhs), state4)
      else
        let expr, state2 = parse_expr state1 in
        (match expect_sym ")" state2 with
        | Ok ((), state3) -> (expr, state3)
        | Error msg -> raise (Parse_error msg))
  | _ -> raise (Parse_error "expected expression")

and parse_arg_list state =
  match peek state with
  | Sym ")" -> ([], advance state)
  | _ ->
      let rec loop st acc =
        let arg, st = parse_expr st in
        match peek st with
        | Sym "," -> loop (advance st) (arg :: acc)
        | Sym ")" -> (List.rev (arg :: acc), advance st)
        | _ -> raise (Parse_error "expected , or )")
      in
      loop state []

and parse_unary state =
  match peek state with
  | Sym "!" ->
      let rhs, st = parse_unary (advance state) in
      (EUnary (Not, rhs), st)
  | Sym "-" ->
      let rhs, st = parse_unary (advance state) in
      (EUnary (Neg, rhs), st)
  | Sym "*" ->
      let rhs, st = parse_unary (advance state) in
      (EUnary (Deref, rhs), st)
  | Sym "&" ->
      let rhs, st = parse_unary (advance state) in
      (EUnary (Addr, rhs), st)
  | _ -> parse_primary state

and binop_of = function
  | "||" -> Some (Lor, 1)
  | "&&" -> Some (Land, 2)
  | "==" -> Some (Eq, 3)
  | "!=" -> Some (Ne, 3)
  | "<" -> Some (Lt, 4)
  | "<=" -> Some (Le, 4)
  | ">" -> Some (Gt, 4)
  | ">=" -> Some (Ge, 4)
  | "<<" -> Some (Shl, 5)
  | ">>" -> Some (Shr, 5)
  | "+" -> Some (Add, 6)
  | "-" -> Some (Sub, 6)
  | "*" -> Some (Mul, 7)
  | "/" -> Some (Div, 7)
  | "%" -> Some (Mod, 7)
  | _ -> None

and parse_binop min_prec state =
  let lhs, state = parse_unary state in
  parse_binop_tail min_prec lhs state

and parse_binop_tail min_prec lhs state =
  match peek state with
  | Sym op -> (
      match binop_of op with
      | Some (op, prec) when prec >= min_prec ->
          let rhs, state2 = parse_binop (prec + 1) (advance state) in
          parse_binop_tail min_prec (EBinary (op, lhs, rhs)) state2
      | _ -> (lhs, state))
  | _ -> (lhs, state)

let parse_decl_after_type state =
  let name =
    match peek state with
    | Ident name -> name
    | _ -> raise (Parse_error "expected declaration name")
  in
  let state = advance state in
  let state =
    match peek state with
    | Sym "[" ->
        let state = advance state in
        let state =
          match peek state with
          | Sym "]" -> state
          | _ ->
              let _size, state = parse_expr state in
              state
        in
        (match expect_sym "]" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg))
    | _ -> state
  in
  let init, state =
    match peek state with
    | Sym "=" ->
        let expr, state = parse_expr (advance state) in
        (Some expr, state)
    | _ -> (None, state)
  in
  (SDecl (name, init), state)

let parse_simple_no_semi state =
  match peek state with
  | Sym ")" | Sym ";" -> (SEmpty, state)
  | tok when starts_type tok ->
      let _ty, state = parse_type state in
      parse_decl_after_type state
  | Ident name -> (
      let state1 = advance state in
      match peek state1 with
      | Sym "=" ->
          let expr, st = parse_expr (advance state1) in
          (SAssign (name, expr), st)
      | Sym "+=" ->
          let expr, st = parse_expr (advance state1) in
          (SAugAssign (name, Add, expr), st)
      | Sym "-=" ->
          let expr, st = parse_expr (advance state1) in
          (SAugAssign (name, Sub, expr), st)
      | Sym "++" -> (SPost (name, 1), advance state1)
      | Sym "--" -> (SPost (name, -1), advance state1)
      | Sym "(" ->
          let args, st = parse_arg_list (advance state1) in
          (SExpr (ECall (name, args)), st)
      | _ ->
          let expr, st = parse_binop_tail 1 (EVar name) state1 in
          (SExpr expr, st))
  | _ ->
      let expr, st = parse_expr state in
      (SExpr expr, st)

let parse_simple_stmt state =
  let simple, state = parse_simple_no_semi state in
  match expect_sym ";" state with
  | Ok ((), state') -> (simple, state')
  | Error msg -> raise (Parse_error msg)

let rec parse_stmt state =
  match peek state with
  | Sym "{" ->
      let body, state = parse_block (advance state) in
      (Block body, state)
  | Ident "return" ->
      let state = advance state in
      if peek state = Sym ";" then (Return None, advance state)
      else
        let expr, state = parse_expr state in
        (match expect_sym ";" state with Ok ((), st) -> (Return (Some expr), st) | Error msg -> raise (Parse_error msg))
  | Ident "if" ->
      let state = advance state in
      let state = match expect_sym "(" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
      let cond, state = parse_expr state in
      let state = match expect_sym ")" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
      let yes, state = parse_stmt state in
      let else_part =
        match peek state with
        | Ident "else" ->
            let no, st = parse_stmt (advance state) in
            (Some no, st)
        | _ -> (None, state)
      in
      let no, state = else_part in
      (If (cond, yes, no), state)
  | Ident "while" ->
      let state = advance state in
      let state = match expect_sym "(" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
      let cond, state = parse_expr state in
      let state = match expect_sym ")" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
      let body, state = parse_stmt state in
      (While (cond, body), state)
  | Ident "for" ->
      let state = advance state in
      let state = match expect_sym "(" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
      let init, state =
        if peek state = Sym ";" then (None, advance state)
        else
          let s, st = parse_simple_no_semi state in
          let st = match expect_sym ";" st with Ok ((), st') -> st' | Error msg -> raise (Parse_error msg) in
          (Some s, st)
      in
      let cond, state =
        if peek state = Sym ";" then (None, advance state)
        else
          let e, st = parse_expr state in
          let st = match expect_sym ";" st with Ok ((), st') -> st' | Error msg -> raise (Parse_error msg) in
          (Some e, st)
      in
      let post, state =
        if peek state = Sym ")" then (None, advance state)
        else
          let s, st = parse_simple_no_semi state in
          let st = match expect_sym ")" st with Ok ((), st') -> st' | Error msg -> raise (Parse_error msg) in
          (Some s, st)
      in
      let body, state = parse_stmt state in
      (For (init, cond, post, body), state)
  | Ident "goto" ->
      let state = advance state in
      let name = match peek state with Ident name -> name | _ -> raise (Parse_error "expected label") in
      let state = advance state in
      let state = match expect_sym ";" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
      (Goto name, state)
  | Ident name -> (
      match peek (advance state) with
      | Sym ":" -> (Label name, advance (advance state))
      | _ ->
          let simple, state = parse_simple_stmt state in
          (Simple simple, state))
  | Sym ";" -> (Simple SEmpty, advance state)
  | _ ->
      let simple, state = parse_simple_stmt state in
      (Simple simple, state)

and parse_block state =
  match peek state with
  | Sym "}" -> ([], advance state)
  | Eof -> raise (Parse_error "unterminated block")
  | _ ->
      let stmt, state = parse_stmt state in
      let rest, state = parse_block state in
      (stmt :: rest, state)

let parse_params state =
  let state = match expect_sym "(" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
  match peek state with
  | Sym ")" -> ([], advance state)
  | Ident "void" when peek (advance state) = Sym ")" -> ([], advance (advance state))
  | _ ->
      let rec loop st acc =
        let _ty, st = parse_type st in
        let name, st =
          match peek st with
          | Ident name -> (name, advance st)
          | _ -> ("_", st)
        in
        match peek st with
        | Sym "," -> loop (advance st) (name :: acc)
        | Sym ")" -> (List.rev (name :: acc), advance st)
        | _ -> raise (Parse_error "expected , or ) in parameter list")
      in
      loop state []

let rec skip_decl tokens pos depth =
  match tokens.(pos) with
  | Eof -> pos
  | Sym ";" when depth = 0 -> pos + 1
  | Sym "{" -> skip_decl tokens (pos + 1) (depth + 1)
  | Sym "}" when depth > 0 -> skip_decl tokens (pos + 1) (depth - 1)
  | _ -> skip_decl tokens (pos + 1) depth

let parse_function state =
  let ret_type, state = parse_type state in
  let name =
    match peek state with Ident name -> name | _ -> raise (Parse_error "expected function name")
  in
  let state = advance state in
  let params, state = parse_params state in
  match peek state with
  | Sym ";" -> (None, advance state)
  | Sym "{" ->
      let body, state = parse_block (advance state) in
      (Some { name; params; body; ret_type }, state)
  | _ -> raise (Parse_error "expected function body")

let parse_program tokens =
  let rec loop state acc =
    match peek state with
    | Eof -> List.rev acc
    | Ident ("typedef" | "struct" | "enum") ->
        loop { state with pos = skip_decl state.tokens state.pos 0 } acc
    | tok when starts_type tok -> (
        match parse_function state with
        | Some fn, state -> loop state (fn :: acc)
        | None, state -> loop state acc)
    | _ -> loop (advance state) acc
  in
  loop { tokens; pos = 0 } []

let truth n = n <> 0
let bool_int b = if b then 1 else 0

let rec assoc_find name = function
  | [] -> fail ("unknown variable: " ^ name)
  | (key, value) :: rest -> if key = name then value else assoc_find name rest

let assoc_set name value env = (name, value) :: List.remove_assoc name env

type control = Continue of (string * int) list | Returned of int | Jumped of string * (string * int) list

let rec eval_expr funcs env = function
  | EInt n -> n
  | EString s -> if String.length s = 0 then 0 else Char.code s.[0]
  | EVar name -> assoc_find name env
  | EUnary (Neg, e) -> - eval_expr funcs env e
  | EUnary (Not, e) -> bool_int (not (truth (eval_expr funcs env e)))
  | EUnary (Deref, e) ->
      let _ = eval_expr funcs env e in
      0
  | EUnary (Addr, e) ->
      let _ = eval_expr funcs env e in
      0
  | ECast (ty, e) ->
      let value = eval_expr funcs env e in
      (match ty with
      | TUnsignedChar -> value land 255
      | TSignedChar | TChar ->
          let b = value land 255 in
          if b > 127 then b - 256 else b
      | _ -> value)
  | EBinary (Land, a, b) ->
      if truth (eval_expr funcs env a) then bool_int (truth (eval_expr funcs env b)) else 0
  | EBinary (Lor, a, b) ->
      if truth (eval_expr funcs env a) then 1 else bool_int (truth (eval_expr funcs env b))
  | EBinary (op, a, b) ->
      let x = eval_expr funcs env a in
      let y = eval_expr funcs env b in
      (match op with
      | Add -> x + y
      | Sub -> x - y
      | Mul -> x * y
      | Div -> x / y
      | Mod -> x mod y
      | Eq -> bool_int (x = y)
      | Ne -> bool_int (x <> y)
      | Lt -> bool_int (x < y)
      | Le -> bool_int (x <= y)
      | Gt -> bool_int (x > y)
      | Ge -> bool_int (x >= y)
      | Shl -> x lsl y
      | Shr -> x asr y
      | Land | Lor -> assert false)
  | ECall ("_exit", [ arg ]) -> eval_expr funcs env arg
  | ECall (name, args) ->
      let values = List.map (eval_expr funcs env) args in
      eval_func funcs name values

and eval_func funcs name args =
  let fn =
    match List.find_opt (fun fn -> fn.name = name) funcs with
    | Some fn -> fn
    | None -> fail ("unknown function: " ^ name)
  in
  let env = List.combine fn.params args in
  match exec_block funcs fn.body env with
  | Returned code -> code
  | Continue _ -> 0
  | Jumped (label, _) -> fail ("unresolved goto: " ^ label)

and exec_simple funcs env = function
  | SEmpty -> env
  | SExpr (ECall ("_exit", [ arg ])) -> raise (Exit_code (eval_expr funcs env arg))
  | SExpr (ECall (name, _)) when List.find_opt (fun fn -> fn.name = name) funcs = None -> env
  | SExpr expr ->
      let _ = eval_expr funcs env expr in
      env
  | SDecl (name, init) ->
      let value = match init with Some expr -> eval_expr funcs env expr | None -> 0 in
      assoc_set name value env
  | SAssign (name, expr) -> assoc_set name (eval_expr funcs env expr) env
  | SAugAssign (name, op, expr) ->
      let old = assoc_find name env in
      let delta = eval_expr funcs env expr in
      let value = match op with Add -> old + delta | Sub -> old - delta | _ -> fail "bad compound assignment" in
      assoc_set name value env
  | SPost (name, delta) ->
      let old = assoc_find name env in
      assoc_set name (old + delta) env

and exec_stmt funcs env = function
  | Simple simple -> (
      try Continue (exec_simple funcs env simple) with Exit_code code -> Returned code)
  | Return None -> Returned 0
  | Return (Some expr) -> Returned (eval_expr funcs env expr)
  | Goto label -> Jumped (label, env)
  | Label _ -> Continue env
  | Block body -> exec_block funcs body env
  | If (cond, yes, no) ->
      if truth (eval_expr funcs env cond) then exec_stmt funcs env yes
      else (
        match no with Some stmt -> exec_stmt funcs env stmt | None -> Continue env)
  | While (cond, body) ->
      let rec loop env =
        if truth (eval_expr funcs env cond) then
          match exec_stmt funcs env body with
          | Continue env' -> loop env'
          | other -> other
        else Continue env
      in
      loop env
  | For (init, cond, post, body) ->
      let env = match init with Some s -> exec_simple funcs env s | None -> env in
      let rec loop env =
        let go = match cond with Some e -> truth (eval_expr funcs env e) | None -> true in
        if go then
          match exec_stmt funcs env body with
          | Continue env' ->
              let env'' = match post with Some s -> exec_simple funcs env' s | None -> env' in
              loop env''
          | other -> other
        else Continue env
      in
      loop env

and exec_block funcs stmts env =
  let label_index label =
    let rec loop i = function
      | [] -> None
      | Label name :: _ when name = label -> Some (i + 1)
      | _ :: rest -> loop (i + 1) rest
    in
    loop 0 stmts
  in
  let arr = Array.of_list stmts in
  let rec run_at i env =
    if i >= Array.length arr then Continue env
    else
      match exec_stmt funcs env arr.(i) with
      | Continue env' -> run_at (i + 1) env'
      | Jumped (label, env') -> (
          match label_index label with Some j -> run_at j env' | None -> Jumped (label, env'))
      | Returned _ as ret -> ret
  in
  run_at 0 env

let m1_of_exit code =
  "DEFINE LOADI32_RDI 48C7C7\n\
   DEFINE LOADI32_RAX 48C7C0\n\
   DEFINE SYSCALL 0F05\n\n\
   :_start\n\
  \tLOADI32_RDI %" ^ string_of_int code ^ "\n\
  \tLOADI32_RAX %60\n\
  \tSYSCALL"

let compile src =
  let tokens = lex src in
  let funcs = parse_program tokens in
  m1_of_exit (eval_func funcs "main" [])

let read_stdin () =
  let b = Buffer.create 4096 in
  (try
     while true do
       Buffer.add_channel b stdin 4096
     done
   with End_of_file -> ());
  Buffer.contents b

let () =
  try print_string (compile (read_stdin ())) with
  | Parse_error msg ->
      prerr_endline ("ccc-host-ocaml: parse error: " ^ msg);
      exit 1
  | Compile_error msg ->
      prerr_endline ("ccc-host-ocaml: compile error: " ^ msg);
      exit 1
