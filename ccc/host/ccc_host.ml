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

let is_space ch =
  match ch with ' ' | '\n' | '\r' | '\t' -> true | _ -> false
let is_digit ch = '0' <= ch && ch <= '9'
let is_alpha ch = ch = '_' || ('A' <= ch && ch <= 'Z') || ('a' <= ch && ch <= 'z')
let is_ident ch = is_alpha ch || is_digit ch

let rec list_find_opt pred xs =
  match xs with
  | [] -> None
  | x :: xs -> if pred x then Some x else list_find_opt pred xs

let rec strings_of_chars chars =
  match chars with
  | [] -> []
  | ch :: rest -> String.make 1 ch :: strings_of_chars rest

let string_of_rev_chars chars =
  String.concat "" (strings_of_chars (List.rev chars))

let unsigned_mod value modulus =
  let rem = value mod modulus in
  if rem < 0 then rem + modulus else rem

let rec pow2 count =
  if count <= 0 then 1 else 2 * pow2 (count - 1)

let rec shift_left_u32 value count =
  if count <= 0 then unsigned_mod value 4294967296
  else shift_left_u32 (unsigned_mod (value * 2) 4294967296) (count - 1)

let shift_right_u32 value count =
  (unsigned_mod value 4294967296) / pow2 count

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

let rec skip_hspace src pos =
  if pos >= String.length src then pos
  else
    match src.[pos] with
    | ' ' | '\t' | '\r' -> skip_hspace src (pos + 1)
    | _ -> pos

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
  | ch ->
      if '0' <= ch && ch <= '7' then
        let rec loop p count acc =
          if count < 3 && p < String.length src && '0' <= src.[p] && src.[p] <= '7' then
            loop (p + 1) (count + 1) ((acc * 8) + Char.code src.[p] - Char.code '0')
          else (acc, p)
        in
        loop pos 0 0
      else (Char.code ch, pos + 1)

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
  let rec loop p acc =
    if p >= String.length src then fail "unterminated string literal"
    else if src.[p] = '"' then (String_lit (string_of_rev_chars acc), p + 1)
    else if src.[p] = '\\' then
      let value, next = parse_escape src (p + 1) in
      loop next (Char.chr (unsigned_mod value 256) :: acc)
    else loop (p + 1) (src.[p] :: acc)
  in
  loop (pos + 1) []

let directive_word_at word src pos =
  let len = String.length word in
  pos + len <= String.length src
  && String.sub src pos len = word
  && (pos + len >= String.length src || not (is_ident src.[pos + len]))

let parse_define_constant src pos acc =
  let pos = skip_hspace src pos in
  if directive_word_at "define" src pos then
    let pos = skip_hspace src (pos + 6) in
    if pos < String.length src && is_alpha src.[pos] then
      let rec ident_end p = if p < String.length src && is_ident src.[p] then ident_end (p + 1) else p in
      let stop = ident_end (pos + 1) in
      let name = String.sub src pos (stop - pos) in
      let value_pos = skip_hspace src stop in
      if value_pos < String.length src && src.[value_pos] = '(' then acc
      else if value_pos < String.length src && src.[value_pos] = '\'' then
        (match lex_char src value_pos with
        | Char_lit value, _ -> (name, value) :: acc
        | _ -> acc)
      else if value_pos < String.length src && src.[value_pos] = '-' then (
        match lex_number src (value_pos + 1) with
        | Int_lit value, _ -> (name, -value) :: acc
        | _ -> acc)
      else if value_pos < String.length src && is_digit src.[value_pos] then (
        match lex_number src value_pos with
        | Int_lit value, _ -> (name, value) :: acc
        | _ -> acc)
      else acc
    else acc
  else acc

let rec define_exists name defs =
  match defs with
  | [] -> false
  | (key, _) :: rest -> key = name || define_exists name rest

let directive_name word src hash_pos =
  let pos = skip_hspace src (hash_pos + 1) in
  let len = String.length word in
  if directive_word_at word src pos then
    let pos = skip_hspace src (pos + len) in
    if pos < String.length src && is_alpha src.[pos] then
      let rec ident_end p = if p < String.length src && is_ident src.[p] then ident_end (p + 1) else p in
      let stop = ident_end (pos + 1) in
      Some (String.sub src pos (stop - pos))
    else None
  else None

let directive_at word src hash_pos =
  directive_word_at word src (skip_hspace src (hash_pos + 1))

let rec skip_inactive_conditional src pos depth =
  if pos >= String.length src then pos
  else
    let first = skip_hspace src pos in
    let next = skip_line src pos in
    if first < String.length src && src.[first] = '#' then
      if directive_at "ifdef" src first || directive_at "ifndef" src first then
        skip_inactive_conditional src next (depth + 1)
      else if directive_at "endif" src first then
        if depth = 0 then next else skip_inactive_conditional src next (depth - 1)
      else if directive_at "else" src first && depth = 0 then next
      else skip_inactive_conditional src next depth
    else skip_inactive_conditional src next depth

let rec skip_active_else src pos depth =
  if pos >= String.length src then pos
  else
    let first = skip_hspace src pos in
    let next = skip_line src pos in
    if first < String.length src && src.[first] = '#' then
      if directive_at "ifdef" src first || directive_at "ifndef" src first then
        skip_active_else src next (depth + 1)
      else if directive_at "endif" src first then
        if depth = 0 then next else skip_active_else src next (depth - 1)
      else skip_active_else src next depth
    else skip_active_else src next depth

let preprocess_source src =
  let rec loop pos defs acc =
    if pos >= String.length src then (String.concat "" (List.rev acc), defs)
    else
      let first = skip_hspace src pos in
      let next = skip_line src pos in
      if first < String.length src && src.[first] = '#' then
        if directive_at "define" src first then
          loop next (parse_define_constant src (first + 1) defs) acc
        else if directive_at "ifdef" src first then (
          match directive_name "ifdef" src first with
          | Some name ->
              if define_exists name defs then loop next defs acc else loop (skip_inactive_conditional src next 0) defs acc
          | None -> loop next defs acc)
        else if directive_at "ifndef" src first then (
          match directive_name "ifndef" src first with
          | Some name ->
              if define_exists name defs then loop (skip_inactive_conditional src next 0) defs acc else loop next defs acc
          | None -> loop next defs acc)
        else if directive_at "else" src first then
          loop (skip_active_else src next 0) defs acc
        else loop next defs acc
      else
        loop next defs (String.sub src pos (next - pos) :: acc)
  in
  loop 0 [] []

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
          list_find_opt
            (fun op -> pos + String.length op <= String.length src && String.sub src pos (String.length op) = op)
            multi_symbols
        in
        match found with
        | Some op -> loop (pos + String.length op) (Sym op :: acc)
        | None -> loop (pos + 1) (Sym (String.make 1 ch) :: acc)
  in
  Array.of_list (loop 0 [])

type parser_state = { tokens : token array; pos : int }
type 'a parser_reply = ParserOk of 'a * parser_state | ParserErr of string
type 'a consumed = Consumed of 'a parser_reply | Unconsumed of 'a parser_reply
type 'a parser = parser_state -> 'a consumed

let force_consumed consumed =
  match consumed with Consumed reply -> reply | Unconsumed reply -> reply

let return value state = Unconsumed (ParserOk (value, state))

let bind parser next state =
  match parser state with
  | Unconsumed (ParserOk (value, state')) -> next value state'
  | Consumed (ParserOk (value, state')) -> Consumed (force_consumed (next value state'))
  | Unconsumed (ParserErr msg) -> Unconsumed (ParserErr msg)
  | Consumed (ParserErr msg) -> Consumed (ParserErr msg)

let peek state =
  if state.pos < Array.length state.tokens then state.tokens.(state.pos) else Eof

let advance state = { state with pos = state.pos + 1 }

let satisfy f expected state =
  match f (peek state) with
  | Some value -> Consumed (ParserOk (value, advance state))
  | None -> Unconsumed (ParserErr expected)

let expect_sym text =
  satisfy (fun tok -> match tok with Sym got -> if got = text then Some () else None | _ -> None) ("expected " ^ text)

let expect_ident =
  satisfy (fun tok -> match tok with Ident name -> Some name | _ -> None) "expected identifier"

let expect_keyword text =
  satisfy (fun tok -> match tok with Ident got -> if got = text then Some () else None | _ -> None) ("expected " ^ text)

let expect_int_lit =
  satisfy (fun tok -> match tok with Int_lit n -> Some n | _ -> None) "expected integer literal"

let expect_char_lit =
  satisfy (fun tok -> match tok with Char_lit n -> Some n | _ -> None) "expected character literal"

let expect_string_lit =
  satisfy (fun tok -> match tok with String_lit s -> Some s | _ -> None) "expected string literal"

let optional parser state =
  match parser state with
  | Unconsumed (ParserErr _) -> Unconsumed (ParserOk (None, state))
  | Unconsumed (ParserOk (value, state')) -> Unconsumed (ParserOk (Some value, state'))
  | Consumed (ParserOk (value, state')) -> Consumed (ParserOk (Some value, state'))
  | Consumed (ParserErr msg) -> Consumed (ParserErr msg)

let need parser state =
  match force_consumed (parser state) with
  | ParserOk (value, state') -> (value, state')
  | ParserErr msg -> raise (Parse_error msg)

let need_sym text state =
  let _, state = need (expect_sym text) state in
  state

let need_keyword text state =
  let _, state = need (expect_keyword text) state in
  state

let need_ident state =
  need expect_ident state

let take parser state =
  match force_consumed (optional parser state) with
  | ParserOk (Some _, state') -> Some state'
  | ParserOk (None, _) -> None
  | ParserErr _ -> None

let take_value parser state =
  match force_consumed (optional parser state) with
  | ParserOk (Some value, state') -> Some (value, state')
  | ParserOk (None, _) -> None
  | ParserErr _ -> None

let take_sym text state =
  take (expect_sym text) state

let take_keyword text state =
  take (expect_keyword text) state

let take_ident state =
  take_value expect_ident state

let rec choose_option parsers state =
  match parsers with
  | [] -> None
  | parser :: rest -> (
      match parser state with
      | Some result -> Some result
      | None -> choose_option rest state)

let run parser tokens =
  match parser { tokens; pos = 0 } with
  | Consumed (ParserOk (value, _)) | Unconsumed (ParserOk (value, _)) -> value
  | Consumed (ParserErr msg) | Unconsumed (ParserErr msg) -> raise (Parse_error msg)

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
  | EUpdateLvalue of expr * int * bool
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
  | Switch of expr * switch_case list
  | Goto of string
  | Label of string
  | Break
  | ContinueStmt
  | Block of stmt list
and switch_case = SwitchCase of expr option * stmt list

type func = { name : string; params : string list; body : stmt list; ret_type : c_type }
type global_decl = { global_type : c_type; global_name : string; global_init : expr option; global_array_size : expr option }
type field_layout = { field_name : string; field_size : int; field_offset : int; field_is_array : bool }
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

let rec starts_type tok =
  match tok with
  | Ident ("int" | "char" | "signed" | "unsigned" | "void" | "long" | "short" | "_Bool" | "double" | "static" | "const" | "struct") -> true
  | Ident name -> has_suffix "_t" name || starts_uppercase name
  | _ -> false

let option_is_some value =
  match value with Some _ -> true | None -> false

let rec take_keyword_type choices state =
  match choices with
  | [] -> None
  | (word, ty) :: rest -> (
      match take_keyword word state with
      | Some state -> Some (ty, state)
      | None -> take_keyword_type rest state)

let rec parse_type state =
  let rec qualifiers st =
    match take_keyword "static" st with
    | Some st -> qualifiers st
    | None -> (
        match take_keyword "const" st with
        | Some st -> qualifiers st
        | None -> st)
  in
  let signed_suffix st =
    match take_keyword_type [ ("char", TSignedChar); ("short", TShort); ("int", TInt) ] st with
    | Some result -> result
    | None -> (TInt, st)
  in
  let unsigned_suffix st =
    match take_keyword_type [ ("char", TUnsignedChar); ("short", TUnsignedShort) ] st with
    | Some result -> result
    | None -> (
        match take_keyword "long" st with
        | Some st -> (
            match take_keyword "long" st with
            | Some st -> (TUnsignedLongLong, st)
            | None -> (TUnsignedLong, st))
        | None -> (
            match take_keyword "int" st with
            | Some st -> (TUnsigned, st)
            | None -> (TUnsigned, st)))
  in
  let long_suffix st =
    match take_keyword "long" st with
    | Some st -> (TLongLong, st)
    | None -> (
        match take_keyword "double" st with
        | Some st -> (TLongDouble, st)
        | None -> (TLong, st))
  in
  let struct_type st =
    match take_ident st with
    | Some (name, st) -> (TOther ("struct " ^ name), st)
    | None -> (TOther "struct", st)
  in
  let named_type st =
    let name, st = need_ident st in
    (TOther name, st)
  in
  let plain_type st =
    match take_keyword_type [ ("char", TChar); ("int", TInt); ("void", TVoid); ("_Bool", TBool); ("short", TShort); ("double", TDouble) ] st with
    | Some result -> result
    | None -> (
        match take_keyword "long" st with
        | Some st -> long_suffix st
        | None -> (
            match take_keyword "struct" st with
            | Some st -> struct_type st
            | None -> named_type st))
  in
  let state = qualifiers state in
  let base, state =
    match take_keyword "signed" state with
    | Some st -> signed_suffix st
    | None -> (
        match take_keyword "unsigned" state with
        | Some st -> unsigned_suffix st
        | None -> plain_type state)
  in
  let rec post_ptr_qualifiers st =
    match take_keyword "const" st with
    | Some st -> post_ptr_qualifiers st
    | None -> st
  in
  let rec ptr ty st =
    match take_sym "*" st with
    | Some st -> ptr (TPtr ty) (post_ptr_qualifiers st)
    | None -> (ty, st)
  in
  ptr base state

let rec parse_expr state = parse_assignment state

and parse_assignment state =
  let lhs, state = parse_conditional state in
  match take_sym "=" state with
  | Some state -> (
      let rhs, state = parse_assignment state in
      match lhs with
      | EVar name -> (EAssignExpr (name, rhs), state)
      | EUnary (Deref, ptr) -> (EAssignDeref (ptr, rhs), state)
      | EIndex (base, index) -> (EAssignIndex (base, index, rhs), state)
      | EMember (base, field) -> (EAssignMember (base, field, rhs), state)
      | EPtrMember (base, field) -> (EAssignMember (EUnary (Deref, base), field, rhs), state)
      | _ -> raise (Parse_error "bad assignment target"))
  | None -> (lhs, state)

and parse_conditional state =
  let cond, state = parse_binop 1 state in
  match take_sym "?" state with
  | Some state ->
      let yes, state = parse_expr state in
      let state = need_sym ":" state in
      let no, state = parse_conditional state in
      (ECond (cond, yes, no), state)
  | None -> (cond, state)

and parse_primary state =
  let int_lit st =
    match take_value expect_int_lit st with
    | Some (n, st) -> Some (EInt n, st)
    | None -> None
  in
  let char_lit st =
    match take_value expect_char_lit st with
    | Some (n, st) -> Some (EInt n, st)
    | None -> None
  in
  let string_lit st =
    match take_value expect_string_lit st with
    | Some (s, st) -> Some (EString s, st)
    | None -> None
  in
  let init_list st =
    match take_sym "{" st with
    | None -> None
    | Some st ->
        let rec loop st acc =
          match take_sym "}" st with
          | Some st -> (EInitList (List.rev acc), st)
          | None ->
              let expr, st = parse_expr st in
              (match take_sym "," st with
              | Some st -> loop st (expr :: acc)
              | None ->
                  let st = need_sym "}" st in
                  (EInitList (List.rev (expr :: acc)), st))
        in
        Some (loop st [])
  in
  let sizeof_expr st =
    match take_keyword "sizeof" st with
    | None -> None
    | Some st ->
        let expr, st =
          match take_sym "(" st with
          | Some st ->
              if starts_type (peek st) then
                let ty, st = parse_type st in
                let st = need_sym ")" st in
                (ESizeof ty, st)
              else
                let expr, st = parse_expr st in
                let st = need_sym ")" st in
                (ESizeofExpr expr, st)
          | None ->
              let expr, st = parse_unary st in
              (ESizeofExpr expr, st)
        in
        Some (expr, st)
  in
  let ident_expr st =
    match take_ident st with
    | None -> None
    | Some (name, st) -> (
        match take_sym "(" st with
        | Some st ->
            let args, st = parse_arg_list st in
            Some (ECall (name, args), st)
        | None -> Some (EVar name, st))
  in
  let paren_or_cast st =
    match take_sym "(" st with
    | None -> None
    | Some st ->
        if starts_type (peek st) then
          let ty, st = parse_type st in
          let st = need_sym ")" st in
          let rhs, st = parse_unary st in
          Some (ECast (ty, rhs), st)
        else
          let expr, st = parse_expr st in
          let st = need_sym ")" st in
          Some (expr, st)
  in
  match
    choose_option
      [ int_lit; char_lit; string_lit; init_list; sizeof_expr; ident_expr; paren_or_cast ]
      state
  with
  | Some result -> result
  | None -> raise (Parse_error "expected expression")

and parse_arg_list state =
  match take_sym ")" state with
  | Some state -> ([], state)
  | None ->
      let rec loop st acc =
        let arg, st = parse_expr st in
        match take_sym "," st with
        | Some st -> loop st (arg :: acc)
        | None ->
            let st = need_sym ")" st in
            (List.rev (arg :: acc), st)
      in
      loop state []

and parse_unary state =
  let prefix_update symbol delta st =
    match take_sym symbol st with
    | None -> None
    | Some st ->
        let rhs, st = parse_unary st in
        let expr =
          match rhs with
          | EVar name -> EUpdateExpr (name, delta, true)
          | _ -> EUpdateLvalue (rhs, delta, true)
        in
        Some (expr, st)
  in
  let prefix_unary symbol op st =
    match take_sym symbol st with
    | None -> None
    | Some st ->
        let rhs, st = parse_unary st in
        Some (EUnary (op, rhs), st)
  in
  match
    choose_option
      [
        prefix_update "++" 1;
        prefix_update "--" (-1);
        prefix_unary "!" Not;
        prefix_unary "-" Neg;
        prefix_unary "*" Deref;
        prefix_unary "&" Addr;
      ]
      state
  with
  | Some result -> result
  | None ->
      let expr, state = parse_primary state in
      parse_postfix expr state

and parse_postfix expr state =
  let postfix_tail expr state =
    match take_sym "[" state with
    | Some state ->
        let index, state = parse_expr state in
        let state = need_sym "]" state in
        parse_postfix (EIndex (expr, index)) state
    | None -> (
        match take_sym "." state with
        | Some state ->
            let name, state = need_ident state in
            parse_postfix (EMember (expr, name)) state
        | None -> (
            match take_sym "->" state with
            | Some state ->
                let name, state = need_ident state in
                parse_postfix (EPtrMember (expr, name)) state
            | None -> (expr, state)))
  in
  match expr with
  | EVar name -> (
      match take_sym "++" state with
      | Some state -> (EUpdateExpr (name, 1, false), state)
      | None -> (
          match take_sym "--" state with
          | Some state -> (EUpdateExpr (name, -1, false), state)
          | None -> postfix_tail expr state))
  | _ -> postfix_tail expr state

and binop_of op =
  match op with
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
  let expect_binop =
    satisfy
      (fun tok ->
        match tok with
        | Sym op -> (
            match binop_of op with
            | Some (op, prec) -> if prec >= min_prec then Some (op, prec) else None
            | None -> None)
        | _ -> None)
      "expected binary operator"
  in
  match take_value expect_binop state with
  | Some ((op, prec), state) ->
      let rhs, state = parse_binop (prec + 1) state in
      parse_binop_tail min_prec (EBinary (op, lhs, rhs)) state
  | None -> (lhs, state)

let layout_scalar_size ty =
  match ty with
  | TChar | TSignedChar | TUnsignedChar | TBool -> 1
  | TShort | TUnsignedShort -> 2
  | TInt | TUnsigned | TOther _ -> 4
  | TLong | TLongLong | TUnsignedLong | TUnsignedLongLong | TPtr _ -> 8
  | TDouble -> 8
  | TLongDouble -> 16
  | TVoid -> 1

let layout_align ty =
  min 8 (layout_scalar_size ty)

let const_expr_int expr =
  match expr with
  | EInt n -> n
  | EUnary (Neg, EInt n) -> -n
  | _ -> 1

let layout_field_size ty array_size =
  let count = match array_size with Some expr -> const_expr_int expr | None -> 1 in
  layout_scalar_size ty * count

let build_struct_layout name fields =
  let rec loop offset acc fields =
    match fields with
    | [] -> { struct_name = name; struct_fields = List.rev acc; struct_size = offset }
    | (field_name, ty, array_size) :: rest ->
        let offset = align_up offset (layout_align ty) in
        let field_size = layout_field_size ty array_size in
        loop (offset + field_size) ({ field_name; field_size; field_offset = offset; field_is_array = option_is_some array_size } :: acc) rest
  in
  loop 0 [] fields

let parse_enum_after_keyword state =
  let state =
    match take_ident state with
    | Some (_, state) -> state
    | None -> state
  in
  let state = need_sym "{" state in
  let rec loop st acc =
    match take_sym "}" st with
    | Some st -> (List.rev acc, st)
    | None ->
        let name, st = need_ident st in
        let value, st =
          match take_sym "=" st with
          | Some st ->
              let expr, st = parse_expr st in
              (Some expr, st)
          | None -> (None, st)
        in
        (match take_sym "," st with
        | Some st -> loop st ((name, value) :: acc)
        | None ->
            let st = need_sym "}" st in
            (List.rev ((name, value) :: acc), st))
  in
  loop state []

let parse_enum_decl state =
  let state = need_keyword "enum" state in
  let constants, state = parse_enum_after_keyword state in
  let state = need_sym ";" state in
  (constants, state)

let parse_array_size state =
    match take_sym "[" state with
    | Some state ->
        (match take_sym "]" state with
        | Some state -> (Some (EInt (-1)), state)
        | None ->
            let size, state = parse_expr state in
            let state = need_sym "]" state in
            (Some size, state))
    | None -> (None, state)

let parse_decl_suffix name state =
  let array_size, state =
    parse_array_size state
  in
  let init, state =
    match take_sym "=" state with
    | Some state ->
        let expr, state = parse_expr state in
        (Some expr, state)
    | None -> (None, state)
  in
  (name, init, array_size, state)

let parse_decl_tail state =
  let name, state = need_ident state in
  parse_decl_suffix name state

let parse_decl_after_type state =
  let ty, state = parse_type state in
  let name, init, array_size, state = parse_decl_tail state in
  (SDecl (ty, name, init, array_size), state)

let parse_simple_no_semi state =
  match peek state with
  | Sym ")" | Sym ";" -> (SEmpty, state)
  | tok ->
      if starts_type tok then parse_decl_after_type state
      else
        let expr_stmt st =
          let expr, st = parse_expr st in
          (SExpr expr, st)
        in
        match take_ident state with
        | Some (name, tail_state) ->
            let assign_tail st =
              match take_sym "=" st with
              | Some st ->
                  let expr, st = parse_expr st in
                  Some (SAssign (name, expr), st)
              | None -> None
            in
            let aug_tail symbol op st =
              match take_sym symbol st with
              | Some st ->
                  let expr, st = parse_expr st in
                  Some (SAugAssign (name, op, expr), st)
              | None -> None
            in
            let post_tail symbol delta st =
              match take_sym symbol st with
              | Some st -> Some (SPost (name, delta), st)
              | None -> None
            in
            let call_tail st =
              match take_sym "(" st with
              | Some st ->
                  let args, st = parse_arg_list st in
                  Some (SExpr (ECall (name, args)), st)
              | None -> None
            in
            (match
               choose_option
                 [ assign_tail; aug_tail "+=" Add; aug_tail "-=" Sub; post_tail "++" 1; post_tail "--" (-1); call_tail ]
                 tail_state
             with
            | Some result -> result
            | None -> expr_stmt state)
        | None -> expr_stmt state

let parse_simple_stmt state =
  let simple, state = parse_simple_no_semi state in
  let state = need_sym ";" state in
  (simple, state)

let rec skip_decl tokens pos depth =
  match tokens.(pos) with
  | Eof -> pos
  | Sym ";" -> if depth = 0 then pos + 1 else skip_decl tokens (pos + 1) depth
  | Sym "{" -> skip_decl tokens (pos + 1) (depth + 1)
  | Sym "}" -> if depth > 0 then skip_decl tokens (pos + 1) (depth - 1) else skip_decl tokens (pos + 1) depth
  | _ -> skip_decl tokens (pos + 1) depth

let rec parse_stmt state =
  let typedef_stmt st =
    match take_keyword "typedef" st with
    | None -> None
    | Some st ->
        let ty, st = parse_type st in
        let name, st = need_ident st in
        let st = need_sym ";" st in
        Some (Simple (STypeAlias (ty, name)), st)
  in
  let enum_stmt st =
    match take_keyword "enum" st with
    | None -> None
    | Some st ->
        let constants, st = parse_enum_after_keyword st in
        let st = need_sym ";" st in
        Some (Simple (SEnumDecl constants), st)
  in
  let block_stmt st =
    match take_sym "{" st with
    | Some st ->
        let body, st = parse_block st in
        Some (Block body, st)
    | None -> None
  in
  let return_stmt st =
    match take_keyword "return" st with
    | None -> None
    | Some st -> (
        match take_sym ";" st with
        | Some st -> Some (Return None, st)
        | None ->
            let expr, st = parse_expr st in
            let st = need_sym ";" st in
            Some (Return (Some expr), st))
  in
  let if_stmt st =
    match take_keyword "if" st with
    | None -> None
    | Some st ->
        let st = need_sym "(" st in
        let cond, st = parse_expr st in
        let st = need_sym ")" st in
        let yes, st = parse_stmt st in
        let no, st =
          match take_keyword "else" st with
          | Some st ->
              let no, st = parse_stmt st in
              (Some no, st)
          | None -> (None, st)
        in
        Some (If (cond, yes, no), st)
  in
  let while_stmt st =
    match take_keyword "while" st with
    | None -> None
    | Some st ->
        let st = need_sym "(" st in
        let cond, st = parse_expr st in
        let st = need_sym ")" st in
        let body, st = parse_stmt st in
        Some (While (cond, body), st)
  in
  let do_stmt st =
    match take_keyword "do" st with
    | None -> None
    | Some st ->
        let body, st = parse_stmt st in
        let st = need_keyword "while" st in
        let st = need_sym "(" st in
        let cond, st = parse_expr st in
        let st = need_sym ")" st in
        let st = need_sym ";" st in
        Some (DoWhile (body, cond), st)
  in
  let for_stmt st =
    match take_keyword "for" st with
    | None -> None
    | Some st ->
        let st = need_sym "(" st in
        let init, st =
          match take_sym ";" st with
          | Some st -> (None, st)
          | None ->
              let simple, st = parse_simple_no_semi st in
              let st = need_sym ";" st in
              (Some simple, st)
        in
        let cond, st =
          match take_sym ";" st with
          | Some st -> (None, st)
          | None ->
              let expr, st = parse_expr st in
              let st = need_sym ";" st in
              (Some expr, st)
        in
        let post, st =
          match take_sym ")" st with
          | Some st -> (None, st)
          | None ->
              let simple, st = parse_simple_no_semi st in
              let st = need_sym ")" st in
              (Some simple, st)
        in
        let body, st = parse_stmt st in
        Some (For (init, cond, post, body), st)
  in
  let switch_stmt st =
    match take_keyword "switch" st with
    | None -> None
    | Some st ->
        let st = need_sym "(" st in
        let value, st = parse_expr st in
        let st = need_sym ")" st in
        let st = need_sym "{" st in
        let rec case_body st acc =
          match peek st with
          | Ident "case" | Ident "default" | Sym "}" -> (List.rev acc, st)
          | _ ->
              let stmt, st = parse_stmt st in
              case_body st (stmt :: acc)
        in
        let rec cases st acc =
          match take_sym "}" st with
          | Some st -> (List.rev acc, st)
          | None -> (
              match take_keyword "case" st with
              | Some st ->
                  let label, st = parse_expr st in
                  let st = need_sym ":" st in
                  let body, st = case_body st [] in
                  cases st (SwitchCase (Some label, body) :: acc)
              | None -> (
                  match take_keyword "default" st with
                  | Some st ->
                      let st = need_sym ":" st in
                      let body, st = case_body st [] in
                      cases st (SwitchCase (None, body) :: acc)
                  | None -> raise (Parse_error "expected switch case")))
        in
        let cases, st = cases st [] in
        Some (Switch (value, cases), st)
  in
  let goto_stmt st =
    match take_keyword "goto" st with
    | None -> None
    | Some st ->
        let name, st = need_ident st in
        let st = need_sym ";" st in
        Some (Goto name, st)
  in
  let break_stmt st =
    match take_keyword "break" st with
    | None -> None
    | Some st ->
        let st = need_sym ";" st in
        Some (Break, st)
  in
  let continue_stmt st =
    match take_keyword "continue" st with
    | None -> None
    | Some st ->
        let st = need_sym ";" st in
        Some (ContinueStmt, st)
  in
  let label_stmt st =
    match take_ident st with
    | Some (name, st1) -> (
        match take_sym ":" st1 with
        | Some st -> Some (Label name, st)
        | None -> None)
    | None -> None
  in
  let empty_stmt st =
    match take_sym ";" st with
    | Some st -> Some (Simple SEmpty, st)
    | None -> None
  in
  match
    choose_option
      [
        typedef_stmt;
        enum_stmt;
        block_stmt;
        return_stmt;
        if_stmt;
        while_stmt;
        do_stmt;
        for_stmt;
        switch_stmt;
        goto_stmt;
        break_stmt;
        continue_stmt;
        label_stmt;
        empty_stmt;
      ]
      state
  with
  | Some result -> result
  | None ->
      let simple, state = parse_simple_stmt state in
      (Simple simple, state)

and parse_block state =
  match take_sym "}" state with
  | Some state -> ([], state)
  | None -> (
      match peek state with
      | Eof -> raise (Parse_error "unterminated block")
      | _ ->
          let stmt, state = parse_stmt state in
          let rest, state = parse_block state in
          (stmt :: rest, state))

let parse_params state =
  let state = need_sym "(" state in
  let rec skip_balanced st depth =
    match peek st with
    | Eof -> raise (Parse_error "unterminated function pointer parameter")
    | Sym "(" -> skip_balanced (advance st) (depth + 1)
    | Sym ")" ->
        if depth = 1 then advance st else skip_balanced (advance st) (depth - 1)
    | _ -> skip_balanced (advance st) depth
  in
  let parse_name st =
    match peek st, peek (advance st), peek (advance (advance st)) with
    | Sym "(", Sym "*", Ident name ->
        let st = advance (advance (advance st)) in
        let st = need_sym ")" st in
        let st =
          match peek st with
          | Sym "(" -> skip_balanced st 0
          | _ -> st
        in
        (name, st)
    | _ -> (
        match take_ident st with
        | Some (name, st) -> (name, st)
        | None -> ("_", st))
  in
  let rec parse_nonempty st acc =
    let _ty, st = parse_type st in
    let name, st = parse_name st in
    match take_sym "," st with
    | Some st -> parse_nonempty st (name :: acc)
    | None ->
        let st = need_sym ")" st in
        (List.rev (name :: acc), st)
  in
  match take_sym ")" state with
  | Some state -> ([], state)
  | None -> (
      match take_keyword "void" state with
      | Some state_after_void -> (
          match take_sym ")" state_after_void with
          | Some state -> ([], state)
          | None -> parse_nonempty state [])
      | None -> parse_nonempty state [])

let parse_function_tail name params ret_type state =
  match take_sym ";" state with
  | Some state -> (None, state)
  | None -> (
      match take_sym "{" state with
      | Some state ->
          let body, state = parse_block state in
          (Some { name; params; body; ret_type }, state)
      | None -> raise (Parse_error "expected function body"))

let parse_function state =
  let ret_type, state = parse_type state in
  let name, state = need_ident state in
  let params, state = parse_params state in
  parse_function_tail name params ret_type state

type external_decl = ExternalFunc of func option | ExternalGlobal of global_decl

let parse_external_decl state =
  let ty, state = parse_type state in
  let name, state = need_ident state in
  match take_sym "(" state with
  | Some _ ->
      let params, state = parse_params state in
      let func, state = parse_function_tail name params ty state in
      (ExternalFunc func, state)
  | None ->
      let name, init, array_size, state = parse_decl_suffix name state in
      let state = need_sym ";" state in
      (ExternalGlobal { global_type = ty; global_name = name; global_init = init; global_array_size = array_size }, state)

let parse_struct_definition state =
  let state = need_keyword "struct" state in
  let name, state = need_ident state in
  let state = need_sym "{" state in
  let rec loop st acc =
    match take_sym "}" st with
    | Some st ->
        let st = need_sym ";" st in
        (build_struct_layout name (List.rev acc), st)
    | None ->
        let ty, st = parse_type st in
        let field, st = need_ident st in
        let array_size, st =
          parse_array_size st
        in
        let st = need_sym ";" st in
        loop st ((field, ty, array_size) :: acc)
  in
  loop state []

let parse_typedef_struct_definition state =
  let state = need_keyword "typedef" state in
  let state = need_keyword "struct" state in
  let tag, state =
    match take_ident state with
    | Some (name, state) -> (name, state)
    | None -> (
        match peek state with
        | Sym "{" -> ("", state)
        | _ -> raise (Parse_error "expected struct name"))
  in
  let state = need_sym "{" state in
  let rec fields st acc =
    match take_sym "}" st with
    | Some st -> (List.rev acc, st)
    | None ->
        let ty, st = parse_type st in
        let field, st = need_ident st in
        let array_size, st =
          parse_array_size st
        in
        let st = need_sym ";" st in
        fields st ((field, ty, array_size) :: acc)
  in
  let fields, state = fields state [] in
  let alias, state = need_ident state in
  let state = need_sym ";" state in
  let layout = build_struct_layout alias fields in
  let tag_layout = if tag = "" then None else Some { layout with struct_name = tag } in
  (tag_layout, layout, state)

let rec assoc_int name env =
  match env with
  | [] -> fail ("unknown enum constant: " ^ name)
  | (key, value) :: rest -> if key = name then value else assoc_int name rest

let rec eval_enum_expr env expr =
  match expr with
  | EInt n -> n
  | EVar name -> assoc_int name env
  | EBinary (Add, a, b) -> eval_enum_expr env a + eval_enum_expr env b
  | EBinary (Sub, a, b) -> eval_enum_expr env a - eval_enum_expr env b
  | EBinary (Mul, a, b) -> eval_enum_expr env a * eval_enum_expr env b
  | EBinary (Div, a, b) -> eval_enum_expr env a / eval_enum_expr env b
  | EBinary (Mod, a, b) -> eval_enum_expr env a mod eval_enum_expr env b
  | EBinary (Shl, a, b) -> shift_left_u32 (eval_enum_expr env a) (eval_enum_expr env b)
  | EBinary (Shr, a, b) -> shift_right_u32 (eval_enum_expr env a) (eval_enum_expr env b)
  | EUnary (Neg, e) -> - eval_enum_expr env e
  | _ -> fail "unsupported enum initializer"

let add_enum_constants env constants =
  let rec loop next_value env constants =
    match constants with
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

let is_struct_definition_start state =
  match peek state with
  | Ident "struct" -> (
      match peek (advance state) with
      | Ident _ -> peek (advance (advance state)) = Sym "{"
      | _ -> false)
  | _ -> false

let is_typedef_struct_definition_start state =
  match peek state with
  | Ident "typedef" -> (
      match peek (advance state) with
      | Ident "struct" -> (
          match peek (advance (advance state)) with
          | Ident _ -> peek (advance (advance (advance state))) = Sym "{"
          | Sym "{" -> true
          | _ -> false)
      | _ -> false)
  | _ -> false

let parse_program tokens initial_constants =
  let rec loop state constants structs globals funcs =
    let parse_external_or_skip state constants structs globals funcs =
      try
        (match parse_external_decl state with
        | ExternalFunc (Some fn), state -> loop state constants structs globals (fn :: funcs)
        | ExternalFunc None, state -> loop state constants structs globals funcs
        | ExternalGlobal global, state -> loop state constants structs (global :: globals) funcs)
      with
      | Parse_error msg ->
          if not (external_is_named_function state) then
            loop { state with pos = skip_decl state.tokens state.pos 0 } constants structs globals funcs
          else raise (Parse_error msg)
    in
    match peek state with
    | Eof -> { constants; structs = List.rev structs; globals = List.rev globals; funcs = List.rev funcs }
    | Ident "enum" ->
        if peek (advance state) = Sym "{" then
          let enum_constants, state = parse_enum_decl state in
          let constants = add_enum_constants constants enum_constants in
          loop state constants structs globals funcs
        else
          loop { state with pos = skip_decl state.tokens state.pos 0 } constants structs globals funcs
    | Ident "struct" ->
        if is_struct_definition_start state then
          let layout, state = parse_struct_definition state in
          loop state constants (layout :: structs) globals funcs
        else parse_external_or_skip state constants structs globals funcs
    | Ident "typedef" ->
        if is_typedef_struct_definition_start state then
          let tag_layout, alias_layout, state = parse_typedef_struct_definition state in
          let structs = alias_layout :: structs in
          let structs = match tag_layout with Some layout -> layout :: structs | None -> structs in
          loop state constants structs globals funcs
        else loop { state with pos = skip_decl state.tokens state.pos 0 } constants structs globals funcs
    | tok ->
        if starts_type tok then
          parse_external_or_skip state constants structs globals funcs
        else loop (advance state) constants structs globals funcs
  in
  loop { tokens; pos = 0 } initial_constants [] [] []

let truth n = n <> 0
let bool_int b = if b then 1 else 0

let rec sizeof_type ty =
  match ty with
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
  bind_bytes : value array option;
  bind_fields : (string * value ref) list ref option;
}

type env = binding list

let int_of_value value =
  match value with
  | VInt value -> value
  | VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _ -> fail "pointer used as integer"

let coerce_int ty value =
  match ty with
  | TUnsignedChar -> unsigned_mod value 256
  | TUnsignedShort -> unsigned_mod value 65536
  | TSignedChar | TChar ->
      let b = unsigned_mod value 256 in
      if b > 127 then b - 256 else b
  | TUnsigned -> value
  | TBool -> bool_int (truth value)
  | _ -> value

let coerce_value ty value =
  match value with
  | VInt value -> VInt (coerce_int ty value)
  | (VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _) as ptr -> ptr

let rec find_binding name env =
  match env with
  | [] -> fail ("unknown variable: " ^ name)
  | binding :: rest -> if binding.bind_name = name then binding else find_binding name rest

let rec find_binding_opt name env =
  match env with
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

let assoc_decl_full text array bytes ty name value env =
  let fields =
    match ty with
    | TOther _ -> Some (ref [])
    | _ -> None
  in
  { bind_name = name; bind_type = ty; bind_value = ref (coerce_value ty value); bind_string = text; bind_array = array; bind_bytes = bytes; bind_fields = fields }
  :: env

let assoc_decl_value ty name value env =
  assoc_decl_full None None None ty name value env

type control = Continue of env | Returned of value | Jumped of string * env | Broke of env | Continued of env

let string_byte text pos =
  if pos < 0 || pos >= String.length text then 0 else Char.code text.[pos]

let rec read_binding_index binding index =
  match binding.bind_array, binding.bind_string, !(binding.bind_value) with
  | Some values, _, _ ->
      if index < 0 || index >= Array.length values then VInt 0 else values.(index)
  | None, Some text, _ -> VInt (string_byte text index)
  | None, None, VArrayPtr (target, base) -> read_binding_index target (base + index)
  | None, None, VFieldPtr (target, base) -> (
      match target.bind_bytes with
      | Some values -> if base + index < 0 || base + index >= Array.length values then VInt 0 else values.(base + index)
      | None -> fail ("not a byte-addressable value: " ^ target.bind_name))
  | None, None, VStringPtr (text, base) -> VInt (string_byte text (base + index))
  | None, None, _ -> fail ("not an indexable value: " ^ binding.bind_name)

let read_binding_byte binding index =
  match binding.bind_bytes with
  | Some values -> if index < 0 || index >= Array.length values then VInt 0 else values.(index)
  | None -> fail ("not a byte-addressable value: " ^ binding.bind_name)

let rec write_binding_index binding index value =
  match binding.bind_array, !(binding.bind_value) with
  | Some values, _ ->
      if index < 0 || index >= Array.length values then fail ("array index out of bounds: " ^ binding.bind_name);
      let value = coerce_value binding.bind_type value in
      values.(index) <- value;
      value
  | None, VArrayPtr (target, base) -> write_binding_index target (base + index) value
  | None, VFieldPtr (target, base) -> (
      match target.bind_bytes with
      | Some values ->
          let index = base + index in
          if index < 0 || index >= Array.length values then fail ("byte index out of bounds: " ^ target.bind_name);
          let value = coerce_value TUnsignedChar value in
          values.(index) <- value;
          value
      | None -> fail ("not a writable byte value: " ^ target.bind_name))
  | None, _ -> fail ("not a writable array: " ^ binding.bind_name)

let write_binding_byte binding index value =
  match binding.bind_bytes with
  | Some values ->
      if index < 0 || index >= Array.length values then fail ("byte index out of bounds: " ^ binding.bind_name);
      let value = coerce_value TUnsignedChar value in
      values.(index) <- value;
      value
  | None -> fail ("not a writable byte value: " ^ binding.bind_name)

let read_pointer ptr =
  match ptr with
  | VPtr target -> !(target.bind_value)
  | VArrayPtr (target, offset) -> read_binding_index target offset
  | VFieldPtr (target, offset) -> read_binding_byte target offset
  | VStringPtr (text, offset) -> VInt (string_byte text offset)
  | VInt _ | VFunc _ -> fail "not a pointer"

let write_pointer ptr value =
  match ptr with
  | VPtr target ->
      target.bind_value := coerce_value target.bind_type value;
      value
  | VArrayPtr (target, offset) -> write_binding_index target offset value
  | VFieldPtr (target, offset) -> write_binding_byte target offset value
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
  match list_find_opt (fun (field, _) -> field = name) !(fields) with
  | Some (_, cell) -> cell
  | None ->
      let cell = ref (VInt 0) in
      fields := !(fields) @ [ (name, cell) ];
      cell

let binding_fields binding =
  match binding.bind_fields with
  | Some fields -> fields
  | None -> fail ("not a struct value: " ^ binding.bind_name)

let copy_struct_fields target source =
  let target_fields = binding_fields target in
  List.iter
    (fun (field, source_cell) ->
      let target_cell = field_cell target_fields field in
      target_cell := !(source_cell))
    !(binding_fields source)

let struct_binding_from_pointer ptr =
  match ptr with
  | VPtr binding -> Some binding
  | VFieldPtr (binding, 0) -> Some binding
  | _ -> None

let struct_name_of_type ty =
  match ty with
  | TOther name ->
      if has_prefix "struct " name then Some (String.sub name 7 (String.length name - 7))
      else Some name
  | _ -> None

let struct_fields structs ty =
  match struct_name_of_type ty with
  | None -> []
  | Some name -> (
      match list_find_opt (fun layout -> layout.struct_name = name) structs with
      | Some layout -> List.map (fun field -> field.field_name) layout.struct_fields
      | None -> [])

let struct_size structs ty =
  match struct_name_of_type ty with
  | None -> None
  | Some name -> (
      match list_find_opt (fun layout -> layout.struct_name = name) structs with
      | Some layout -> Some layout.struct_size
      | None -> None)

let struct_field_offset structs ty field_name =
  match struct_name_of_type ty with
  | None -> None
  | Some name -> (
      match list_find_opt (fun layout -> layout.struct_name = name) structs with
      | None -> None
      | Some layout -> (
          match list_find_opt (fun field -> field.field_name = field_name) layout.struct_fields with
          | Some field -> Some field.field_offset
          | None -> None))

let struct_field_layout structs ty field_name =
  match struct_name_of_type ty with
  | None -> None
  | Some name -> (
      match list_find_opt (fun layout -> layout.struct_name = name) structs with
      | None -> None
      | Some layout -> list_find_opt (fun field -> field.field_name = field_name) layout.struct_fields)

let struct_field_size structs ty field_name =
  match struct_name_of_type ty with
  | None -> None
  | Some name -> (
      match list_find_opt (fun layout -> layout.struct_name = name) structs with
      | None -> None
      | Some layout -> (
          match list_find_opt (fun field -> field.field_name = field_name) layout.struct_fields with
          | Some field -> Some field.field_size
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

let truth_value value =
  match value with
  | VInt n -> truth n
  | VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _ -> true

let pointer_delta a b =
  match (a, b) with
  | VFieldPtr (x, ix), VFieldPtr (y, iy) -> if x == y then Some (ix - iy) else None
  | VArrayPtr (x, ix), VArrayPtr (y, iy) -> if x == y then Some (ix - iy) else None
  | VStringPtr (x, ix), VStringPtr (y, iy) -> if x = y then Some (ix - iy) else None
  | _ -> None

let pointer_compare a b =
  match pointer_delta a b with
  | Some delta -> Some (compare delta 0)
  | None -> None

let add_values a b =
  match (a, b) with
  | VInt x, VInt y -> VInt (x + y)
  | (VArrayPtr _ | VFieldPtr _ | VStringPtr _ as ptr), VInt n -> add_to_value ptr n
  | VInt n, (VArrayPtr _ | VFieldPtr _ | VStringPtr _ as ptr) -> add_to_value ptr n
  | _ -> fail "unsupported addition"

let sub_values a b =
  match (a, b) with
  | VInt x, VInt y -> VInt (x - y)
  | (VArrayPtr _ | VFieldPtr _ | VStringPtr _ as ptr), VInt n -> add_to_value ptr (-n)
  | _ -> (
      match pointer_delta a b with Some delta -> VInt delta | None -> fail "unsupported subtraction")

let rec eval_value funcs structs globals env expr =
  match expr with
  | EInt n -> VInt n
  | EString s -> VStringPtr (s, 0)
  | EInitList _ -> VInt 0
  | EVar name ->
      (match find_binding_opt name env with
      | Some binding -> (match binding.bind_array with Some _ -> VArrayPtr (binding, 0) | None -> !(binding.bind_value))
      | None -> if List.exists (fun fn -> fn.name = name) funcs then VFunc name else fail ("unknown variable: " ^ name))
  | ESizeof (TOther name) -> (
      match struct_size structs (TOther name) with
      | Some size -> VInt size
      | None -> (
          try VInt (assoc_find name env) with Compile_error _ -> VInt 4))
  | ESizeof ty -> VInt (match struct_size structs ty with Some size -> size | None -> sizeof_type ty)
  | ESizeofExpr expr -> VInt (sizeof_expr funcs structs globals env expr)
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
      (match struct_field_layout structs binding.bind_type field with
      | Some layout ->
          if layout.field_is_array then VFieldPtr (binding, layout.field_offset)
          else !(field_cell (binding_fields binding) field)
      | None -> !(field_cell (binding_fields binding) field))
  | EPtrMember (base, field) ->
      eval_value funcs structs globals env (EMember (EUnary (Deref, base), field))
  | EAssignExpr (name, expr) ->
      let target = find_binding name env in
      (match target.bind_fields, expr with
      | Some _, EUnary (Deref, ptr_expr) -> (
          match struct_binding_from_pointer (eval_value funcs structs globals env ptr_expr) with
          | Some source ->
              copy_struct_fields target source;
              VInt 0
          | None ->
              let value = eval_value funcs structs globals env expr in
              let _ = assoc_set_value name value env in
              !(target.bind_value))
      | _ ->
          let value = eval_value funcs structs globals env expr in
          let _ = assoc_set_value name value env in
          !(target.bind_value))
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
  | EUpdateLvalue (target, delta, prefix) ->
      let cell =
        match target with
        | EMember (EVar name, field) ->
            field_cell (binding_fields (find_binding name env)) field
        | EPtrMember (base, field) ->
            let binding =
              match eval_value funcs structs globals env base with
              | VPtr target | VFieldPtr (target, 0) -> target
              | _ -> fail "not a struct pointer"
            in
            field_cell (binding_fields binding) field
        | _ -> fail "unsupported update target"
      in
      let old_value = !(cell) in
      let new_value = add_to_value old_value delta in
      cell := new_value;
      if prefix then new_value else old_value
  | EUnary (Neg, e) -> VInt (- eval_expr funcs structs globals env e)
  | EUnary (Not, e) -> VInt (bool_int (not (truth_value (eval_value funcs structs globals env e))))
  | ECond (cond, yes, no) ->
      if truth_value (eval_value funcs structs globals env cond) then eval_value funcs structs globals env yes else eval_value funcs structs globals env no
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
      VInt (if truth_value (eval_value funcs structs globals env a) then bool_int (truth_value (eval_value funcs structs globals env b)) else 0)
  | EBinary (Lor, a, b) ->
      VInt (if truth_value (eval_value funcs structs globals env a) then 1 else bool_int (truth_value (eval_value funcs structs globals env b)))
  | EBinary (Eq, a, b) ->
      VInt (bool_int (value_equal (eval_value funcs structs globals env a) (eval_value funcs structs globals env b)))
  | EBinary (Ne, a, b) ->
      VInt (bool_int (not (value_equal (eval_value funcs structs globals env a) (eval_value funcs structs globals env b))))
  | EBinary (Add, a, b) -> add_values (eval_value funcs structs globals env a) (eval_value funcs structs globals env b)
  | EBinary (Sub, a, b) -> sub_values (eval_value funcs structs globals env a) (eval_value funcs structs globals env b)
  | EBinary ((Lt | Le | Gt | Ge) as op, a, b) ->
      let av = eval_value funcs structs globals env a in
      let bv = eval_value funcs structs globals env b in
      let cmp = match pointer_compare av bv with Some cmp -> cmp | None -> compare (int_of_value av) (int_of_value bv) in
      VInt
        (bool_int
           (match op with
           | Lt -> cmp < 0
           | Le -> cmp <= 0
           | Gt -> cmp > 0
           | Ge -> cmp >= 0
           | _ -> assert false))
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
      | Shl -> shift_left_u32 x y
      | Shr -> shift_right_u32 x y
      | Land | Lor -> assert false)
  | ECall ("_exit", [ arg ]) -> VInt (eval_expr funcs structs globals env arg)
  | ECall (name, args) ->
      let values = List.map (call_arg funcs structs globals env) args in
      let target =
        match find_binding_opt name env with
        | Some binding -> (match !(binding.bind_value) with VFunc target -> target | _ -> name)
        | None -> name
      in
      eval_func funcs structs globals target values

and sizeof_expr funcs structs globals env expr =
  match expr with
  | EVar name -> (
      match find_binding_opt name env with
      | Some { bind_array = Some values; _ } -> Array.length values
      | _ -> (
          match eval_value funcs structs globals env (EVar name) with
          | VInt _ -> 4
          | VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _ -> 8))
  | EMember (EVar name, field) ->
      let binding = find_binding name env in
      (match struct_field_size structs binding.bind_type field with Some size -> size | None -> 4)
  | EPtrMember (EVar name, field) -> (
      let binding = find_binding name env in
      match binding.bind_type with
      | TPtr ty -> (match struct_field_size structs ty field with Some size -> size | None -> 4)
      | _ -> (
          match eval_value funcs structs globals env (EVar name) with
          | VPtr binding | VFieldPtr (binding, 0) -> (
              match struct_field_size structs binding.bind_type field with Some size -> size | None -> 4)
          | _ -> 4))
  | EPtrMember (base, field) -> (
      match eval_value funcs structs globals env base with
      | VPtr binding | VFieldPtr (binding, 0) -> (
          match struct_field_size structs binding.bind_type field with Some size -> size | None -> 4)
      | _ -> 4)
  | EIndex _ -> 1
  | expr -> (
      match eval_value funcs structs globals env expr with
      | VInt _ -> 4
      | VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _ -> 8)

and eval_expr funcs structs globals env expr = int_of_value (eval_value funcs structs globals env expr)

and call_arg funcs structs globals env expr =
  eval_value funcs structs globals env expr

and eval_func funcs structs globals name args =
  let fn =
    match list_find_opt (fun fn -> fn.name = name) funcs with
    | Some fn -> fn
    | None -> fail ("unknown function: " ^ name)
  in
  let env =
    List.map2
      (fun param value ->
        { bind_name = param; bind_type = TInt; bind_value = ref value; bind_string = None; bind_array = None; bind_bytes = None; bind_fields = None })
      fn.params args
    @ globals
  in
  let env = assoc_decl_full (Some name) None None (TPtr TChar) "__func__" (VStringPtr (name, 0)) env in
  match exec_block funcs structs globals fn.body env with
  | Returned value -> coerce_value fn.ret_type value
  | Continue _ -> VInt 0
  | Jumped (label, _) -> fail ("unresolved goto: " ^ label)
  | Broke _ -> fail "break outside loop"
  | Continued _ -> fail "continue outside loop"

and exec_simple funcs structs globals env simple =
  match simple with
  | SEmpty -> env
  | SExpr (ECall ("_exit", [ arg ])) -> raise (Exit_code (eval_expr funcs structs globals env arg))
  | SExpr (ECall (name, _) as expr) ->
      if list_find_opt (fun fn -> fn.name = name) funcs = None then env
      else
        let _ = eval_value funcs structs globals env expr in
        env
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
      let bytes =
        match struct_size structs ty with
        | Some size -> Some (Array.make size (VInt 0))
        | None -> None
      in
      let text = match init with Some (EString text) -> Some text | _ -> None in
      let env = assoc_decl_full text array bytes ty name value env in
      (match init with
      | Some (EInitList values) ->
          let binding = find_binding name env in
          (match binding.bind_array with
          | Some array ->
              let rec fill i values =
                match values with
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
  | STypeAlias (ty, name) -> assoc_decl_value TInt name (VInt (sizeof_type ty)) env
  | SEnumDecl constants ->
      let rec loop next_value env constants =
        match constants with
        | [] -> env
        | (name, expr) :: rest ->
            let value = match expr with Some expr -> eval_expr funcs structs globals env expr | None -> next_value in
            loop (value + 1) (assoc_decl_value TInt name (VInt value) env) rest
      in
      loop 0 env constants
  | SAssign (name, expr) ->
      let target = find_binding name env in
      (match target.bind_fields, expr with
      | Some _, EUnary (Deref, ptr_expr) -> (
          match struct_binding_from_pointer (eval_value funcs structs globals env ptr_expr) with
          | Some source ->
              copy_struct_fields target source;
              env
          | None -> assoc_set_value name (eval_value funcs structs globals env expr) env)
      | _ -> assoc_set_value name (eval_value funcs structs globals env expr) env)
  | SAugAssign (name, op, expr) ->
      let old = assoc_find name env in
      let delta = eval_expr funcs structs globals env expr in
      let value = match op with Add -> old + delta | Sub -> old - delta | _ -> fail "bad compound assignment" in
      assoc_set name value env
  | SPost (name, delta) ->
      let binding = find_binding name env in
      binding.bind_value := coerce_value binding.bind_type (add_to_value !(binding.bind_value) delta);
      env

and exec_stmt funcs structs globals env stmt =
  match stmt with
  | Simple simple -> (
      try Continue (exec_simple funcs structs globals env simple) with Exit_code code -> Returned (VInt code))
  | Return None -> Returned (VInt 0)
  | Return (Some expr) -> Returned (eval_value funcs structs globals env expr)
  | Goto label -> Jumped (label, env)
  | Label _ -> Continue env
  | Break -> Broke env
  | ContinueStmt -> Continued env
  | Block body -> (
      match exec_block funcs structs globals body env with
      | Continue _ -> Continue env
      | Jumped (label, _) -> Jumped (label, env)
      | Broke _ -> Broke env
      | Continued _ -> Continued env
      | Returned _ as ret -> ret)
  | If (cond, yes, no) ->
      if truth_value (eval_value funcs structs globals env cond) then exec_stmt funcs structs globals env yes
      else (
        match no with Some stmt -> exec_stmt funcs structs globals env stmt | None -> Continue env)
  | While (cond, body) ->
      let rec loop env =
        if truth_value (eval_value funcs structs globals env cond) then
          match exec_stmt funcs structs globals env body with
          | Continue env' -> loop env'
          | Continued env' -> loop env'
          | Broke env' -> Continue env'
          | other -> other
        else Continue env
      in
      loop env
  | DoWhile (body, cond) ->
      let rec loop env =
        match exec_stmt funcs structs globals env body with
        | Continue env' -> if truth_value (eval_value funcs structs globals env' cond) then loop env' else Continue env'
        | Continued env' -> if truth_value (eval_value funcs structs globals env' cond) then loop env' else Continue env'
        | Broke env' -> Continue env'
        | other -> other
      in
      loop env
  | For (init, cond, post, body) ->
      let env = match init with Some s -> exec_simple funcs structs globals env s | None -> env in
      let rec loop env =
        let go = match cond with Some e -> truth_value (eval_value funcs structs globals env e) | None -> true in
        if go then
          match exec_stmt funcs structs globals env body with
          | Continue env' ->
              let env'' = match post with Some s -> exec_simple funcs structs globals env' s | None -> env' in
              loop env''
          | Continued env' ->
              let env'' = match post with Some s -> exec_simple funcs structs globals env' s | None -> env' in
              loop env''
          | Broke env' -> Continue env'
          | other -> other
        else Continue env
      in
      loop env
  | Switch (value, cases) ->
      let switch_value = eval_expr funcs structs globals env value in
      let rec select default cases =
        match cases with
        | [] -> (
            match default with
            | Some cases -> cases
            | None -> [])
        | (SwitchCase (label, _) as current) :: rest -> (
            match label with
            | Some expr ->
                if eval_expr funcs structs globals env expr = switch_value then current :: rest else select default rest
            | None -> select (Some (current :: rest)) rest)
      in
      let rec run cases env =
        match cases with
        | [] -> Continue env
        | SwitchCase (_, body) :: rest -> (
            match exec_block funcs structs globals body env with
            | Continue env -> run rest env
            | Broke env -> Continue env
            | Jumped _ as jumped -> jumped
            | Continued _ as continued -> continued
            | Returned _ as returned -> returned)
      in
      run (select None cases) env

and exec_block funcs structs globals stmts env =
  let label_index label =
    let rec loop i stmts =
      match stmts with
      | [] -> None
      | Label name :: rest -> if name = label then Some (i + 1) else loop (i + 1) rest
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
      | Broke _ as broke -> broke
      | Continued _ as continued -> continued
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
  let src, constants = preprocess_source src in
  let tokens = lex src in
  let program = parse_program tokens constants in
  if not (List.exists (fun fn -> fn.name = "main") program.funcs) then m1_of_exit 0
  else
  let constants =
    List.map
      (fun (name, value) ->
        { bind_name = name; bind_type = TInt; bind_value = ref (VInt value); bind_string = None; bind_array = None; bind_bytes = None; bind_fields = None })
      program.constants
  in
  let globals =
    List.fold_left
      (fun env global ->
        exec_simple program.funcs program.structs env env (SDecl (global.global_type, global.global_name, global.global_init, global.global_array_size)))
      constants program.globals
  in
  m1_of_exit (int_of_value (eval_func program.funcs program.structs globals "main" []))

let read_stdin () =
  let rec loop acc =
    let next = try Some (input_char stdin) with End_of_file -> None in
    match next with
    | Some ch -> loop (ch :: acc)
    | None -> string_of_rev_chars acc
  in
  loop []

let () =
  try print_string (compile (read_stdin ())) with
  | Parse_error msg ->
      prerr_endline ("ccc-host-ocaml: parse error: " ^ msg);
      exit 1
  | Compile_error msg ->
      prerr_endline ("ccc-host-ocaml: compile error: " ^ msg);
      exit 1
