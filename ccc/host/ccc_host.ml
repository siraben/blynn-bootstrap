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

type c_type =
  | TInt
  | TChar
  | TSignedChar
  | TUnsignedChar
  | TShort
  | TUnsignedShort
  | TLong
  | TLongLong
  | TUnsigned
  | TUnsignedLong
  | TUnsignedLongLong
  | TBool
  | TDouble
  | TLongDouble
  | TVoid
  | TOther of string
  | TPtr of c_type

type binop = Add | Sub | Mul | Div | Mod | Eq | Ne | Lt | Le | Gt | Ge | Land | Lor | Shl | Shr
type unop = Neg | Not | Deref | Addr

type expr =
  | EInt of int
  | EVar of string
  | EString of string
  | EInitList of expr list
  | EIndex of expr * expr
  | EMember of expr * string
  | EPtrMember of expr * string
  | ESizeof of c_type
  | ESizeofExpr of expr
  | EAssignExpr of string * expr
  | EAssignDeref of expr * expr
  | EAssignIndex of expr * expr * expr
  | EAssignMember of expr * string * expr
  | EUpdateExpr of string * int * bool
  | ECond of expr * expr * expr
  | EUnary of unop * expr
  | EBinary of binop * expr * expr
  | ECall of string * expr list
  | ECast of c_type * expr

type simple_stmt =
  | SExpr of expr
  | SAssign of string * expr
  | SAugAssign of string * binop * expr
  | SPost of string * int
  | SDecl of c_type * string * expr option * expr option
  | STypeAlias of c_type * string
  | SEnumDecl of (string * expr option) list
  | SEmpty

type stmt =
  | Simple of simple_stmt
  | Return of expr option
  | If of expr * stmt * stmt option
  | While of expr * stmt
  | DoWhile of stmt * expr
  | For of simple_stmt option * expr option * simple_stmt option * stmt
  | Goto of string
  | Label of string
  | Block of stmt list

type func = { name : string; params : string list; body : stmt list; ret_type : c_type }
type global_decl = { global_type : c_type; global_name : string; global_init : expr option; global_array_size : expr option }
type field_layout = { field_name : string; field_size : int; field_offset : int }
type struct_layout = { struct_name : string; struct_fields : field_layout list; struct_size : int }
type program = { constants : (string * int) list; structs : struct_layout list; globals : global_decl list; funcs : func list }

let has_suffix suffix text =
  let suffix_len = String.length suffix in
  let text_len = String.length text in
  text_len >= suffix_len && String.sub text (text_len - suffix_len) suffix_len = suffix

let has_prefix prefix text =
  let prefix_len = String.length prefix in
  String.length text >= prefix_len && String.sub text 0 prefix_len = prefix

let align_up value align =
  if align <= 1 then value else ((value + align - 1) / align) * align

let starts_uppercase name =
  String.length name > 0 && 'A' <= name.[0] && name.[0] <= 'Z'

let rec starts_type = function
  | Ident ("int" | "char" | "signed" | "unsigned" | "void" | "long" | "short" | "_Bool" | "double" | "static" | "const" | "struct") -> true
  | Ident name -> has_suffix "_t" name || starts_uppercase name
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
        (match peek st with
        | Ident "char" -> (TSignedChar, advance st)
        | Ident "short" -> (TShort, advance st)
        | Ident "int" -> (TInt, advance st)
        | _ -> (TInt, st))
    | Ident "unsigned" ->
        let st = advance state in
        (match peek st with
        | Ident "char" -> (TUnsignedChar, advance st)
        | Ident "short" -> (TUnsignedShort, advance st)
        | Ident "long" ->
            let st = advance st in
            (match peek st with Ident "long" -> (TUnsignedLongLong, advance st) | _ -> (TUnsignedLong, st))
        | Ident "int" -> (TUnsigned, advance st)
        | _ -> (TUnsigned, st))
    | Ident "char" -> (TChar, advance state)
    | Ident "int" -> (TInt, advance state)
    | Ident "void" -> (TVoid, advance state)
    | Ident "_Bool" -> (TBool, advance state)
    | Ident "short" -> (TShort, advance state)
    | Ident "long" ->
        let st = advance state in
        (match peek st with
        | Ident "long" -> (TLongLong, advance st)
        | Ident "double" -> (TLongDouble, advance st)
        | _ -> (TLong, st))
    | Ident "double" -> (TDouble, advance state)
    | Ident "struct" ->
        let st = advance state in
        (match peek st with Ident name -> (TOther ("struct " ^ name), advance st) | _ -> (TOther "struct", st))
    | Ident name -> (TOther name, advance state)
    | _ -> raise (Parse_error "expected type")
  in
  let rec post_ptr_qualifiers st =
    match peek st with
    | Ident "const" -> post_ptr_qualifiers (advance st)
    | _ -> st
  in
  let rec ptr ty st = match peek st with Sym "*" -> ptr (TPtr ty) (post_ptr_qualifiers (advance st)) | _ -> (ty, st) in
  ptr base state

let rec parse_expr state = parse_assignment state

and parse_assignment state =
  let lhs, state = parse_conditional state in
  match peek state with
  | Sym "=" -> (
      let rhs, state = parse_assignment (advance state) in
      match lhs with
      | EVar name -> (EAssignExpr (name, rhs), state)
      | EUnary (Deref, ptr) -> (EAssignDeref (ptr, rhs), state)
      | EIndex (base, index) -> (EAssignIndex (base, index, rhs), state)
      | EMember (base, field) -> (EAssignMember (base, field, rhs), state)
      | EPtrMember (base, field) -> (EAssignMember (EUnary (Deref, base), field, rhs), state)
      | _ -> raise (Parse_error "bad assignment target"))
  | _ -> (lhs, state)

and parse_conditional state =
  let cond, state = parse_binop 1 state in
  match peek state with
  | Sym "?" ->
      let yes, state = parse_expr (advance state) in
      let state =
        match expect_sym ":" state with
        | Ok ((), st) -> st
        | Error msg -> raise (Parse_error msg)
      in
      let no, state = parse_conditional state in
      (ECond (cond, yes, no), state)
  | _ -> (cond, state)

and parse_primary state =
  match peek state with
  | Int_lit n -> (EInt n, advance state)
  | Char_lit n -> (EInt n, advance state)
  | String_lit s -> (EString s, advance state)
  | Sym "{" ->
      let rec loop st acc =
        match peek st with
        | Sym "}" -> (EInitList (List.rev acc), advance st)
        | _ ->
            let expr, st = parse_expr st in
            (match peek st with
            | Sym "," -> loop (advance st) (expr :: acc)
            | Sym "}" -> loop st (expr :: acc)
            | _ -> raise (Parse_error "expected , or } in initializer"))
      in
      loop (advance state) []
  | Ident "sizeof" ->
      let state = advance state in
      let state =
        match expect_sym "(" state with
        | Ok ((), st) -> st
        | Error msg -> raise (Parse_error msg)
      in
      if starts_type (peek state) then
        let ty, state = parse_type state in
        let state =
          match expect_sym ")" state with
          | Ok ((), st) -> st
          | Error msg -> raise (Parse_error msg)
        in
        (ESizeof ty, state)
      else
        let expr, state = parse_expr state in
        (match expect_sym ")" state with
        | Ok ((), state) -> (ESizeofExpr expr, state)
        | Error msg -> raise (Parse_error msg))
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
  | Sym "++" ->
      let name = match peek (advance state) with Ident name -> name | _ -> raise (Parse_error "expected identifier after ++") in
      (EUpdateExpr (name, 1, true), advance (advance state))
  | Sym "--" ->
      let name = match peek (advance state) with Ident name -> name | _ -> raise (Parse_error "expected identifier after --") in
      (EUpdateExpr (name, -1, true), advance (advance state))
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
  | _ ->
      let expr, state = parse_primary state in
      parse_postfix expr state

and parse_postfix expr state =
  match (expr, peek state) with
  | EVar name, Sym "++" -> (EUpdateExpr (name, 1, false), advance state)
  | EVar name, Sym "--" -> (EUpdateExpr (name, -1, false), advance state)
  | _, Sym "[" ->
      let index, state = parse_expr (advance state) in
      let state =
        match expect_sym "]" state with
        | Ok ((), st) -> st
        | Error msg -> raise (Parse_error msg)
      in
      parse_postfix (EIndex (expr, index)) state
  | _, Sym "." ->
      let name =
        match peek (advance state) with
        | Ident name -> name
        | _ -> raise (Parse_error "expected field name")
      in
      parse_postfix (EMember (expr, name)) (advance (advance state))
  | _, Sym "->" ->
      let name =
        match peek (advance state) with
        | Ident name -> name
        | _ -> raise (Parse_error "expected field name")
      in
      parse_postfix (EPtrMember (expr, name)) (advance (advance state))
  | _ -> (expr, state)

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

let layout_scalar_size = function
  | TChar | TSignedChar | TUnsignedChar | TBool -> 1
  | TShort | TUnsignedShort -> 2
  | TInt | TUnsigned | TOther _ -> 4
  | TLong | TLongLong | TUnsignedLong | TUnsignedLongLong | TPtr _ -> 8
  | TDouble -> 8
  | TLongDouble -> 16
  | TVoid -> 1

let layout_align ty =
  min 8 (layout_scalar_size ty)

let const_expr_int = function
  | EInt n -> n
  | EUnary (Neg, EInt n) -> -n
  | _ -> 1

let layout_field_size ty array_size =
  let count = match array_size with Some expr -> const_expr_int expr | None -> 1 in
  layout_scalar_size ty * count

let build_struct_layout name fields =
  let rec loop offset acc = function
    | [] -> { struct_name = name; struct_fields = List.rev acc; struct_size = offset }
    | (field_name, ty, array_size) :: rest ->
        let offset = align_up offset (layout_align ty) in
        let field_size = layout_field_size ty array_size in
        loop (offset + field_size) ({ field_name; field_size; field_offset = offset } :: acc) rest
  in
  loop 0 [] fields

let parse_enum_decl state =
  let state =
    match peek state with
    | Ident "enum" -> advance state
    | _ -> raise (Parse_error "expected enum")
  in
  let state =
    match peek state with
    | Ident _ -> advance state
    | _ -> state
  in
  let state =
    match expect_sym "{" state with
    | Ok ((), st) -> st
    | Error msg -> raise (Parse_error msg)
  in
  let rec loop st acc =
    match peek st with
    | Sym "}" -> (List.rev acc, advance st)
    | Ident name ->
        let st = advance st in
        let value, st =
          match peek st with
          | Sym "=" ->
              let expr, st = parse_expr (advance st) in
              (Some expr, st)
          | _ -> (None, st)
        in
        (match peek st with
        | Sym "," -> loop (advance st) ((name, value) :: acc)
        | Sym "}" -> loop st ((name, value) :: acc)
        | _ -> raise (Parse_error "expected , or } in enum"))
    | _ -> raise (Parse_error "expected enum constant")
  in
  let constants, state = loop state [] in
  let state =
    match expect_sym ";" state with
    | Ok ((), st) -> st
    | Error msg -> raise (Parse_error msg)
  in
  (constants, state)

let parse_decl_suffix name state =
  let array_size, state =
    match peek state with
    | Sym "[" ->
        let state = advance state in
        let array_size, state =
          match peek state with
          | Sym "]" -> (Some (EInt (-1)), state)
          | _ ->
              let size, state = parse_expr state in
              (Some size, state)
        in
        (match expect_sym "]" state with Ok ((), st) -> (array_size, st) | Error msg -> raise (Parse_error msg))
    | _ -> (None, state)
  in
  let init, state =
    match peek state with
    | Sym "=" ->
        let expr, state = parse_expr (advance state) in
        (Some expr, state)
    | _ -> (None, state)
  in
  (name, init, array_size, state)

let parse_decl_tail state =
  let name =
    match peek state with
    | Ident name -> name
    | _ -> raise (Parse_error "expected declaration name")
  in
  parse_decl_suffix name (advance state)

let parse_decl_after_type state =
  let ty, state = parse_type state in
  let name, init, array_size, state = parse_decl_tail state in
  (SDecl (ty, name, init, array_size), state)

let parse_simple_no_semi state =
  match peek state with
  | Sym ")" | Sym ";" -> (SEmpty, state)
  | tok when starts_type tok ->
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
          let expr, st = parse_expr state in
          (SExpr expr, st))
  | _ ->
      let expr, st = parse_expr state in
      (SExpr expr, st)

let parse_simple_stmt state =
  let simple, state = parse_simple_no_semi state in
  match expect_sym ";" state with
  | Ok ((), state') -> (simple, state')
  | Error msg -> raise (Parse_error msg)

let rec skip_decl tokens pos depth =
  match tokens.(pos) with
  | Eof -> pos
  | Sym ";" when depth = 0 -> pos + 1
  | Sym "{" -> skip_decl tokens (pos + 1) (depth + 1)
  | Sym "}" when depth > 0 -> skip_decl tokens (pos + 1) (depth - 1)
  | _ -> skip_decl tokens (pos + 1) depth

let rec parse_stmt state =
  match peek state with
  | Ident "typedef" ->
      let ty, state = parse_type (advance state) in
      let name =
        match peek state with
        | Ident name -> name
        | _ -> raise (Parse_error "expected typedef name")
      in
      let state =
        match expect_sym ";" (advance state) with
        | Ok ((), st) -> st
        | Error msg -> raise (Parse_error msg)
      in
      (Simple (STypeAlias (ty, name)), state)
  | Ident "enum" ->
      let constants, state = parse_enum_decl state in
      (Simple (SEnumDecl constants), state)
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
  | Ident "do" ->
      let body, state = parse_stmt (advance state) in
      let state =
        match peek state with
        | Ident "while" -> advance state
        | _ -> raise (Parse_error "expected while after do")
      in
      let state = match expect_sym "(" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
      let cond, state = parse_expr state in
      let state = match expect_sym ")" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
      let state = match expect_sym ";" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
      (DoWhile (body, cond), state)
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

type external_decl = ExternalFunc of func option | ExternalGlobal of global_decl

let parse_external_decl state =
  let ty, state = parse_type state in
  let name = match peek state with Ident name -> name | _ -> raise (Parse_error "expected function name") in
  let state = advance state in
  match peek state with
  | Sym "(" ->
      let params, state = parse_params state in
      (match peek state with
      | Sym ";" -> (ExternalFunc None, advance state)
      | Sym "{" ->
          let body, state = parse_block (advance state) in
          (ExternalFunc (Some { name; params; body; ret_type = ty }), state)
      | _ -> raise (Parse_error "expected function body"))
  | _ ->
      let name, init, array_size, state = parse_decl_suffix name state in
      let state = match expect_sym ";" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
      (ExternalGlobal { global_type = ty; global_name = name; global_init = init; global_array_size = array_size }, state)

let parse_struct_definition state =
  let state =
    match peek state with
    | Ident "struct" -> advance state
    | _ -> raise (Parse_error "expected struct")
  in
  let name =
    match peek state with
    | Ident name -> name
    | _ -> raise (Parse_error "expected struct name")
  in
  let state = match expect_sym "{" (advance state) with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
  let rec loop st acc =
    match peek st with
    | Sym "}" ->
        let st = advance st in
        let st = match expect_sym ";" st with Ok ((), st') -> st' | Error msg -> raise (Parse_error msg) in
        (build_struct_layout name (List.rev acc), st)
    | _ ->
        let ty, st = parse_type st in
        let field =
          match peek st with
          | Ident name -> name
          | _ -> raise (Parse_error "expected field name")
        in
        let array_size, st =
          match peek (advance st) with
          | Sym "[" ->
              let st = advance (advance st) in
              let array_size, st = if peek st = Sym "]" then (None, st) else let expr, st = parse_expr st in (Some expr, st) in
              (match expect_sym "]" st with Ok ((), st') -> (array_size, st') | Error msg -> raise (Parse_error msg))
          | _ -> (None, advance st)
        in
        let st = match expect_sym ";" st with Ok ((), st') -> st' | Error msg -> raise (Parse_error msg) in
        loop st ((field, ty, array_size) :: acc)
  in
  loop state []

let parse_typedef_struct_definition state =
  let state =
    match peek state with
    | Ident "typedef" -> advance state
    | _ -> raise (Parse_error "expected typedef")
  in
  let state =
    match peek state with
    | Ident "struct" -> advance state
    | _ -> raise (Parse_error "expected struct")
  in
  let tag, state =
    match peek state with
    | Ident name -> (name, advance state)
    | Sym "{" -> ("", state)
    | _ -> raise (Parse_error "expected struct name")
  in
  let state = match expect_sym "{" state with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
  let rec fields st acc =
    match peek st with
    | Sym "}" -> (List.rev acc, advance st)
    | _ ->
        let ty, st = parse_type st in
        let field =
          match peek st with
          | Ident name -> name
          | _ -> raise (Parse_error "expected field name")
        in
        let array_size, st =
          match peek (advance st) with
          | Sym "[" ->
              let st = advance (advance st) in
              let array_size, st = if peek st = Sym "]" then (None, st) else let expr, st = parse_expr st in (Some expr, st) in
              (match expect_sym "]" st with Ok ((), st') -> (array_size, st') | Error msg -> raise (Parse_error msg))
          | _ -> (None, advance st)
        in
        let st = match expect_sym ";" st with Ok ((), st') -> st' | Error msg -> raise (Parse_error msg) in
        fields st ((field, ty, array_size) :: acc)
  in
  let fields, state = fields state [] in
  let alias =
    match peek state with
    | Ident name -> name
    | _ -> raise (Parse_error "expected typedef alias")
  in
  let state = match expect_sym ";" (advance state) with Ok ((), st) -> st | Error msg -> raise (Parse_error msg) in
  let layout = build_struct_layout alias fields in
  let tag_layout = if tag = "" then None else Some { layout with struct_name = tag } in
  (tag_layout, layout, state)

let rec assoc_int name = function
  | [] -> fail ("unknown enum constant: " ^ name)
  | (key, value) :: rest -> if key = name then value else assoc_int name rest

let rec eval_enum_expr env = function
  | EInt n -> n
  | EVar name -> assoc_int name env
  | EBinary (Add, a, b) -> eval_enum_expr env a + eval_enum_expr env b
  | EBinary (Sub, a, b) -> eval_enum_expr env a - eval_enum_expr env b
  | EUnary (Neg, e) -> - eval_enum_expr env e
  | _ -> fail "unsupported enum initializer"

let add_enum_constants env constants =
  let rec loop next_value env = function
    | [] -> env
    | (name, expr) :: rest ->
        let value = match expr with Some expr -> eval_enum_expr env expr | None -> next_value in
        loop (value + 1) ((name, value) :: env) rest
  in
  loop 0 env constants

let external_is_named_function state =
  try
    let _ty, state = parse_type state in
    match peek state with
    | Ident _ -> peek (advance state) = Sym "("
    | _ -> false
  with Parse_error _ -> false

let parse_program tokens =
  let rec loop state constants structs globals funcs =
    match peek state with
    | Eof -> { constants; structs = List.rev structs; globals = List.rev globals; funcs = List.rev funcs }
    | Ident "enum" ->
        if peek (advance state) = Sym "{" then
          let enum_constants, state = parse_enum_decl state in
          let constants = add_enum_constants constants enum_constants in
          loop state constants structs globals funcs
        else
          loop { state with pos = skip_decl state.tokens state.pos 0 } constants structs globals funcs
    | Ident "struct" when (match peek (advance state) with Ident _ -> peek (advance (advance state)) = Sym "{" | _ -> false) ->
        let layout, state = parse_struct_definition state in
        loop state constants (layout :: structs) globals funcs
    | Ident "typedef"
      when (match peek (advance state) with
      | Ident "struct" -> (
          match peek (advance (advance state)) with
          | Ident _ -> peek (advance (advance (advance state))) = Sym "{"
          | Sym "{" -> true
          | _ -> false)
      | _ -> false) ->
        let tag_layout, alias_layout, state = parse_typedef_struct_definition state in
        let structs = alias_layout :: structs in
        let structs = match tag_layout with Some layout -> layout :: structs | None -> structs in
        loop state constants structs globals funcs
    | Ident "typedef" ->
        loop { state with pos = skip_decl state.tokens state.pos 0 } constants structs globals funcs
    | tok when starts_type tok -> (
        try
          match parse_external_decl state with
          | ExternalFunc (Some fn), state -> loop state constants structs globals (fn :: funcs)
          | ExternalFunc None, state -> loop state constants structs globals funcs
          | ExternalGlobal global, state -> loop state constants structs (global :: globals) funcs
        with
        | Parse_error _ when not (external_is_named_function state) ->
            loop { state with pos = skip_decl state.tokens state.pos 0 } constants structs globals funcs)
    | _ -> loop (advance state) constants structs globals funcs
  in
  loop { tokens; pos = 0 } [] [] [] []

let truth n = n <> 0
let bool_int b = if b then 1 else 0

let rec sizeof_type = function
  | TChar | TSignedChar | TUnsignedChar | TBool -> 1
  | TShort | TUnsignedShort -> 2
  | TInt | TUnsigned -> 4
  | TLong | TLongLong | TUnsignedLong | TUnsignedLongLong | TPtr _ -> 8
  | TDouble -> 8
  | TLongDouble -> 16
  | TVoid -> 1
  | TOther _ -> 4

type value =
  | VInt of int
  | VPtr of binding
  | VArrayPtr of binding * int
  | VFieldPtr of binding * int
  | VStringPtr of string * int
  | VFunc of string

and binding = {
  bind_name : string;
  bind_type : c_type;
  bind_value : value ref;
  bind_string : string option;
  bind_array : value array option;
  bind_fields : (string * value ref) list ref option;
}

type env = binding list

let int_of_value = function
  | VInt value -> value
  | VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _ -> fail "pointer used as integer"

let coerce_int ty value =
  match ty with
  | TUnsignedChar -> value land 255
  | TUnsignedShort -> value land 65535
  | TSignedChar | TChar ->
      let b = value land 255 in
      if b > 127 then b - 256 else b
  | TUnsigned -> value
  | TBool -> bool_int (truth value)
  | _ -> value

let coerce_value ty = function
  | VInt value -> VInt (coerce_int ty value)
  | (VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _) as ptr -> ptr

let rec find_binding name = function
  | [] -> fail ("unknown variable: " ^ name)
  | binding :: rest -> if binding.bind_name = name then binding else find_binding name rest

let rec find_binding_opt name = function
  | [] -> None
  | binding :: rest -> if binding.bind_name = name then Some binding else find_binding_opt name rest

let assoc_find name env =
  let binding = find_binding name env in
  int_of_value !(binding.bind_value)

let assoc_set_value name value env =
  let binding = find_binding name env in
  binding.bind_value := coerce_value binding.bind_type value;
  env

let assoc_set name value env = assoc_set_value name (VInt value) env

let assoc_decl ?text ?array ty name value env =
  let fields =
    match ty with
    | TOther _ -> Some (ref [])
    | _ -> None
  in
  { bind_name = name; bind_type = ty; bind_value = ref (coerce_value ty value); bind_string = text; bind_array = array; bind_fields = fields }
  :: env

let assoc_decl_value ty name value env =
  assoc_decl ty name value env

type control = Continue of env | Returned of int | Jumped of string * env

let string_byte text pos =
  if pos < 0 || pos >= String.length text then 0 else Char.code text.[pos]

let rec read_binding_index binding index =
  match binding.bind_array, binding.bind_string, !(binding.bind_value) with
  | Some values, _, _ ->
      if index < 0 || index >= Array.length values then VInt 0 else values.(index)
  | None, Some text, _ -> VInt (string_byte text index)
  | None, None, VArrayPtr (target, base) -> read_binding_index target (base + index)
  | None, None, VStringPtr (text, base) -> VInt (string_byte text (base + index))
  | None, None, _ -> fail ("not an indexable value: " ^ binding.bind_name)

let rec write_binding_index binding index value =
  match binding.bind_array, !(binding.bind_value) with
  | Some values, _ ->
      if index < 0 || index >= Array.length values then fail ("array index out of bounds: " ^ binding.bind_name);
      let value = coerce_value binding.bind_type value in
      values.(index) <- value;
      value
  | None, VArrayPtr (target, base) -> write_binding_index target (base + index) value
  | None, _ -> fail ("not a writable array: " ^ binding.bind_name)

let read_pointer = function
  | VPtr target -> !(target.bind_value)
  | VArrayPtr (target, offset) -> read_binding_index target offset
  | VFieldPtr _ -> fail "cannot read raw struct byte pointer"
  | VStringPtr (text, offset) -> VInt (string_byte text offset)
  | VInt _ | VFunc _ -> fail "not a pointer"

let write_pointer ptr value =
  match ptr with
  | VPtr target ->
      target.bind_value := coerce_value target.bind_type value;
      value
  | VArrayPtr (target, offset) -> write_binding_index target offset value
  | VFieldPtr _ -> fail "cannot write raw struct byte pointer"
  | VStringPtr _ -> fail "cannot write through string literal pointer"
  | VInt _ | VFunc _ -> fail "not a pointer"

let add_to_value value delta =
  match value with
  | VInt n -> VInt (n + delta)
  | VArrayPtr (target, offset) -> VArrayPtr (target, offset + delta)
  | VFieldPtr (target, offset) -> VFieldPtr (target, offset + delta)
  | VStringPtr (text, offset) -> VStringPtr (text, offset + delta)
  | VPtr _ | VFunc _ -> fail "unsupported pointer arithmetic"

let field_cell fields name =
  match List.find_opt (fun (field, _) -> field = name) !(fields) with
  | Some (_, cell) -> cell
  | None ->
      let cell = ref (VInt 0) in
      fields := !(fields) @ [ (name, cell) ];
      cell

let binding_fields binding =
  match binding.bind_fields with
  | Some fields -> fields
  | None -> fail ("not a struct value: " ^ binding.bind_name)

let struct_name_of_type = function
  | TOther name when has_prefix "struct " name -> Some (String.sub name 7 (String.length name - 7))
  | TOther name -> Some name
  | _ -> None

let struct_fields structs ty =
  match struct_name_of_type ty with
  | None -> []
  | Some name -> (
      match List.find_opt (fun layout -> layout.struct_name = name) structs with
      | Some layout -> List.map (fun field -> field.field_name) layout.struct_fields
      | None -> [])

let struct_size structs ty =
  match struct_name_of_type ty with
  | None -> None
  | Some name -> (
      match List.find_opt (fun layout -> layout.struct_name = name) structs with
      | Some layout -> Some layout.struct_size
      | None -> None)

let struct_field_offset structs ty field_name =
  match struct_name_of_type ty with
  | None -> None
  | Some name -> (
      match List.find_opt (fun layout -> layout.struct_name = name) structs with
      | None -> None
      | Some layout -> (
          match List.find_opt (fun field -> field.field_name = field_name) layout.struct_fields with
          | Some field -> Some field.field_offset
          | None -> None))

let value_equal a b =
  match (a, b) with
  | VInt x, VInt y -> x = y
  | VPtr x, VPtr y -> x == y
  | VArrayPtr (x, ix), VArrayPtr (y, iy) -> x == y && ix = iy
  | VFieldPtr (x, ix), VFieldPtr (y, iy) -> x == y && ix = iy
  | VStringPtr (x, ix), VStringPtr (y, iy) -> x = y && ix = iy
  | VFunc x, VFunc y -> x = y
  | VInt 0, (VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _) -> false
  | (VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _), VInt 0 -> false
  | _ -> false

let pointer_delta a b =
  match (a, b) with
  | VFieldPtr (x, ix), VFieldPtr (y, iy) when x == y -> Some (ix - iy)
  | VArrayPtr (x, ix), VArrayPtr (y, iy) when x == y -> Some (ix - iy)
  | VStringPtr (x, ix), VStringPtr (y, iy) when x = y -> Some (ix - iy)
  | _ -> None

let rec eval_value funcs structs globals env = function
  | EInt n -> VInt n
  | EString s -> VStringPtr (s, 0)
  | EInitList _ -> VInt 0
  | EVar name ->
      (match find_binding_opt name env with
      | Some binding -> (match binding.bind_array with Some _ -> VArrayPtr (binding, 0) | None -> !(binding.bind_value))
      | None when List.exists (fun fn -> fn.name = name) funcs -> VFunc name
      | None -> fail ("unknown variable: " ^ name))
  | ESizeof (TOther name) -> (
      match struct_size structs (TOther name) with
      | Some size -> VInt size
      | None -> (
          try VInt (assoc_find name env) with Compile_error _ -> VInt 4))
  | ESizeof ty -> VInt (match struct_size structs ty with Some size -> size | None -> sizeof_type ty)
  | ESizeofExpr expr -> (
      match eval_value funcs structs globals env expr with
      | VInt _ -> VInt 4
      | VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _ -> VInt 8)
  | EIndex (base, index) ->
      let index_value = eval_expr funcs structs globals env index in
      let value =
        match base with
        | EVar name -> read_binding_index (find_binding name env) index_value
        | EString text -> VInt (string_byte text index_value)
        | expr -> read_pointer (add_to_value (eval_value funcs structs globals env expr) index_value)
      in
      value
  | EMember (base, field) ->
      let binding =
        match base with
        | EVar name -> find_binding name env
        | EUnary (Deref, ptr) -> (
            match eval_value funcs structs globals env ptr with
            | VPtr target -> target
            | VFieldPtr (target, 0) -> target
            | _ -> fail "not a struct pointer")
        | _ -> fail "unsupported member expression"
      in
      !(field_cell (binding_fields binding) field)
  | EPtrMember (base, field) ->
      eval_value funcs structs globals env (EMember (EUnary (Deref, base), field))
  | EAssignExpr (name, expr) ->
      let value = eval_value funcs structs globals env expr in
      let _ = assoc_set_value name value env in
      !((find_binding name env).bind_value)
  | EAssignDeref (ptr, expr) ->
      let value = eval_value funcs structs globals env expr in
      write_pointer (eval_value funcs structs globals env ptr) value
  | EAssignIndex (base, index, expr) ->
      let index_value = eval_expr funcs structs globals env index in
      let value = eval_value funcs structs globals env expr in
      let written =
        match base with
        | EVar name -> write_binding_index (find_binding name env) index_value value
        | expr -> write_pointer (add_to_value (eval_value funcs structs globals env expr) index_value) value
      in
      written
  | EAssignMember (base, field, expr) ->
      let binding =
        match base with
        | EVar name -> find_binding name env
        | EUnary (Deref, ptr) -> (
            match eval_value funcs structs globals env ptr with
            | VPtr target -> target
            | VFieldPtr (target, 0) -> target
            | _ -> fail "not a struct pointer")
        | _ -> fail "unsupported member expression"
      in
      let value = eval_value funcs structs globals env expr in
      let cell = field_cell (binding_fields binding) field in
      cell := value;
      value
  | EUpdateExpr (name, delta, prefix) ->
      let binding = find_binding name env in
      let old_value = !(binding.bind_value) in
      let new_value = coerce_value binding.bind_type (add_to_value old_value delta) in
      binding.bind_value := new_value;
      if prefix then new_value else old_value
  | EUnary (Neg, e) -> VInt (- eval_expr funcs structs globals env e)
  | EUnary (Not, e) -> VInt (bool_int (not (truth (eval_expr funcs structs globals env e))))
  | ECond (cond, yes, no) ->
      if truth (eval_expr funcs structs globals env cond) then eval_value funcs structs globals env yes else eval_value funcs structs globals env no
  | EUnary (Deref, e) -> read_pointer (eval_value funcs structs globals env e)
  | EUnary (Addr, EVar name) ->
      let binding = find_binding name env in
      (match binding.bind_fields with Some _ -> VFieldPtr (binding, 0) | None -> VPtr binding)
  | EUnary (Addr, EIndex (base, index)) ->
      let index_value = eval_expr funcs structs globals env index in
      add_to_value (eval_value funcs structs globals env base) index_value
  | EUnary (Addr, EMember (EVar name, field)) ->
      let binding = find_binding name env in
      let offset =
        match struct_field_offset structs binding.bind_type field with
        | Some offset -> offset
        | None -> 0
      in
      VFieldPtr (binding, offset)
  | EUnary (Addr, _) -> fail "unsupported address expression"
  | ECast (ty, e) ->
      coerce_value ty (eval_value funcs structs globals env e)
  | EBinary (Land, a, b) ->
      VInt (if truth (eval_expr funcs structs globals env a) then bool_int (truth (eval_expr funcs structs globals env b)) else 0)
  | EBinary (Lor, a, b) ->
      VInt (if truth (eval_expr funcs structs globals env a) then 1 else bool_int (truth (eval_expr funcs structs globals env b)))
  | EBinary (Eq, a, b) ->
      VInt (bool_int (value_equal (eval_value funcs structs globals env a) (eval_value funcs structs globals env b)))
  | EBinary (Ne, a, b) ->
      VInt (bool_int (not (value_equal (eval_value funcs structs globals env a) (eval_value funcs structs globals env b))))
  | EBinary (Sub, a, b) -> (
      let av = eval_value funcs structs globals env a in
      let bv = eval_value funcs structs globals env b in
      match pointer_delta av bv with
      | Some delta -> VInt delta
      | None -> VInt (int_of_value av - int_of_value bv))
  | EBinary (op, a, b) ->
      let x = eval_expr funcs structs globals env a in
      let y = eval_expr funcs structs globals env b in
      VInt
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
      | Shl -> (x lsl y) land 0xffffffff
      | Shr -> x lsr y
      | Land | Lor -> assert false)
  | ECall ("_exit", [ arg ]) -> VInt (eval_expr funcs structs globals env arg)
  | ECall (name, args) ->
      let values = List.map (call_arg funcs structs globals env) args in
      let target =
        match find_binding_opt name env with
        | Some binding -> (match !(binding.bind_value) with VFunc target -> target | _ -> name)
        | None -> name
      in
      VInt (eval_func funcs structs globals target values)

and eval_expr funcs structs globals env expr = int_of_value (eval_value funcs structs globals env expr)

and call_arg funcs structs globals env = function
  | expr -> eval_value funcs structs globals env expr

and eval_func funcs structs globals name args =
  let fn =
    match List.find_opt (fun fn -> fn.name = name) funcs with
    | Some fn -> fn
    | None -> fail ("unknown function: " ^ name)
  in
  let env =
    List.map2
      (fun param value ->
        { bind_name = param; bind_type = TInt; bind_value = ref value; bind_string = None; bind_array = None; bind_fields = None })
      fn.params args
    @ globals
  in
  let env = assoc_decl ~text:name (TPtr TChar) "__func__" (VStringPtr (name, 0)) env in
  match exec_block funcs structs globals fn.body env with
  | Returned code -> coerce_int fn.ret_type code
  | Continue _ -> 0
  | Jumped (label, _) -> fail ("unresolved goto: " ^ label)

and exec_simple funcs structs globals env = function
  | SEmpty -> env
  | SExpr (ECall ("_exit", [ arg ])) -> raise (Exit_code (eval_expr funcs structs globals env arg))
  | SExpr (ECall (name, _)) when List.find_opt (fun fn -> fn.name = name) funcs = None -> env
  | SExpr expr ->
      let _ = eval_value funcs structs globals env expr in
      env
  | SDecl (ty, name, init, array_size) ->
      let array =
        match array_size with
        | Some size_expr ->
            let size =
              match (size_expr, init) with
              | EInt (-1), Some (EInitList values) -> List.length values
              | EInt (-1), _ -> 0
              | _ -> eval_expr funcs structs globals env size_expr
            in
            if size < 0 then fail ("negative array size: " ^ name);
            Some (Array.make size (VInt 0))
        | None -> None
      in
      let value =
        match init with
        | Some (EInitList _) | None -> VInt 0
        | Some expr -> eval_value funcs structs globals env expr
      in
      let text = match init with Some (EString text) -> Some text | _ -> None in
      let env = assoc_decl ?text ?array ty name value env in
      (match init with
      | Some (EInitList values) ->
          let binding = find_binding name env in
          (match binding.bind_array with
          | Some array ->
              let rec fill i = function
                | [] -> ()
                | value_expr :: values ->
                    if i < Array.length array then array.(i) <- coerce_value binding.bind_type (eval_value funcs structs globals env value_expr);
                    fill (i + 1) values
              in
              fill 0 values
          | None ->
              let rec fill fields values =
                match (fields, values) with
                | field :: fields, value_expr :: values ->
                    let cell = field_cell (binding_fields binding) field in
                    cell := eval_value funcs structs globals env value_expr;
                    fill fields values
                | _ -> ()
              in
              fill (struct_fields structs ty) values);
          env
      | _ -> env)
  | STypeAlias (ty, name) -> assoc_decl TInt name (VInt (sizeof_type ty)) env
  | SEnumDecl constants ->
      let rec loop next_value env = function
        | [] -> env
        | (name, expr) :: rest ->
            let value = match expr with Some expr -> eval_expr funcs structs globals env expr | None -> next_value in
            loop (value + 1) (assoc_decl TInt name (VInt value) env) rest
      in
      loop 0 env constants
  | SAssign (name, expr) -> assoc_set_value name (eval_value funcs structs globals env expr) env
  | SAugAssign (name, op, expr) ->
      let old = assoc_find name env in
      let delta = eval_expr funcs structs globals env expr in
      let value = match op with Add -> old + delta | Sub -> old - delta | _ -> fail "bad compound assignment" in
      assoc_set name value env
  | SPost (name, delta) ->
      let binding = find_binding name env in
      binding.bind_value := coerce_value binding.bind_type (add_to_value !(binding.bind_value) delta);
      env

and exec_stmt funcs structs globals env = function
  | Simple simple -> (
      try Continue (exec_simple funcs structs globals env simple) with Exit_code code -> Returned code)
  | Return None -> Returned 0
  | Return (Some expr) -> Returned (eval_expr funcs structs globals env expr)
  | Goto label -> Jumped (label, env)
  | Label _ -> Continue env
  | Block body -> (
      match exec_block funcs structs globals body env with
      | Continue _ -> Continue env
      | Jumped (label, _) -> Jumped (label, env)
      | Returned _ as ret -> ret)
  | If (cond, yes, no) ->
      if truth (eval_expr funcs structs globals env cond) then exec_stmt funcs structs globals env yes
      else (
        match no with Some stmt -> exec_stmt funcs structs globals env stmt | None -> Continue env)
  | While (cond, body) ->
      let rec loop env =
        if truth (eval_expr funcs structs globals env cond) then
          match exec_stmt funcs structs globals env body with
          | Continue env' -> loop env'
          | other -> other
        else Continue env
      in
      loop env
  | DoWhile (body, cond) ->
      let rec loop env =
        match exec_stmt funcs structs globals env body with
        | Continue env' -> if truth (eval_expr funcs structs globals env' cond) then loop env' else Continue env'
        | other -> other
      in
      loop env
  | For (init, cond, post, body) ->
      let env = match init with Some s -> exec_simple funcs structs globals env s | None -> env in
      let rec loop env =
        let go = match cond with Some e -> truth (eval_expr funcs structs globals env e) | None -> true in
        if go then
          match exec_stmt funcs structs globals env body with
          | Continue env' ->
              let env'' = match post with Some s -> exec_simple funcs structs globals env' s | None -> env' in
              loop env''
          | other -> other
        else Continue env
      in
      loop env

and exec_block funcs structs globals stmts env =
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
      match exec_stmt funcs structs globals env arr.(i) with
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
  let program = parse_program tokens in
  if not (List.exists (fun fn -> fn.name = "main") program.funcs) then m1_of_exit 0
  else
  let constants =
    List.map
      (fun (name, value) ->
        { bind_name = name; bind_type = TInt; bind_value = ref (VInt value); bind_string = None; bind_array = None; bind_fields = None })
      program.constants
  in
  let globals =
    List.fold_left
      (fun env global ->
        exec_simple program.funcs program.structs env env (SDecl (global.global_type, global.global_name, global.global_init, global.global_array_size)))
      constants program.globals
  in
  m1_of_exit (eval_func program.funcs program.structs globals "main" [])

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
