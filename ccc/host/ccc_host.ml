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

let rec same_length xs ys =
  match (xs, ys) with
  | [], [] -> true
  | _ :: xs, _ :: ys -> same_length xs ys
  | _ -> false

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

let bitwise_combine choose x y =
  let rec loop count x y place acc =
    if count <= 0 then unsigned_mod acc 4294967296
    else
      let xb = unsigned_mod x 2 in
      let yb = unsigned_mod y 2 in
      let bit = if choose xb yb then place else 0 in
      loop (count - 1) (x / 2) (y / 2) (place * 2) (acc + bit)
  in
  loop 32 (unsigned_mod x 4294967296) (unsigned_mod y 4294967296) 1 0

let bitwise_or x y =
  bitwise_combine (fun xb yb -> xb <> 0 || yb <> 0) x y

let bitwise_and x y =
  bitwise_combine (fun xb yb -> xb <> 0 && yb <> 0) x y

let bitwise_xor x y =
  bitwise_combine (fun xb yb -> (xb <> 0 && yb = 0) || (xb = 0 && yb <> 0)) x y

let bitwise_not x =
  bitwise_xor x 4294967295

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
  let rec float_suffix p =
    if p < len then
      match src.[p] with
      | 'f' | 'F' | 'l' | 'L' -> float_suffix (p + 1)
      | _ -> p
    else p
  in
  let rec decimal_digits p =
    if p < len && is_digit src.[p] then decimal_digits (p + 1) else p
  in
  let exponent p =
    if p < len && (src.[p] = 'e' || src.[p] = 'E') then
      let p = p + 1 in
      let p =
        if p < len && (src.[p] = '+' || src.[p] = '-') then p + 1 else p
      in
      decimal_digits p
    else p
  in
  let float_tail p =
    let after_dot =
      if p < len && src.[p] = '.' then decimal_digits (p + 1) else p
    in
    let after_exp = exponent after_dot in
    if after_dot <> p || after_exp <> after_dot then Some (float_suffix after_exp) else None
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
      else
        match float_tail p with
        | Some p -> (Int_lit 0, p)
        | None -> (Int_lit acc, suffix p)
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

let rec remove_define name defs =
  match defs with
  | [] -> []
  | (key, value) :: rest ->
      if key = name then remove_define name rest
      else (key, value) :: remove_define name rest

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

let rec define_value name defs =
  match defs with
  | [] -> 0
  | (key, value) :: rest -> if key = name then value else define_value name rest

let parse_directive_identifier src pos =
  let pos = skip_hspace src pos in
  if pos < String.length src && is_alpha src.[pos] then
    let rec ident_end p = if p < String.length src && is_ident src.[p] then ident_end (p + 1) else p in
    let stop = ident_end (pos + 1) in
    Some (String.sub src pos (stop - pos), stop)
  else None

let parse_defined_expr defs src pos =
  let pos = skip_hspace src pos in
  let pos, close =
    if pos < String.length src && src.[pos] = '(' then (skip_hspace src (pos + 1), true) else (pos, false)
  in
  match parse_directive_identifier src pos with
  | None -> (false, pos)
  | Some (name, pos) ->
      let pos = skip_hspace src pos in
      if close then
        if pos < String.length src && src.[pos] = ')' then (define_exists name defs, pos + 1)
        else (false, pos)
      else (define_exists name defs, pos)

let eval_defined_expr defs src pos =
  let value, _ = parse_defined_expr defs src pos in
  value

let rec parse_preprocessor_primary defs src pos =
  let pos = skip_hspace src pos in
  if pos < String.length src && src.[pos] = '!' then
    let value, pos = parse_preprocessor_primary defs src (pos + 1) in
    (not value, pos)
  else if pos < String.length src && src.[pos] = '(' then
    let value, pos = parse_preprocessor_or defs src (pos + 1) in
    let pos = skip_hspace src pos in
    if pos < String.length src && src.[pos] = ')' then (value, pos + 1) else (value, pos)
  else if directive_word_at "defined" src pos then
    parse_defined_expr defs src (pos + 7)
  else if pos < String.length src && src.[pos] = '\'' then
    (match lex_char src pos with Char_lit value, pos -> (value <> 0, pos) | _ -> (false, pos))
  else if pos < String.length src && src.[pos] = '-' then (
    match lex_number src (pos + 1) with Int_lit value, pos -> (-value <> 0, pos) | _ -> (false, pos))
  else if pos < String.length src && is_digit src.[pos] then (
    match lex_number src pos with Int_lit value, pos -> (value <> 0, pos) | _ -> (false, pos))
  else
    match parse_directive_identifier src pos with
    | Some (name, pos) -> (define_value name defs <> 0, pos)
    | None -> (false, pos)

and parse_preprocessor_and defs src pos =
  let value, pos = parse_preprocessor_primary defs src pos in
  let rec loop value pos =
    let pos = skip_hspace src pos in
    if pos + 1 < String.length src && src.[pos] = '&' && src.[pos + 1] = '&' then
      let right, pos = parse_preprocessor_primary defs src (pos + 2) in
      loop (value && right) pos
    else (value, pos)
  in
  loop value pos

and parse_preprocessor_or defs src pos =
  let value, pos = parse_preprocessor_and defs src pos in
  let rec loop value pos =
    let pos = skip_hspace src pos in
    if pos + 1 < String.length src && src.[pos] = '|' && src.[pos + 1] = '|' then
      let right, pos = parse_preprocessor_and defs src (pos + 2) in
      loop (value || right) pos
    else (value, pos)
  in
  loop value pos

let eval_preprocessor_if defs src pos =
  let value, _ = parse_preprocessor_or defs src pos in
  value

let directive_expr_pos word src hash_pos =
  skip_hspace src (skip_hspace src (hash_pos + 1) + String.length word)

let rec skip_inactive_conditional src pos depth =
  if pos >= String.length src then pos
  else
    let first = skip_hspace src pos in
    let next = skip_line src pos in
    if first < String.length src && src.[first] = '#' then
      if directive_at "ifdef" src first || directive_at "ifndef" src first || directive_at "if" src first then
        skip_inactive_conditional src next (depth + 1)
      else if directive_at "endif" src first then
        if depth = 0 then next else skip_inactive_conditional src next (depth - 1)
      else if (directive_at "elif" src first || directive_at "else" src first) && depth = 0 then next
      else skip_inactive_conditional src next depth
    else skip_inactive_conditional src next depth

let rec select_inactive_conditional src pos defs depth =
  if pos >= String.length src then pos
  else
    let first = skip_hspace src pos in
    let next = skip_line src pos in
    if first < String.length src && src.[first] = '#' then
      if directive_at "ifdef" src first || directive_at "ifndef" src first || directive_at "if" src first then
        select_inactive_conditional src next defs (depth + 1)
      else if directive_at "endif" src first then
        if depth = 0 then next else select_inactive_conditional src next defs (depth - 1)
      else if directive_at "elif" src first && depth = 0 then
        if eval_preprocessor_if defs src (directive_expr_pos "elif" src first) then next
        else select_inactive_conditional src next defs depth
      else if directive_at "else" src first && depth = 0 then next
      else select_inactive_conditional src next defs depth
    else select_inactive_conditional src next defs depth

let rec skip_active_else src pos depth =
  if pos >= String.length src then pos
  else
    let first = skip_hspace src pos in
    let next = skip_line src pos in
    if first < String.length src && src.[first] = '#' then
      if directive_at "ifdef" src first || directive_at "ifndef" src first || directive_at "if" src first then
        skip_active_else src next (depth + 1)
      else if directive_at "endif" src first then
        if depth = 0 then next else skip_active_else src next (depth - 1)
      else if (directive_at "elif" src first || directive_at "else" src first) && depth = 0 then
        skip_active_else src next depth
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
        else if directive_at "undef" src first then (
          match directive_name "undef" src first with
          | Some name -> loop next (remove_define name defs) acc
          | None -> loop next defs acc)
        else if directive_at "ifdef" src first then (
          match directive_name "ifdef" src first with
          | Some name ->
              if define_exists name defs then loop next defs acc else loop (select_inactive_conditional src next defs 0) defs acc
          | None -> loop next defs acc)
        else if directive_at "ifndef" src first then (
          match directive_name "ifndef" src first with
          | Some name ->
              if define_exists name defs then loop (select_inactive_conditional src next defs 0) defs acc else loop next defs acc
          | None -> loop next defs acc)
        else if directive_at "if" src first then
          if eval_preprocessor_if defs src (skip_hspace src (first + 1) + 2) then loop next defs acc
          else loop (select_inactive_conditional src next defs 0) defs acc
        else if directive_at "elif" src first then
          loop (skip_active_else src next 0) defs acc
        else if directive_at "else" src first then
          loop (skip_active_else src next 0) defs acc
        else loop next defs acc
      else
        loop next defs (String.sub src pos (next - pos) :: acc)
  in
  loop 0 [] []

let multi_symbols =
  [ "..."; "<<="; ">>="; "=="; "!="; "<="; ">="; "&&"; "||"; "<<"; ">>"; "++"; "--"; "+="; "-="; "*="; "/="; "%="; "|="; "&="; "^="; "->" ]

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

let token_text tok =
  match tok with
  | Ident name -> "identifier " ^ name
  | Int_lit n -> "integer " ^ string_of_int n
  | Char_lit n -> "character " ^ string_of_int n
  | String_lit s -> "string length " ^ string_of_int (String.length s)
  | Sym text -> "symbol " ^ text
  | Eof -> "end of input"

let trace_enabled () =
  Array.length Sys.argv > 1 && Sys.argv.(1) = "--trace"

let trace msg =
  if trace_enabled () then prerr_endline ("ccc-host-ocaml: " ^ msg) else ()

let parse_trace_next = ref 0

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

let trace_parse_position state =
  if trace_enabled () && state.pos >= !parse_trace_next then (
    trace ("parse token " ^ string_of_int state.pos ^ " near " ^ token_text (peek state));
    parse_trace_next := state.pos + 10000)

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
  | ParserErr msg ->
      raise (Parse_error (msg ^ " at token " ^ string_of_int state.pos ^ " near " ^ token_text (peek state)))

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
  | Consumed (ParserErr msg) | Unconsumed (ParserErr msg) ->
      raise (Parse_error (msg ^ " at token 0 near " ^ token_text tokens.(0)))

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
  | TFloat
  | TDouble
  | TLongDouble
  | TVoid
  | TUnion
  | TOther of string
  | TPtr of c_type

type binop = Add | Sub | Mul | Div | Mod | Eq | Ne | Lt | Le | Gt | Ge | Land | Lor | Bor | Bxor | Band | Shl | Shr
type unop = Neg | Not | BNot | Deref | Addr

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
  | EComma of expr * expr
  | ECall of string * expr list
  | ECallExpr of expr * expr list
  | ECast of c_type * expr

type simple_stmt =
  | SExpr of expr
  | SAssign of string * expr
  | SAugAssign of string * binop * expr
  | SPost of string * int
  | SDecl of c_type * string * expr option * expr option
  | SDecls of (c_type * string * expr option * expr option) list
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

type param = { param_type : c_type; param_name : string }
type func = { name : string; params : param list; body : stmt list; ret_type : c_type }
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
  | Ident ("int" | "char" | "signed" | "unsigned" | "void" | "long" | "short" | "_Bool" | "float" | "double" | "static" | "const" | "struct" | "union") -> true
  | Ident "va_list" -> true
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

let skip_braced_tokens state =
  let state = need_sym "{" state in
  let rec loop state depth =
    match peek state with
    | Eof -> raise (Parse_error "unterminated braced type")
    | Sym "{" -> loop (advance state) (depth + 1)
    | Sym "}" ->
        if depth = 1 then advance state else loop (advance state) (depth - 1)
    | _ -> loop (advance state) depth
  in
  loop state 1

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
    | Some (name, st) ->
        let st =
          match peek st with
          | Sym "{" -> skip_braced_tokens st
          | _ -> st
        in
        (TOther ("struct " ^ name), st)
    | None -> (
        match peek st with
        | Sym "{" -> (TOther "struct", skip_braced_tokens st)
        | _ -> (TOther "struct", st))
  in
  let union_type st =
    match take_ident st with
    | Some (_, st) -> (TUnion, st)
    | None -> (
        match peek st with
        | Sym "{" -> (TUnion, skip_braced_tokens st)
        | _ -> (TUnion, st))
  in
  let named_type st =
    let name, st = need_ident st in
    (TOther name, st)
  in
  let plain_type st =
    match take_keyword_type [ ("char", TChar); ("int", TInt); ("void", TVoid); ("_Bool", TBool); ("short", TShort); ("float", TFloat); ("double", TDouble) ] st with
    | Some result -> result
    | None -> (
        match take_keyword "long" st with
        | Some st -> long_suffix st
        | None -> (
            match take_keyword "struct" st with
            | Some st -> struct_type st
            | None -> (
                match take_keyword "union" st with
                | Some st -> union_type st
                | None -> named_type st)))
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
  ptr base (qualifiers state)

let rec parse_expr state = parse_comma state

and parse_comma state =
  let lhs, state = parse_assignment state in
  match take_sym "," state with
  | Some state ->
      let rhs, state = parse_comma state in
      (EComma (lhs, rhs), state)
  | None -> (lhs, state)

and parse_assignment state =
  let lhs, state = parse_conditional state in
  let compound_op st =
    choose_option
      [
        (fun st -> match take_sym "+=" st with Some st -> Some (Add, st) | None -> None);
        (fun st -> match take_sym "-=" st with Some st -> Some (Sub, st) | None -> None);
        (fun st -> match take_sym "*=" st with Some st -> Some (Mul, st) | None -> None);
        (fun st -> match take_sym "/=" st with Some st -> Some (Div, st) | None -> None);
        (fun st -> match take_sym "%=" st with Some st -> Some (Mod, st) | None -> None);
        (fun st -> match take_sym "<<=" st with Some st -> Some (Shl, st) | None -> None);
        (fun st -> match take_sym ">>=" st with Some st -> Some (Shr, st) | None -> None);
        (fun st -> match take_sym "|=" st with Some st -> Some (Bor, st) | None -> None);
        (fun st -> match take_sym "&=" st with Some st -> Some (Band, st) | None -> None);
        (fun st -> match take_sym "^=" st with Some st -> Some (Bxor, st) | None -> None);
      ]
      st
  in
  match compound_op state with
  | Some (op, state) ->
      let rhs, state = parse_assignment state in
      let rhs = EBinary (op, lhs, rhs) in
      (match lhs with
      | EVar name -> (EAssignExpr (name, rhs), state)
      | EUnary (Deref, ptr) -> (EAssignDeref (ptr, rhs), state)
      | EIndex (base, index) -> (EAssignIndex (base, index, rhs), state)
      | EMember (base, field) -> (EAssignMember (base, field, rhs), state)
      | EPtrMember (base, field) -> (EAssignMember (EUnary (Deref, base), field, rhs), state)
      | _ -> raise (Parse_error "bad compound assignment target"))
  | None -> (
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
  | None -> (lhs, state))

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
    | Some (s, st) ->
        let rec loop acc st =
          match take_value expect_string_lit st with
          | Some (next, st) -> loop (acc ^ next) st
          | None -> Some (EString acc, st)
        in
        loop s st
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
              let expr, st = parse_assignment st in
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
        let parenthesized st =
          let expr, st = parse_expr st in
          let st = need_sym ")" st in
          Some (expr, st)
        in
        if starts_type (peek st) then
          let cast =
            try
              let ty, cast_st = parse_type st in
              match take_sym ")" cast_st with
              | Some cast_st ->
                  let rhs, cast_st = parse_unary cast_st in
                  Some (ECast (ty, rhs), cast_st)
              | None -> None
            with Parse_error _ -> None
          in
          match cast with
          | Some result -> Some result
          | None -> parenthesized st
        else parenthesized st
  in
  match
    choose_option
      [ int_lit; char_lit; string_lit; init_list; sizeof_expr; ident_expr; paren_or_cast ]
      state
  with
  | Some result -> result
  | None ->
      raise (Parse_error ("expected expression at token " ^ string_of_int state.pos ^ " near " ^ token_text (peek state)))

and parse_arg_list state =
  match take_sym ")" state with
  | Some state -> ([], state)
  | None ->
        let rec loop st acc =
        let arg, st = parse_assignment st in
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
        prefix_unary "~" BNot;
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
  let update_expr delta =
    match expr with
    | EVar name -> EUpdateExpr (name, delta, false)
    | _ -> EUpdateLvalue (expr, delta, false)
  in
  let postfix_tail expr state =
    match take_sym "[" state with
    | Some state ->
        let index, state = parse_expr state in
        let state = need_sym "]" state in
        parse_postfix (EIndex (expr, index)) state
    | None -> (
        match take_sym "(" state with
        | Some state ->
            let args, state = parse_arg_list state in
            parse_postfix (ECallExpr (expr, args)) state
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
            | None -> (
                match take_sym "++" state with
                | Some state -> (update_expr 1, state)
                | None -> (
                    match take_sym "--" state with
                    | Some state -> (update_expr (-1), state)
                    | None -> (expr, state))))))
  in
  postfix_tail expr state

and binop_of op =
  match op with
  | "||" -> Some (Lor, 1)
  | "&&" -> Some (Land, 2)
  | "|" -> Some (Bor, 3)
  | "^" -> Some (Bxor, 4)
  | "&" -> Some (Band, 5)
  | "==" -> Some (Eq, 6)
  | "!=" -> Some (Ne, 6)
  | "<" -> Some (Lt, 7)
  | "<=" -> Some (Le, 7)
  | ">" -> Some (Gt, 7)
  | ">=" -> Some (Ge, 7)
  | "<<" -> Some (Shl, 8)
  | ">>" -> Some (Shr, 8)
  | "+" -> Some (Add, 9)
  | "-" -> Some (Sub, 9)
  | "*" -> Some (Mul, 10)
  | "/" -> Some (Div, 10)
  | "%" -> Some (Mod, 10)
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
  | TInt | TUnsigned | TFloat | TOther _ -> 4
  | TLong | TLongLong | TUnsignedLong | TUnsignedLongLong | TPtr _ -> 8
  | TUnion -> 8
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
              let expr, st = parse_assignment st in
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

let parse_array_sizes state =
  let rec loop state acc =
    match parse_array_size state with
    | None, state -> (acc, state)
    | Some size, state ->
        let acc =
          match acc with
          | None -> Some size
          | Some prev -> Some (EBinary (Mul, prev, size))
        in
        loop state acc
  in
  loop state None

let parse_decl_suffix name state =
  let array_size, state =
    parse_array_sizes state
  in
  let init, state =
    match take_sym "=" state with
    | Some state ->
        let expr, state = parse_assignment state in
        (Some expr, state)
    | None -> (None, state)
  in
  (name, init, array_size, state)

let parse_decl_tail state =
  let name, state = need_ident state in
  parse_decl_suffix name state

let rec strip_ptr_type ty =
  match ty with
  | TPtr ty -> strip_ptr_type ty
  | _ -> ty

let rec add_ptr_type ty count =
  if count <= 0 then ty else add_ptr_type (TPtr ty) (count - 1)

let parse_declarator_pointer state =
  let rec qualifiers state =
    match take_keyword "const" state with
    | Some state -> qualifiers state
    | None -> state
  in
  let rec loop count state =
    match take_sym "*" state with
    | Some state -> loop (count + 1) (qualifiers state)
    | None -> (count, state)
  in
  loop 0 state

let parse_decl_after_type state =
  let ty, state = parse_type state in
  let name, init, array_size, state = parse_decl_tail state in
  let base_ty = strip_ptr_type ty in
  let first = (ty, name, init, array_size) in
  let rec rest state acc =
    match take_sym "," state with
    | Some state ->
        let ptr_count, state = parse_declarator_pointer state in
        let item_ty = add_ptr_type base_ty ptr_count in
        let name, init, array_size, state = parse_decl_tail state in
        rest state ((item_ty, name, init, array_size) :: acc)
    | None ->
        let decls = List.rev acc in
        (match decls with
        | [ (ty, name, init, array_size) ] -> (SDecl (ty, name, init, array_size), state)
        | _ -> (SDecls decls, state))
  in
  rest state [ first ]

let starts_typedef_decl_shape state =
  match peek state with
  | Ident _ -> (
      match peek (advance state) with
      | Ident _ | Sym "*" -> true
      | _ -> false)
  | _ -> false

let starts_statement_decl state =
  match peek state with
  | Ident ("struct" | "union") -> starts_type (peek state)
  | _ -> starts_typedef_decl_shape state

let parse_simple_no_semi state =
  match peek state with
  | Sym ")" | Sym ";" -> (SEmpty, state)
  | tok ->
      if starts_statement_decl state || starts_typedef_decl_shape state then parse_decl_after_type state
      else
        let expr, state = parse_expr state in
        (SExpr expr, state)

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

let skip_balanced_symbols open_sym close_sym err state =
  let state = need_sym open_sym state in
  let rec loop st depth =
    match peek st with
    | Eof -> raise (Parse_error err)
    | Sym sym ->
        if sym = open_sym then loop (advance st) (depth + 1)
        else if sym = close_sym then
          if depth = 1 then advance st else loop (advance st) (depth - 1)
        else loop (advance st) depth
    | _ -> loop (advance st) depth
  in
  loop state 1

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
  let parse_name ty st =
    match peek st, peek (advance st), peek (advance (advance st)) with
    | Sym "(", Sym "*", Ident name ->
        let st = advance (advance (advance st)) in
        let st = need_sym ")" st in
        let st =
          match peek st with
          | Sym "(" -> skip_balanced st 0
          | _ -> st
        in
        (name, TPtr ty, st)
    | _ -> (
        match take_ident st with
        | Some (name, st) -> (name, ty, st)
        | None -> ("_", ty, st))
  in
  let rec skip_square st depth =
    match peek st with
    | Eof -> raise (Parse_error "unterminated array parameter")
    | Sym "[" -> skip_square (advance st) (depth + 1)
    | Sym "]" ->
        if depth = 1 then advance st else skip_square (advance st) (depth - 1)
    | _ -> skip_square (advance st) depth
  in
  let rec skip_param_suffix st has_array =
    match peek st with
    | Sym "[" -> skip_param_suffix (skip_square st 0) true
    | _ -> (has_array, st)
  in
  let rec parse_nonempty st acc =
    match take_sym "..." st with
    | Some st ->
        let st = need_sym ")" st in
        (List.rev acc, st)
    | None ->
        let ty, st = parse_type st in
        let name, ty, st = parse_name ty st in
        let has_array, st = skip_param_suffix st false in
        let ty = if has_array then TPtr ty else ty in
        let param = { param_type = ty; param_name = name } in
        match take_sym "," st with
        | Some st -> parse_nonempty st (param :: acc)
        | None ->
            let st = need_sym ")" st in
            (List.rev (param :: acc), st)
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

let rec skip_attributes state =
  match take_keyword "__attribute__" state with
  | Some state ->
      let state = skip_balanced_symbols "(" ")" "unterminated attribute" state in
      skip_attributes state
  | None -> state

let parse_function_tail name params ret_type state =
  let state = skip_attributes state in
  match take_sym ";" state with
  | Some state -> (None, state)
  | None -> (
      match take_sym "{" state with
      | Some state ->
          let body, state = parse_block state in
          (Some { name; params; body; ret_type }, state)
      | None ->
          raise (Parse_error ("expected function body at token " ^ string_of_int state.pos ^ " near " ^ token_text (peek state))))

let parse_function state =
  let ret_type, state = parse_type state in
  let name, state = need_ident state in
  let params, state = parse_params state in
  parse_function_tail name params ret_type state

type external_decl = ExternalFunc of func option | ExternalGlobal of global_decl

let parse_function_pointer_declarator ty state =
  let state = need_sym "(" state in
  let state = need_sym "*" state in
  let name, state = need_ident state in
  let state = need_sym ")" state in
  let state =
    match peek state with
    | Sym "(" -> skip_balanced_symbols "(" ")" "unterminated function pointer declarator" state
    | _ -> state
  in
  (TPtr ty, name, state)

let parse_external_decl state =
  let ty, state = parse_type state in
  match peek state with
  | Sym "(" ->
      let ty, name, state = parse_function_pointer_declarator ty state in
      let init, state =
        match take_sym "=" state with
        | Some state ->
            let expr, state = parse_assignment state in
            (Some expr, state)
        | None -> (None, state)
      in
      let state = need_sym ";" state in
      (ExternalGlobal { global_type = ty; global_name = name; global_init = init; global_array_size = None }, state)
  | _ ->
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

let skip_braced_type_body state =
  let state = need_sym "{" state in
  let rec loop st depth =
    match peek st with
    | Eof -> raise (Parse_error "unterminated braced type body")
    | Sym "{" -> loop (advance st) (depth + 1)
    | Sym "}" ->
        if depth = 1 then advance st else loop (advance st) (depth - 1)
    | _ -> loop (advance st) depth
  in
  loop state 1

let parse_field_name state =
  match peek state, peek (advance state), peek (advance (advance state)) with
  | Sym "(", Sym "*", Ident name ->
      let state = advance (advance (advance state)) in
      let state = need_sym ")" state in
      let state =
        match peek state with
        | Sym "(" -> skip_balanced_symbols "(" ")" "unterminated function pointer field" state
        | _ -> state
      in
        (name, state)
  | _ -> need_ident state

let starts_aggregate_body state =
  match peek state, peek (advance state), peek (advance (advance state)) with
  | Ident ("struct" | "union"), Sym "{", _ -> true
  | Ident ("struct" | "union"), Ident _, Sym "{" -> true
  | _ -> false

let parse_aggregate_body_field state =
  let keyword =
    match peek state with
    | Ident name -> name
    | _ -> raise (Parse_error "expected aggregate field")
  in
  let state = advance state in
  let tag, state =
    match take_ident state with
    | Some (name, state) -> (name, state)
    | None -> ("", state)
  in
  let base_ty =
    if keyword = "struct" then
      TOther (if tag = "" then "struct" else "struct " ^ tag)
    else TUnion
  in
  let state = skip_braced_type_body state in
  match take_sym ";" state with
  | Some state -> ([ ("__anonymous_" ^ keyword, base_ty, None) ], state)
  | None ->
      let rec declarators state acc =
        let ptr_count, state = parse_declarator_pointer state in
        let ty = add_ptr_type base_ty ptr_count in
        let field, state = parse_field_name state in
        let array_size, state = parse_array_size state in
        match take_sym "," state with
        | Some state -> declarators state ((field, ty, array_size) :: acc)
        | None ->
            let state = need_sym ";" state in
            (List.rev ((field, ty, array_size) :: acc), state)
      in
      declarators state []

let parse_struct_field state =
  match peek state with
  | Ident ("struct" | "union") ->
      if starts_aggregate_body state then parse_aggregate_body_field state
      else
        let ty, state = parse_type state in
        let rec skip_declarator_pointer state =
          match take_sym "*" state with
          | Some state ->
              let rec qualifiers state =
                match take_keyword "const" state with
                | Some state -> qualifiers state
                | None -> state
              in
              skip_declarator_pointer (qualifiers state)
          | None -> state
        in
        let rec declarators state acc =
          let state = skip_declarator_pointer state in
          let field, state = parse_field_name state in
          let array_size, state = parse_array_size state in
          let state =
            match take_sym ":" state with
            | Some state ->
                let _width, state = parse_assignment state in
                state
            | None -> state
          in
          match take_sym "," state with
          | Some state -> declarators state ((field, ty, array_size) :: acc)
          | None ->
              let state = need_sym ";" state in
              (List.rev ((field, ty, array_size) :: acc), state)
        in
        declarators state []
  | _ ->
      let ty, state = parse_type state in
      let rec skip_declarator_pointer state =
        match take_sym "*" state with
        | Some state ->
            let rec qualifiers state =
              match take_keyword "const" state with
              | Some state -> qualifiers state
              | None -> state
            in
            skip_declarator_pointer (qualifiers state)
        | None -> state
      in
      let rec declarators state acc =
        let state = skip_declarator_pointer state in
        let field, state = parse_field_name state in
        let array_size, state = parse_array_size state in
        let state =
          match take_sym ":" state with
          | Some state ->
              let _width, state = parse_assignment state in
              state
          | None -> state
        in
        match take_sym "," state with
        | Some state -> declarators state ((field, ty, array_size) :: acc)
        | None ->
            let state = need_sym ";" state in
            (List.rev ((field, ty, array_size) :: acc), state)
      in
      declarators state []

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
        let fields, st = parse_struct_field st in
        loop st (List.rev_append fields acc)
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
        let parsed, st = parse_struct_field st in
        fields st (List.rev_append parsed acc)
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
  | EBinary (Bor, a, b) -> bitwise_or (eval_enum_expr env a) (eval_enum_expr env b)
  | EBinary (Bxor, a, b) -> bitwise_xor (eval_enum_expr env a) (eval_enum_expr env b)
  | EBinary (Band, a, b) -> bitwise_and (eval_enum_expr env a) (eval_enum_expr env b)
  | EBinary (Shl, a, b) -> shift_left_u32 (eval_enum_expr env a) (eval_enum_expr env b)
  | EBinary (Shr, a, b) -> shift_right_u32 (eval_enum_expr env a) (eval_enum_expr env b)
  | EUnary (Neg, e) -> - eval_enum_expr env e
  | EUnary (BNot, e) -> bitwise_not (eval_enum_expr env e)
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
    trace_parse_position state;
    let parse_external_or_skip state constants structs globals funcs =
      let parsed =
        try Some (parse_external_decl state) with
        | Parse_error msg ->
          if not (external_is_named_function state) then
            None
          else raise (Parse_error msg)
      in
      match parsed with
      | Some (ExternalFunc (Some fn), state) -> loop state constants structs globals (fn :: funcs)
      | Some (ExternalFunc None, state) -> loop state constants structs globals funcs
      | Some (ExternalGlobal global, state) -> loop state constants structs (global :: globals) funcs
      | None -> loop { state with pos = skip_decl state.tokens state.pos 0 } constants structs globals funcs
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
  | TInt | TUnsigned | TFloat -> 4
  | TLong | TLongLong | TUnsignedLong | TUnsignedLongLong | TPtr _ -> 8
  | TDouble -> 8
  | TLongDouble -> 16
  | TVoid -> 1
  | TOther _ -> 4
  | TUnion -> 8

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

let alloc_counter = ref 0

let positive_size size =
  if size <= 0 then 1 else size

let fresh_alloc size =
  alloc_counter := !alloc_counter + 1;
  let values = Array.make (positive_size size) (VInt 0) in
  let binding =
    {
      bind_name = "__alloc" ^ string_of_int !alloc_counter;
      bind_type = TUnsignedChar;
      bind_value = ref (VInt 0);
      bind_string = None;
      bind_array = Some values;
      bind_bytes = Some values;
      bind_fields = Some (ref []);
    }
  in
  VArrayPtr (binding, 0)

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

let byte_of_pointer ptr offset =
  int_of_value (read_pointer (add_to_value ptr offset))

let write_pointer_byte ptr offset value =
  let _ = write_pointer (add_to_value ptr offset) (VInt value) in
  ()

let write_repeated_bytes ptr value count =
  let rec loop i =
    if i >= count then ()
    else (
      write_pointer_byte ptr i value;
      loop (i + 1))
  in
  loop 0

let copy_bytes dst src count =
  let rec loop i =
    if i >= count then ()
    else (
      write_pointer_byte dst i (byte_of_pointer src i);
      loop (i + 1))
  in
  loop 0

let c_string_length ptr =
  let rec loop i =
    if byte_of_pointer ptr i = 0 then i else loop (i + 1)
  in
  loop 0

let copy_c_string dst src =
  let rec loop i =
    let ch = byte_of_pointer src i in
    write_pointer_byte dst i ch;
    if ch = 0 then () else loop (i + 1)
  in
  loop 0

let compare_bytes a b count =
  let rec loop i =
    if i >= count then 0
    else
      let x = byte_of_pointer a i in
      let y = byte_of_pointer b i in
      if x = y then loop (i + 1) else x - y
  in
  loop 0

let compare_c_string a b =
  let rec loop i =
    let x = byte_of_pointer a i in
    let y = byte_of_pointer b i in
    if x = y then if x = 0 then 0 else loop (i + 1) else x - y
  in
  loop 0

let is_builtin_name name =
  match name with
  | "malloc" | "calloc" | "realloc" | "free" | "exit"
  | "memset" | "memcpy" | "memmove" | "memcmp"
  | "strlen" | "strcpy" | "strcmp"
  | "fprintf" | "printf" | "sprintf" | "snprintf" ->
      true
  | _ -> false

let eval_builtin_call name values =
  match (name, values) with
  | ("malloc" | "calloc"), [ size ] ->
      Some (fresh_alloc (int_of_value size))
  | "calloc", [ count; size ] ->
      Some (fresh_alloc (int_of_value count * int_of_value size))
  | "realloc", [ ptr; size ] ->
      let size = int_of_value size in
      if size = 0 then Some (VInt 0)
      else (
        match ptr with
        | VInt 0 -> Some (fresh_alloc size)
        | _ -> Some ptr)
  | ("free" | "exit"), _ -> Some (VInt 0)
  | "memset", [ ptr; value; count ] ->
      write_repeated_bytes ptr (int_of_value value) (int_of_value count);
      Some ptr
  | ("memcpy" | "memmove"), [ dst; src; count ] ->
      copy_bytes dst src (int_of_value count);
      Some dst
  | "memcmp", [ a; b; count ] ->
      Some (VInt (compare_bytes a b (int_of_value count)))
  | "strlen", [ ptr ] -> Some (VInt (c_string_length ptr))
  | "strcpy", [ dst; src ] ->
      copy_c_string dst src;
      Some dst
  | "strcmp", [ a; b ] -> Some (VInt (compare_c_string a b))
  | ("fprintf" | "printf" | "sprintf" | "snprintf"), _ -> Some (VInt 0)
  | _ -> None

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
  | VArrayPtr (binding, 0) -> Some binding
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

let scalar_field_pointer binding field =
  let cell = field_cell (binding_fields binding) field in
  VPtr
    {
      bind_name = binding.bind_name ^ "." ^ field;
      bind_type = TInt;
      bind_value = cell;
      bind_string = None;
      bind_array = None;
      bind_bytes = None;
      bind_fields = Some (ref []);
    }

let field_pointer structs binding owner_ty field =
  match struct_field_layout structs owner_ty field with
  | Some layout ->
      (match binding.bind_array with
      | Some _ ->
          if layout.field_is_array then VFieldPtr (binding, layout.field_offset)
          else scalar_field_pointer binding field
      | None -> VFieldPtr (binding, layout.field_offset))
  | None -> scalar_field_pointer binding field

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
            match struct_binding_from_pointer (eval_value funcs structs globals env ptr) with
            | Some target -> target
            | None -> fail "not a struct pointer")
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
            match struct_binding_from_pointer (eval_value funcs structs globals env ptr) with
            | Some target -> target
            | None -> fail "not a struct pointer")
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
              match struct_binding_from_pointer (eval_value funcs structs globals env base) with
              | Some target -> target
              | None -> fail "not a struct pointer"
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
  | EUnary (BNot, e) -> VInt (bitwise_not (eval_expr funcs structs globals env e))
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
      field_pointer structs binding binding.bind_type field
  | EUnary (Addr, EPtrMember (EVar name, field)) ->
      let pointer_binding = find_binding name env in
      let target =
        match struct_binding_from_pointer (eval_value funcs structs globals env (EVar name)) with
        | Some target -> target
        | None -> fail "not a struct pointer"
      in
      let owner_ty =
        match pointer_binding.bind_type with
        | TPtr ty -> ty
        | _ -> target.bind_type
      in
      field_pointer structs target owner_ty field
  | EUnary (Addr, EPtrMember (base, field)) ->
      let target =
        match struct_binding_from_pointer (eval_value funcs structs globals env base) with
        | Some target -> target
        | None -> fail "not a struct pointer"
      in
      field_pointer structs target target.bind_type field
  | EUnary (Addr, _) -> fail "unsupported address expression"
  | ECast (ty, e) ->
      coerce_value ty (eval_value funcs structs globals env e)
  | EComma (lhs, rhs) ->
      let _ = eval_value funcs structs globals env lhs in
      eval_value funcs structs globals env rhs
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
      | Bor -> bitwise_or x y
      | Bxor -> bitwise_xor x y
      | Band -> bitwise_and x y
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
      (match eval_builtin_call target values with
      | Some value -> value
      | None -> eval_func funcs structs globals target values)
  | ECallExpr (callee, args) ->
      let values = List.map (call_arg funcs structs globals env) args in
      let target =
        match eval_value funcs structs globals env callee with
        | VFunc name -> name
        | _ -> fail "called expression is not a function"
      in
      (match eval_builtin_call target values with
      | Some value -> value
      | None -> eval_func funcs structs globals target values)

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
  if not (same_length fn.params args) then fail ("wrong argument count: " ^ name) else
  let env =
    List.map2
      (fun param value ->
        {
          bind_name = param.param_name;
          bind_type = param.param_type;
          bind_value = ref (coerce_value param.param_type value);
          bind_string = None;
          bind_array = None;
          bind_bytes = None;
          bind_fields = None;
        })
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
      if list_find_opt (fun fn -> fn.name = name) funcs = None && find_binding_opt name env = None && not (is_builtin_name name) then env
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
  | SDecls decls ->
      List.fold_left
        (fun env (ty, name, init, array_size) -> exec_simple funcs structs globals env (SDecl (ty, name, init, array_size)))
        env decls
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
      let value =
        match op with
        | Add -> old + delta
        | Sub -> old - delta
        | Mul -> old * delta
        | Div -> old / delta
        | Mod -> old mod delta
        | Shl -> shift_left_u32 old delta
        | Shr -> shift_right_u32 old delta
        | Bor -> bitwise_or old delta
        | Band -> bitwise_and old delta
        | Bxor -> bitwise_xor old delta
        | _ -> fail "bad compound assignment"
      in
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

let rec same_c_type a b =
  match (a, b) with
  | TInt, TInt -> true
  | TChar, TChar -> true
  | TSignedChar, TSignedChar -> true
  | TUnsignedChar, TUnsignedChar -> true
  | TShort, TShort -> true
  | TUnsignedShort, TUnsignedShort -> true
  | TLong, TLong -> true
  | TLongLong, TLongLong -> true
  | TUnsigned, TUnsigned -> true
  | TUnsignedLong, TUnsignedLong -> true
  | TUnsignedLongLong, TUnsignedLongLong -> true
  | TBool, TBool -> true
  | TFloat, TFloat -> true
  | TDouble, TDouble -> true
  | TLongDouble, TLongDouble -> true
  | TVoid, TVoid -> true
  | TUnion, TUnion -> true
  | TOther a, TOther b -> a = b
  | TPtr a, TPtr b -> same_c_type a b
  | _ -> false

let is_main_argv_type ty =
  same_c_type ty (TPtr (TPtr TChar))

let main_entry_args fn =
  match fn.params with
  | [] -> []
  | [ argc ] ->
      if same_c_type argc.param_type TInt then [ VInt 0 ]
      else fail "unsupported main parameters"
  | [ argc; argv ] ->
      if same_c_type argc.param_type TInt && is_main_argv_type argv.param_type then [ VInt 0; VInt 0 ]
      else fail "unsupported main parameters"
  | _ -> fail "unsupported main parameters"

let compile src =
  trace "preprocess";
  let src, constants = preprocess_source src in
  trace "lex";
  let tokens = lex src in
  trace ("tokens=" ^ string_of_int (Array.length tokens));
  trace "parse";
  let program = parse_program tokens constants in
  trace
    ("program funcs=" ^ string_of_int (List.length program.funcs)
     ^ " globals=" ^ string_of_int (List.length program.globals)
     ^ " structs=" ^ string_of_int (List.length program.structs));
  if not (List.exists (fun fn -> fn.name = "main") program.funcs) then m1_of_exit 0
  else
  let constants =
    List.map
      (fun (name, value) ->
        { bind_name = name; bind_type = TInt; bind_value = ref (VInt value); bind_string = None; bind_array = None; bind_bytes = None; bind_fields = None })
      program.constants
  in
  let globals =
    trace "globals";
    List.fold_left
      (fun env global ->
        exec_simple program.funcs program.structs env env (SDecl (global.global_type, global.global_name, global.global_init, global.global_array_size)))
      constants program.globals
  in
  let main =
    match list_find_opt (fun fn -> fn.name = "main") program.funcs with
    | Some fn -> fn
    | None -> fail "missing main"
  in
  trace "eval main";
  m1_of_exit (int_of_value (eval_func program.funcs program.structs globals "main" (main_entry_args main)))

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
