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
exception Fatal_exit of int
exception Longjmp of int

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

let rec has_at_least xs ys =
  match (xs, ys) with
  | [], _ -> true
  | _ :: _, [] -> false
  | _ :: xs, _ :: ys -> has_at_least xs ys

let rec strings_of_chars chars =
  match chars with
  | [] -> []
  | ch :: rest -> String.make 1 ch :: strings_of_chars rest

let string_of_rev_chars chars =
  String.concat "" (strings_of_chars (List.rev chars))

let host_stderr_line msg =
  prerr_endline msg (* HOST-ML-BOUNDARY *)

let host_stdout text =
  print_string text (* HOST-ML-BOUNDARY *)

let host_exit code =
  exit code (* HOST-ML-BOUNDARY *)

let host_getenv name =
  try Some (Sys.getenv name) with Not_found -> None (* HOST-ML-BOUNDARY *)

let host_arg_count () =
  Array.length Sys.argv (* HOST-ML-BOUNDARY *)

let host_arg_at i =
  Sys.argv.(i) (* HOST-ML-BOUNDARY *)

let host_read_all chan =
  let rec loop acc =
    let next = try Some (input_char chan) with End_of_file -> None (* HOST-ML-BOUNDARY *) in
    match next with
    | Some ch -> loop (ch :: acc)
    | None -> string_of_rev_chars acc
  in
  loop []

let host_read_stdin () =
  host_read_all stdin (* HOST-ML-BOUNDARY *)

let host_read_text_file path =
  let chan = open_in_bin path in (* HOST-ML-BOUNDARY *)
  try
    let text = host_read_all chan in
    close_in chan; (* HOST-ML-BOUNDARY *)
    text
  with exn ->
    close_in_noerr chan; (* HOST-ML-BOUNDARY *)
    raise exn

let host_write_file path text =
  let chan = open_out_bin path in (* HOST-ML-BOUNDARY *)
  try
    output_string chan text; (* HOST-ML-BOUNDARY *)
    close_out chan (* HOST-ML-BOUNDARY *)
  with exn ->
    close_out_noerr chan; (* HOST-ML-BOUNDARY *)
    raise exn

let unsigned_mod value modulus =
  let rem = value mod modulus in
  if rem < 0 then rem + modulus else rem

let rec pow2 count =
  if count <= 0 then 1 else 2 * pow2 (count - 1)

let rec shift_left_u32 value count =
  if count <= 0 then unsigned_mod value 4294967296
  else shift_left_u32 (unsigned_mod (value * 2) 4294967296) (count - 1)

let rec shift_right_u32 value count =
  if count <= 0 then unsigned_mod value 4294967296
  else if count >= 32 then 0
  else shift_right_u32 ((unsigned_mod value 4294967296) / 2) (count - 1)

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

let saturating_add_digit base acc digit =
  if acc > (max_int - digit) / base then max_int else acc * base + digit

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
  | 'v' -> (11, pos + 1)
  | 'f' -> (12, pos + 1)
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
        loop (p + 1) (saturating_add_digit 16 acc (hex_value src.[p]))
      else (Int_lit acc, suffix p)
    in
    loop (pos + 2) 0
  else
    let rec loop p acc =
      if p < len && is_digit src.[p] then
        loop (p + 1) (saturating_add_digit 10 acc (Char.code src.[p] - Char.code '0'))
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

let trace_requested = ref false

let trace_enabled () =
  !trace_requested

let trace msg =
  if trace_enabled () then host_stderr_line ("ccc-host-ocaml: " ^ msg) else ()

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
  | Labeled of string * stmt
  | Break
  | ContinueStmt
  | Block of stmt list
and switch_case = SwitchCase of expr option * stmt list

type param = { param_type : c_type; param_name : string }
type func = { name : string; params : param list; variadic : bool; body : stmt list; ret_type : c_type }
type global_decl = { global_type : c_type; global_name : string; global_init : expr option; global_array_size : expr option }
type field_layout = { field_name : string; field_type : c_type; field_size : int; field_offset : int; field_is_array : bool }
type struct_layout = { struct_name : string; struct_fields : field_layout list; struct_size : int }
type program = { constants : (string * int) list; structs : struct_layout list; globals : global_decl list; funcs : func list }

let union_begin_field = "__anonymous_union_begin"
let union_end_field = "__anonymous_union_end"

let is_layout_marker name =
  name = union_begin_field || name = union_end_field

let binop_name op =
  match op with
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | Mod -> "%"
  | Eq -> "=="
  | Ne -> "!="
  | Lt -> "<"
  | Le -> "<="
  | Gt -> ">"
  | Ge -> ">="
  | Bor -> "|"
  | Bxor -> "^"
  | Band -> "&"
  | Shl -> "<<"
  | Shr -> ">>"
  | Land -> "&&"
  | Lor -> "||"

let rec expr_summary expr =
  match expr with
  | EInt n -> string_of_int n
  | EVar name -> name
  | EString _ -> "string"
  | EInitList _ -> "init-list"
  | EIndex (base, _) -> expr_summary base ^ "[]"
  | EMember (base, field) -> expr_summary base ^ "." ^ field
  | EPtrMember (base, field) -> expr_summary base ^ "->" ^ field
  | EAssignExpr (name, _) -> name ^ " = ..."
  | EAssignDeref _ -> "*... = ..."
  | EAssignIndex (base, _, _) -> expr_summary base ^ "[] = ..."
  | EAssignMember (base, field, _) -> expr_summary base ^ "." ^ field ^ " = ..."
  | EUpdateExpr (name, _, _) -> name ^ " update"
  | EUpdateLvalue (target, _, _) -> expr_summary target ^ " update"
  | EUnary (Deref, e) -> "*" ^ expr_summary e
  | EUnary (Addr, e) -> "&" ^ expr_summary e
  | EUnary _ -> "unary"
  | EBinary (op, a, b) -> "(" ^ expr_summary a ^ " " ^ binop_name op ^ " " ^ expr_summary b ^ ")"
  | ECond _ -> "?:"
  | ECall (name, _) -> name ^ "(...)"
  | ECallExpr (callee, _) -> expr_summary callee ^ "(...)"
  | ECast (_, e) -> "(" ^ expr_summary e ^ " cast)"
  | ESizeof _ -> "sizeof"
  | ESizeofExpr e -> "sizeof " ^ expr_summary e
  | EComma (_, rhs) -> "..., " ^ expr_summary rhs

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

let canonical_named_type name =
  match name with
  | "int8_t" -> TSignedChar
  | "uint8_t" -> TUnsignedChar
  | "int16_t" -> TShort
  | "uint16_t" -> TUnsignedShort
  | "int32_t" -> TInt
  | "uint32_t" -> TUnsigned
  | "int64_t" -> TLongLong
  | "uint64_t" -> TUnsignedLongLong
  | "size_t" | "__SIZE_TYPE__" | "uintptr_t" | "addr_t" -> TUnsignedLong
  | "ssize_t" | "intptr_t" -> TLong
  | _ -> TOther name

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
    (canonical_named_type name, st)
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
  let layout_one offset field_name ty array_size =
    let offset = align_up offset (layout_align ty) in
    let field_size = layout_field_size ty array_size in
    (offset + field_size, { field_name; field_type = ty; field_size; field_offset = offset; field_is_array = option_is_some array_size })
  in
  let rec take_union fields acc =
    match fields with
    | [] -> (List.rev acc, [])
    | (field_name, ty, array_size) :: rest ->
        if field_name = union_end_field then (List.rev acc, rest)
        else take_union rest ((field_name, ty, array_size) :: acc)
  in
  let rec loop offset acc fields =
    match fields with
    | [] -> { struct_name = name; struct_fields = List.rev acc; struct_size = offset }
    | (field_name, ty, array_size) :: rest ->
        if field_name = union_begin_field then
          let union_fields, rest = take_union rest [] in
          let rec union_align fields align =
            match fields with
            | [] -> align
            | (_, ty, _) :: fields -> union_align fields (max align (layout_align ty))
          in
          let offset = align_up offset (union_align union_fields 1) in
          let rec union_layout fields max_size acc =
            match fields with
            | [] -> (max_size, acc)
            | (field_name, ty, array_size) :: fields ->
                let field_size = layout_field_size ty array_size in
                let layout = { field_name; field_type = ty; field_size; field_offset = offset; field_is_array = option_is_some array_size } in
                union_layout fields (max max_size field_size) (layout :: acc)
          in
          let size, union_acc = union_layout union_fields 0 acc in
          loop (offset + size) union_acc rest
        else if is_layout_marker field_name then loop offset acc rest
        else
          let next_offset, layout = layout_one offset field_name ty array_size in
          loop next_offset (layout :: acc) rest
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

let parse_typedef_enum_decl state =
  let state = need_keyword "typedef" state in
  let state = need_keyword "enum" state in
  let constants, state = parse_enum_after_keyword state in
  let state =
    match take_ident state with
    | Some (_, state) -> state
    | None -> state
  in
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
        let yes, st =
          match take_ident st with
          | Some (name, st1) -> (
              match take_sym ":" st1 with
              | Some st2 ->
                  let stmt, st2 = parse_stmt st2 in
                  (Labeled (name, stmt), st2)
              | None -> parse_stmt st)
          | None -> parse_stmt st
        in
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
        ((List.rev acc, true), st)
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
            ((List.rev (param :: acc), false), st)
  in
  match take_sym ")" state with
  | Some state -> (([], false), state)
  | None -> (
      match take_keyword "void" state with
      | Some state_after_void -> (
          match take_sym ")" state_after_void with
          | Some state -> (([], false), state)
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
          let params, variadic = params in
          (Some { name; params; variadic; body; ret_type }, state)
      | None ->
          raise (Parse_error ("expected function body at token " ^ string_of_int state.pos ^ " near " ^ token_text (peek state))))

let parse_function state =
  let ret_type, state = parse_type state in
  let name, state = need_ident state in
  let params, state = parse_params state in
  parse_function_tail name params ret_type state

type external_decl = ExternalFunc of func option | ExternalGlobals of global_decl list

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
      (ExternalGlobals [ { global_type = ty; global_name = name; global_init = init; global_array_size = None } ], state)
  | _ ->
      let name, state = need_ident state in
      match take_sym "(" state with
      | Some _ ->
          let params, state = parse_params state in
          let func, state = parse_function_tail name params ty state in
          (ExternalFunc func, state)
      | None ->
          let name, init, array_size, state = parse_decl_suffix name state in
          let base_ty = strip_ptr_type ty in
          let first = { global_type = ty; global_name = name; global_init = init; global_array_size = array_size } in
          let rec rest state acc =
            match take_sym "," state with
            | Some state ->
                let ptr_count, state = parse_declarator_pointer state in
                let item_ty = add_ptr_type base_ty ptr_count in
                let name, init, array_size, state = parse_decl_tail state in
                rest state ({ global_type = item_ty; global_name = name; global_init = init; global_array_size = array_size } :: acc)
            | None ->
                let state = need_sym ";" state in
                (ExternalGlobals (List.rev acc), state)
          in
          rest state [ first ]

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

let rec parse_aggregate_body_field state =
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
  let body_fields, state =
    let state = need_sym "{" state in
    let rec loop state acc =
      match take_sym "}" state with
      | Some state -> (List.rev acc, state)
      | None ->
          let fields, state = parse_struct_field state in
          loop state (List.rev_append fields acc)
    in
    loop state []
  in
  match take_sym ";" state with
  | Some state ->
      if keyword = "union" then ((union_begin_field, TUnion, None) :: body_fields @ [ (union_end_field, TUnion, None) ], state)
      else (body_fields, state)
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

and parse_struct_field state =
  match peek state with
  | Ident ("struct" | "union") ->
      if starts_aggregate_body state then parse_aggregate_body_field state
      else
        let ty, state = parse_type state in
        let rec declarator_pointer count state =
          match take_sym "*" state with
          | Some state ->
              let rec qualifiers state =
                match take_keyword "const" state with
                | Some state -> qualifiers state
                | None -> state
              in
              declarator_pointer (count + 1) (qualifiers state)
          | None -> (count, state)
        in
        let rec declarators state acc =
          let ptr_count, state = declarator_pointer 0 state in
          let ty = add_ptr_type ty ptr_count in
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
      let rec declarator_pointer count state =
        match take_sym "*" state with
        | Some state ->
            let rec qualifiers state =
              match take_keyword "const" state with
              | Some state -> qualifiers state
              | None -> state
            in
            declarator_pointer (count + 1) (qualifiers state)
        | None -> (count, state)
      in
      let rec declarators state acc =
        let ptr_count, state = declarator_pointer 0 state in
        let ty = add_ptr_type ty ptr_count in
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

let is_typedef_enum_definition_start state =
  match peek state with
  | Ident "typedef" -> (
      match peek (advance state) with
      | Ident "enum" -> true
      | _ -> false)
  | _ -> false

let is_enum_definition_start state =
  match peek state with
  | Ident "enum" -> (
      match peek (advance state) with
      | Sym "{" -> true
      | Ident _ -> peek (advance (advance state)) = Sym "{"
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
      | Some (ExternalGlobals parsed_globals, state) -> loop state constants structs (List.rev_append parsed_globals globals) funcs
      | None -> loop { state with pos = skip_decl state.tokens state.pos 0 } constants structs globals funcs
    in
    match peek state with
    | Eof -> { constants; structs = List.rev structs; globals = List.rev globals; funcs = List.rev funcs }
    | Ident "enum" ->
        if is_enum_definition_start state then
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
        else if is_typedef_enum_definition_start state then
          let enum_constants, state = parse_typedef_enum_decl state in
          let constants = add_enum_constants constants enum_constants in
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
  bind_layout : field_layout list option ref;
}

type env = binding list

let value_summary value =
  match value with
  | VInt n -> "int " ^ string_of_int n
  | VPtr binding -> "ptr " ^ binding.bind_name
  | VArrayPtr (binding, offset) -> "arrayptr " ^ binding.bind_name ^ "+" ^ string_of_int offset
  | VFieldPtr (binding, offset) -> "fieldptr " ^ binding.bind_name ^ "+" ^ string_of_int offset
  | VStringPtr (_, offset) -> "stringptr +" ^ string_of_int offset
  | VFunc name -> "func " ^ name

let int_of_value value =
  match value with
  | VInt value -> value
  | VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _ -> fail ("pointer used as integer: " ^ value_summary value)

let is_pointer_value value =
  match value with
  | VInt _ -> false
  | VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _ -> true

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
  { bind_name = name; bind_type = ty; bind_value = ref (coerce_value ty value); bind_string = text; bind_array = array; bind_bytes = bytes; bind_fields = fields; bind_layout = ref None }
  :: env

let assoc_decl_value ty name value env =
  assoc_decl_full None None None ty name value env

type control = Continue of env | Returned of value | Jumped of string * env | Broke of env | Continued of env

let alloc_counter = ref 0

let positive_size size =
  if size <= 0 then 1 else size

let fresh_alloc size =
  alloc_counter := !alloc_counter + 1;
  let values = Array.make (positive_size size + 4096) (VInt 0) in
  let binding =
    {
      bind_name = "__alloc" ^ string_of_int !alloc_counter;
      bind_type = TUnsignedChar;
      bind_value = ref (VInt 0);
      bind_string = None;
      bind_array = Some values;
      bind_bytes = Some values;
      bind_fields = Some (ref []);
      bind_layout = ref None;
    }
  in
  VArrayPtr (binding, 0)

let string_byte text pos =
  if pos < 0 || pos >= String.length text then 0 else Char.code text.[pos]

let fill_string_array values text =
  let rec loop i =
    if i >= Array.length values then ()
    else (
      let value = if i < String.length text then Char.code text.[i] else 0 in
      values.(i) <- VInt value;
      loop (i + 1))
  in
  loop 0

let field_cell fields name =
  match list_find_opt (fun (field, _) -> field = name) !(fields) with
  | Some (_, cell) -> cell
  | None ->
      let alias =
        if name = "i" then Some "tab[0]"
        else if has_suffix "_section" name then
          Some (String.sub name 0 (String.length name - String.length "_section"))
        else Some (name ^ "_section")
      in
      (match alias with
      | Some alias -> (
          match list_find_opt (fun (field, _) -> field = alias) !(fields) with
          | Some (_, cell) ->
              fields := !(fields) @ [ (name, cell) ];
              cell
          | None ->
              let cell = ref (VInt 0) in
              fields := !(fields) @ [ (name, cell) ];
              cell)
      | None ->
          let cell = ref (VInt 0) in
          fields := !(fields) @ [ (name, cell) ];
          cell)

let field_index_cell fields field index =
  if field = "tab" && index = 0 then field_cell fields "i"
  else field_cell fields (field ^ "[" ^ string_of_int index ^ "]")

let binding_fields binding =
  match binding.bind_fields with
  | Some fields ->
      (match !(binding.bind_layout) with
      | Some layouts ->
          let rec fields_at_offset offset layouts acc =
            match layouts with
            | [] -> acc
            | layout :: rest ->
                if layout.field_offset = offset then fields_at_offset offset rest (layout.field_name :: acc)
                else fields_at_offset offset rest acc
          in
          let rec find_existing names =
            match names with
            | [] -> None
            | name :: rest -> (
                match list_find_opt (fun (field, _) -> field = name) !(fields) with
                | Some (_, cell) -> Some cell
                | None -> find_existing rest)
          in
          let rec add_missing names cell =
            match names with
            | [] -> ()
            | name :: rest ->
                (match list_find_opt (fun (field, _) -> field = name) !(fields) with
                | Some _ -> ()
                | None -> fields := !(fields) @ [ (name, cell) ]);
                add_missing rest cell
          in
          let rec loop layouts =
            match layouts with
            | [] -> ()
            | layout :: rest ->
                let names = fields_at_offset layout.field_offset layouts [] in
                let cell = match find_existing names with Some cell -> cell | None -> ref (VInt 0) in
                add_missing names cell;
                loop rest
          in
          loop layouts
      | None -> ());
      fields
  | None -> fail ("not a struct value: " ^ binding.bind_name)

let field_array_prefix field = "__field_array:" ^ field ^ ":"

let field_array_name field target =
  field_array_prefix field ^ target.bind_name

let field_array_field binding =
  if has_prefix (field_array_prefix "tab") binding.bind_name then Some "tab" else None

let field_array_pointer target field =
  let values = Array.make 16 (VInt 0) in
  VArrayPtr
    ({
      bind_name = field_array_name field target;
      bind_type = TInt;
      bind_value = ref (VInt 0);
      bind_string = None;
      bind_array = Some values;
      bind_bytes = None;
      bind_fields = Some (binding_fields target);
      bind_layout = ref !(target.bind_layout);
    },
    0)

let rec read_binding_index binding index =
  match binding.bind_array, binding.bind_string, !(binding.bind_value) with
  | Some values, _, _ ->
      if index < 0 || index >= Array.length values then VInt 0
      else (
        match field_array_field binding with
        | Some field -> !(field_index_cell (binding_fields binding) field index)
        | None -> values.(index))
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
      if index < 0 || index >= Array.length values then
        fail
          ("array index out of bounds: " ^ binding.bind_name ^ "["
           ^ string_of_int index ^ "] len=" ^ string_of_int (Array.length values));
      let value = coerce_value binding.bind_type value in
      (match field_array_field binding with
      | Some field ->
          let cell = field_index_cell (binding_fields binding) field index in
          cell := value
      | None -> ());
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
  | VInt _ | VFunc _ -> fail ("not a pointer: " ^ value_summary ptr)

let write_pointer ptr value =
  match ptr with
  | VPtr target ->
      target.bind_value := coerce_value target.bind_type value;
      value
  | VArrayPtr (target, offset) -> write_binding_index target offset value
  | VFieldPtr (target, offset) -> write_binding_byte target offset value
  | VStringPtr _ -> fail "cannot write through string literal pointer"
  | VInt _ | VFunc _ -> fail ("not a pointer: " ^ value_summary ptr)

let is_raw_byte_binding binding =
  match binding.bind_array, binding.bind_type with
  | Some _, TUnsignedChar -> true
  | _ -> false

let raw_byte_at binding index =
  match binding.bind_array with
  | Some values ->
      if index < 0 || index >= Array.length values then 0
      else unsigned_mod (int_of_value values.(index)) 256
  | None -> 0

let write_raw_byte binding index value =
  match binding.bind_array with
  | Some values ->
      if index < 0 || index >= Array.length values then fail ("byte index out of bounds: " ^ binding.bind_name)
      else values.(index) <- VInt (unsigned_mod value 256)
  | None -> fail ("not a raw byte array: " ^ binding.bind_name)

let read_raw_int_unsigned binding offset size =
  let rec loop i shift acc =
    if i >= size then acc
    else loop (i + 1) (shift + 8) (acc + shift_left_u32 (raw_byte_at binding (offset + i)) shift)
  in
  loop 0 0 0

let sign_extend_raw_int size value =
  if size >= 8 then value
  else
    let bits = size * 8 in
    let sign_bit = pow2 (bits - 1) in
    let modulus = pow2 bits in
    if value >= sign_bit then value - modulus else value

let raw_int_is_unsigned ty =
  match ty with
  | TUnsignedChar | TUnsignedShort | TUnsigned | TUnsignedLong | TUnsignedLongLong | TPtr _ -> true
  | _ -> false

let read_raw_int_as ty binding offset size =
  let value = read_raw_int_unsigned binding offset size in
  if raw_int_is_unsigned ty then VInt value else VInt (sign_extend_raw_int size value)

let write_raw_int binding offset size value =
  let n = int_of_value value in
  let rec loop i =
    if i >= size then ()
    else (
      write_raw_byte binding (offset + i) (shift_right_u32 n (i * 8));
      loop (i + 1))
  in
  loop 0;
  value

let raw_pointer_key offset = "__rawptr@" ^ string_of_int offset

let read_raw_pointer binding offset =
  match binding.bind_fields with
  | Some fields -> (
      match list_find_opt (fun (field, _) -> field = raw_pointer_key offset) !(fields) with
      | Some (_, cell) -> !(cell)
      | None -> VInt 0)
  | None -> VInt 0

let write_raw_pointer binding offset value =
  match binding.bind_fields with
  | Some fields ->
      let key = raw_pointer_key offset in
      (match list_find_opt (fun (field, _) -> field = key) !(fields) with
      | Some (_, cell) -> cell := value
      | None -> fields := !(fields) @ [ (key, ref value) ]);
      value
  | None -> fail ("not a raw pointer-addressable value: " ^ binding.bind_name)

let raw_overlay_key offset = "__overlay@" ^ string_of_int offset

let parse_numeric_suffix prefix text =
  let prefix_len = String.length prefix in
  if not (has_prefix prefix text) then None
  else
    let rec loop i acc =
      if i >= String.length text then Some acc
      else
        let ch = text.[i] in
        if is_digit ch then loop (i + 1) (acc * 10 + Char.code ch - Char.code '0') else None
    in
    loop prefix_len 0

let clear_struct_overlay value =
  match value with
  | VPtr target | VFieldPtr (target, 0) -> (
      match target.bind_fields with
      | Some fields -> fields := []
      | None -> ())
  | _ -> ()

let reset_raw_metadata_range binding base count value =
  if value <> 0 then ()
  else
    match binding.bind_fields with
    | None -> ()
    | Some fields ->
        let stop = base + count in
        List.iter
          (fun (field, cell) ->
            let clear_offset prefix action =
              match parse_numeric_suffix prefix field with
              | Some offset -> if base <= offset && offset < stop then action cell else ()
              | None -> ()
            in
            clear_offset "__rawptr@" (fun cell -> cell := VInt 0);
            clear_offset "__overlay@" (fun cell -> clear_struct_overlay !(cell)))
          !(fields)

let read_pointer_as ty ptr =
  let size = sizeof_type ty in
  match ptr with
  | VArrayPtr (binding, offset) | VFieldPtr (binding, offset) ->
      if is_raw_byte_binding binding then
        match ty with
        | TPtr _ | TVoid -> read_raw_pointer binding offset
        | _ -> if size > 1 then read_raw_int_as ty binding offset size else read_pointer ptr
      else read_pointer ptr
  | _ -> read_pointer ptr

let write_pointer_as ty ptr value =
  let size = sizeof_type ty in
  match ptr with
  | VArrayPtr (binding, offset) | VFieldPtr (binding, offset) ->
      if is_raw_byte_binding binding then
        match ty with
        | TPtr _ -> write_raw_pointer binding offset value
        | TVoid -> if is_pointer_value value then write_raw_pointer binding offset value else write_pointer ptr value
        | _ -> if size > 1 then write_raw_int binding offset size value else write_pointer ptr value
      else write_pointer ptr value
  | _ -> write_pointer ptr value

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
  (match ptr with
  | VArrayPtr (binding, base) | VFieldPtr (binding, base) -> reset_raw_metadata_range binding base count value
  | _ -> ());
  match ptr with
  | VArrayPtr (binding, base) -> (
      match binding.bind_array, binding.bind_bytes with
      | Some values, None ->
          let elem_size = sizeof_type binding.bind_type in
          let count = if elem_size <= 0 then count else (count + elem_size - 1) / elem_size in
          let rec loop i =
            if i >= count then ()
            else (
              let index = base + i in
              if index >= 0 && index < Array.length values then values.(index) <- coerce_value binding.bind_type (VInt value);
              loop (i + 1))
          in
          loop 0
      | _ ->
          let rec loop i =
            if i >= count then ()
            else (
              write_pointer_byte ptr i value;
              loop (i + 1))
          in
          loop 0)
  | _ ->
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

let raw_allocation_size ptr =
  match ptr with
  | VArrayPtr (binding, 0) | VFieldPtr (binding, 0) -> (
      match binding.bind_bytes with Some bytes -> Some (Array.length bytes) | None -> None)
  | _ -> None

let raw_allocation_values ptr =
  match ptr with
  | VArrayPtr (binding, 0) | VFieldPtr (binding, 0) -> binding.bind_bytes
  | _ -> None

let raw_allocation_binding ptr =
  match ptr with
  | VArrayPtr (binding, 0) | VFieldPtr (binding, 0) -> Some binding
  | _ -> None

let copy_raw_overlays dst src =
  match raw_allocation_binding dst, raw_allocation_binding src with
  | Some dst_binding, Some src_binding -> (
      match dst_binding.bind_fields, src_binding.bind_fields with
      | Some dst_fields, Some src_fields ->
          dst_fields := !(src_fields)
      | _ -> ())
  | _ -> ()

let copy_raw_allocation dst src count =
  match raw_allocation_values dst, raw_allocation_values src with
  | Some dst_values, Some src_values ->
      let limit = min count (min (Array.length dst_values) (Array.length src_values)) in
      let rec loop i =
        if i >= limit then ()
        else (
          dst_values.(i) <- src_values.(i);
          loop (i + 1))
      in
      loop 0;
      copy_raw_overlays dst src
  | _ -> copy_bytes dst src count

let realloc_pointer ptr size =
  if size = 0 then VInt 0
  else
    match ptr with
    | VInt 0 -> fresh_alloc size
    | _ -> (
        match raw_allocation_size ptr with
        | Some old_size ->
            if size <= old_size then ptr
            else
              let dst = fresh_alloc size in
              copy_raw_allocation dst ptr old_size;
              dst
        | None -> ptr)

let c_string_length ptr =
  let rec loop i =
    if byte_of_pointer ptr i = 0 then i else loop (i + 1)
  in
  loop 0

let c_string_text ptr =
  let rec loop i acc =
    let ch = byte_of_pointer ptr i in
    if ch = 0 then string_of_rev_chars acc
    else loop (i + 1) (Char.chr (unsigned_mod ch 256) :: acc)
  in
  loop 0 []

let trace_string_arg value =
  match value with
  | VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ -> c_string_text value
  | _ -> value_summary value

let format_int_base value base upper =
  let digits = if upper then "0123456789ABCDEF" else "0123456789abcdef" in
  let rec loop n acc =
    if n = 0 then acc
    else loop (n / base) (Char.chr (char_code_at digits (n mod base)) :: acc)
  in
  if value = 0 then "0"
  else if value < 0 && base = 10 then "-" ^ String.concat "" (strings_of_chars (loop (-value) []))
  else String.concat "" (strings_of_chars (loop value []))

let format_c_string fmt args =
  let len = String.length fmt in
  let rec take_int args =
    match args with
    | value :: rest -> (int_of_value value, rest)
    | [] -> (0, [])
  in
  let rec take_string args =
    match args with
    | value :: rest -> (trace_string_arg value, rest)
    | [] -> ("", [])
  in
  let rec flags p =
    if p < len then
      match fmt.[p] with
      | '-' | '+' | ' ' | '#' | '0' -> flags (p + 1)
      | _ -> p
    else p
  in
  let rec digits p =
    if p < len && is_digit fmt.[p] then digits (p + 1) else p
  in
  let rec digit_value p acc =
    if p < len && is_digit fmt.[p] then digit_value (p + 1) (acc * 10 + char_code_at fmt p - Char.code '0')
    else (acc, p)
  in
  let rec length_mod p =
    if p < len then
      match fmt.[p] with
      | 'l' | 'h' | 'z' | 't' | 'j' -> length_mod (p + 1)
      | _ -> p
    else p
  in
  let rec loop p args acc =
    if p >= len then string_of_rev_chars acc
    else if fmt.[p] <> '%' then loop (p + 1) args (fmt.[p] :: acc)
    else if p + 1 < len && fmt.[p + 1] = '%' then loop (p + 2) args ('%' :: acc)
    else
      let p = flags (p + 1) in
      let p, args =
        if p < len && fmt.[p] = '*' then
          let _width, args = take_int args in
          (p + 1, args)
        else (digits p, args)
      in
      let precision, p, args =
        if p < len && fmt.[p] = '.' then
          if p + 1 < len && fmt.[p + 1] = '*' then
            let n, args = take_int args in
            (Some n, p + 2, args)
          else
            let n, p = digit_value (p + 1) 0 in
            (Some n, p, args)
        else
          (None, p, args)
      in
      let p = length_mod p in
      if p >= len then string_of_rev_chars acc
      else
        let text, args =
          match fmt.[p] with
          | 's' ->
              let text, args = take_string args in
              let text =
                match precision with
                | Some n -> if n < String.length text then String.sub text 0 n else text
                | None -> text
              in
              (text, args)
          | 'd' | 'i' | 'u' ->
              let n, args = take_int args in
              (string_of_int n, args)
          | 'x' ->
              let n, args = take_int args in
              (format_int_base n 16 false, args)
          | 'X' ->
              let n, args = take_int args in
              (format_int_base n 16 true, args)
          | 'c' ->
              let n, args = take_int args in
              (String.make 1 (Char.chr (unsigned_mod n 256)), args)
          | spec -> (String.make 1 spec, args)
        in
        let rec add_text i acc =
          if i >= String.length text then acc else add_text (i + 1) (text.[i] :: acc)
        in
        loop (p + 1) args (add_text 0 acc)
  in
  loop 0 args []

type host_file = { host_fd : int; host_text : string; host_pos : int ref }

let next_host_fd = ref 3
let host_files = ref []

let read_file_text path =
  host_read_text_file path

let getenv_option name =
  host_getenv name

let is_root_header_path path =
  if not (has_prefix "/" path) then false
  else
    let rec loop i =
      if i >= String.length path then true
      else if path.[i] = '/' then false
      else loop (i + 1)
    in
    loop 1

let host_remap_path path =
  let prefix = "/hcc-bootstrap/include/" in
  if has_prefix prefix path then
    match getenv_option "CCC_HOST_HCC_INCLUDE" with
    | Some include_dir ->
        include_dir ^ "/" ^ String.sub path (String.length prefix) (String.length path - String.length prefix)
    | None -> path
  else if is_root_header_path path then
    match getenv_option "CCC_HOST_HCC_INCLUDE" with
    | Some include_dir -> include_dir ^ "/" ^ String.sub path 1 (String.length path - 1)
    | None -> path
  else path

let host_open_file path =
  let host_path = host_remap_path path in
  try
    let text = read_file_text host_path in
    let fd = !next_host_fd in
    next_host_fd := fd + 1;
    host_files := { host_fd = fd; host_text = text; host_pos = ref 0 } :: !host_files;
    trace ("host open " ^ host_path ^ " fd=" ^ string_of_int fd ^ " bytes=" ^ string_of_int (String.length text));
    fd
  with Sys_error _ ->
    trace ("host open failed " ^ host_path);
    -1

let rec host_find_file fd files =
  match files with
  | [] -> None
  | file :: files -> if file.host_fd = fd then Some file else host_find_file fd files

let host_read_file fd dst count =
  match host_find_file fd !host_files with
  | None -> -1
  | Some file ->
      let available = String.length file.host_text - !(file.host_pos) in
      let count = if count < available then count else available in
      let rec loop i =
        if i >= count then ()
        else (
          write_pointer_byte dst i (Char.code file.host_text.[!(file.host_pos) + i]);
          loop (i + 1))
      in
      loop 0;
      file.host_pos := !(file.host_pos) + count;
      trace ("host read fd=" ^ string_of_int fd ^ " bytes=" ^ string_of_int count);
      count

let host_close_file fd =
  let rec loop acc files =
    match files with
    | [] -> List.rev acc
    | file :: files -> if file.host_fd = fd then List.rev acc @ files else loop (file :: acc) files
  in
  host_files := loop [] !host_files;
  0

let copy_c_string dst src =
  let rec loop i =
    let ch = byte_of_pointer src i in
    write_pointer_byte dst i ch;
    if ch = 0 then () else loop (i + 1)
  in
  loop 0

let write_text_as_c_string dst size text =
  let limit = if size <= 0 then 0 else size - 1 in
  let text_len = String.length text in
  let rec loop i =
    if i >= limit || i >= text_len then ()
    else (
      write_pointer_byte dst i (Char.code text.[i]);
      loop (i + 1))
  in
  if size > 0 then (
    loop 0;
    let nul_at = if text_len < limit then text_len else limit in
    write_pointer_byte dst nul_at 0)

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

let strchr_value ptr ch =
  let rec loop i =
    let here = byte_of_pointer ptr i in
    if here = ch then add_to_value ptr i
    else if here = 0 then VInt 0
    else loop (i + 1)
  in
  loop 0

let strrchr_value ptr ch =
  let rec loop i last =
    let here = byte_of_pointer ptr i in
    let last = if here = ch then Some i else last in
    if here = 0 then match last with Some offset -> add_to_value ptr offset | None -> VInt 0
    else loop (i + 1) last
  in
  loop 0 None

let cstring_binding ptr =
  match ptr with
  | VPtr binding | VFieldPtr (binding, 0) | VArrayPtr (binding, 0) -> Some binding
  | _ -> None

let cstring_append cstr_ptr text =
  match cstring_binding cstr_ptr with
  | None -> ()
  | Some binding ->
      let fields = binding_fields binding in
      let data_cell = field_cell fields "data" in
      let size_cell = field_cell fields "size" in
      let allocated_cell = field_cell fields "size_allocated" in
      let old_size = int_of_value !(size_cell) in
      let needed = old_size + String.length text + 1 in
      let allocated = int_of_value !(allocated_cell) in
      let data =
        if allocated >= needed && is_pointer_value !(data_cell) then !(data_cell)
        else
          let next = realloc_pointer !(data_cell) needed in
          data_cell := next;
          allocated_cell := VInt needed;
          next
      in
      let rec loop i =
        if i >= String.length text then ()
        else (
          write_pointer_byte data (old_size + i) (Char.code text.[i]);
          loop (i + 1))
      in
      loop 0;
      write_pointer_byte data (old_size + String.length text) 0;
      size_cell := VInt (old_size + String.length text)

let is_builtin_name name =
  match name with
  | "malloc" | "calloc" | "realloc" | "free" | "exit"
  | "memset" | "memcpy" | "memmove" | "memcmp"
  | "strlen" | "strcpy" | "strcmp" | "strchr" | "strrchr"
  | "getenv"
  | "open" | "read" | "close"
  | "setjmp" | "longjmp"
  | "_tcc_error"
  | "cstr_printf"
  | "fprintf" | "printf" | "sprintf" | "snprintf"
  | "vfprintf" | "vprintf" | "vsprintf" | "vsnprintf"
  | "ELF64_ST_INFO" | "ELF64_ST_BIND" | "ELF64_ST_TYPE" | "ELF64_ST_VISIBILITY"
  | "check_fields" ->
      true
  | _ -> false

let eval_builtin_call name values =
  match (name, values) with
  | ("malloc" | "calloc"), [ size ] ->
      Some (fresh_alloc (int_of_value size))
  | "calloc", [ count; size ] ->
      Some (fresh_alloc (int_of_value count * int_of_value size))
  | "realloc", [ ptr; size ] ->
      Some (realloc_pointer ptr (int_of_value size))
  | "free", _ -> Some (VInt 0)
  | "exit", [ code ] -> raise (Fatal_exit (int_of_value code))
  | "exit", _ -> raise (Fatal_exit 0)
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
  | "strchr", [ ptr; ch ] -> Some (strchr_value ptr (int_of_value ch))
  | "strrchr", [ ptr; ch ] -> Some (strrchr_value ptr (int_of_value ch))
  | "getenv", [ _ ] -> Some (VInt 0)
  | "open", path :: _ -> Some (VInt (host_open_file (c_string_text path)))
  | "read", [ fd; dst; count ] -> Some (VInt (host_read_file (int_of_value fd) dst (int_of_value count)))
  | "close", [ fd ] -> Some (VInt (host_close_file (int_of_value fd)))
  | "setjmp", [ _ ] -> Some (VInt 0)
  | "longjmp", [ _; value ] ->
      let value = int_of_value value in
      raise (Longjmp (if value = 0 then 1 else value))
  | "longjmp", _ -> raise (Longjmp 1)
  | "cstr_printf", cstr :: fmt :: args ->
      let text = format_c_string (c_string_text fmt) args in
      trace ("cstr_printf text: " ^ text);
      cstring_append cstr text;
      Some (VInt (String.length text))
  | "snprintf", dst :: size :: fmt :: args ->
      let text = format_c_string (c_string_text fmt) args in
      write_text_as_c_string dst (int_of_value size) text;
      Some (VInt (String.length text))
  | "vsnprintf", dst :: size :: fmt :: _ ->
      let text = c_string_text fmt in
      write_text_as_c_string dst (int_of_value size) text;
      Some (VInt (String.length text))
  | ("sprintf" | "vsprintf"), dst :: fmt :: args ->
      let text = format_c_string (c_string_text fmt) args in
      write_text_as_c_string dst (String.length text + 1) text;
      Some (VInt (String.length text))
  | "fprintf", [ VInt 2; fmt; msg ] ->
      let fmt_text = c_string_text fmt in
      if has_prefix "%s" fmt_text then host_stderr_line (c_string_text msg);
      Some (VInt 0)
  | ("fprintf" | "printf" | "vfprintf" | "vprintf"), _ -> Some (VInt 0)
  | "ELF64_ST_INFO", [ bind; typ ] -> Some (VInt (shift_left_u32 (int_of_value bind) 4 + bitwise_and (int_of_value typ) 15))
  | "ELF64_ST_BIND", [ info ] -> Some (VInt (shift_right_u32 (int_of_value info) 4))
  | "ELF64_ST_TYPE", [ info ] -> Some (VInt (bitwise_and (int_of_value info) 15))
  | "ELF64_ST_VISIBILITY", [ other ] -> Some (VInt (bitwise_and (int_of_value other) 3))
  | "check_fields", _ -> Some (VInt 0)
  | _ -> None

let copy_struct_fields target source =
  let target_fields = binding_fields target in
  List.iter
    (fun (field, source_cell) ->
      let target_cell = field_cell target_fields field in
      target_cell := !(source_cell))
    !(binding_fields source)

let copy_struct_fields_prefixed target prefix source =
  let target_fields = binding_fields target in
  List.iter
    (fun (field, source_cell) ->
      let target_cell = field_cell target_fields (prefix ^ "." ^ field) in
      target_cell := !(source_cell))
    !(binding_fields source)

let struct_binding_from_pointer ptr =
  match ptr with
  | VPtr binding -> if option_is_some binding.bind_fields then Some binding else None
  | VFieldPtr (binding, 0) -> if option_is_some binding.bind_fields then Some binding else None
  | VArrayPtr (binding, index) -> (
      match binding.bind_array with
      | Some values ->
          if index >= 0 && index < Array.length values then
            let overlay =
              match binding.bind_fields with
              | Some fields -> (
                  let key = raw_overlay_key index in
                  match list_find_opt (fun (field, _) -> field = key) !(fields) with
                  | Some (_, cell) -> (
                      match !(cell) with
                      | VPtr target | VFieldPtr (target, 0) -> Some target
                      | _ -> None)
                  | None -> None)
              | None -> None
            in
            match overlay with
            | Some target -> Some target
            | None -> (
                match values.(index) with
                | VPtr target | VFieldPtr (target, 0) -> Some target
                | _ -> if index = 0 && option_is_some binding.bind_fields then Some binding else None)
          else None
      | None -> if index = 0 && option_is_some binding.bind_fields then Some binding else None)
  | _ -> None

let struct_name_of_type ty =
  match ty with
  | TOther name ->
      if has_prefix "struct " name then Some (String.sub name 7 (String.length name - 7))
      else Some name
  | _ -> None

let struct_layout_fields structs ty =
  match struct_name_of_type ty with
  | None -> None
  | Some name -> (
      match list_find_opt (fun layout -> layout.struct_name = name) structs with
      | Some layout -> Some layout.struct_fields
      | None -> None)

let set_binding_layout structs binding =
  match !(binding.bind_layout) with
  | Some _ -> ()
  | None -> binding.bind_layout := struct_layout_fields structs binding.bind_type

let typed_struct_binding_from_pointer structs ptr owner_ty =
  let layout = struct_layout_fields structs owner_ty in
  match ptr with
  | VArrayPtr (binding, index) -> (
      match binding.bind_array, binding.bind_bytes with
      | Some values, Some bytes ->
          if index >= 0 && index < Array.length values then
            if (match binding.bind_type with TUnsignedChar -> true | _ -> false) then
              let fields = binding_fields binding in
              let key = raw_overlay_key index in
              match list_find_opt (fun (field, _) -> field = key) !(fields) with
              | Some (_, cell) -> (
                  match !(cell) with
                  | VPtr target | VFieldPtr (target, 0) -> Some target
                  | _ -> None)
              | None ->
                  let target =
                    {
                      bind_name = binding.bind_name ^ "@" ^ string_of_int index;
                      bind_type = owner_ty;
                      bind_value = ref (VInt index);
                      bind_string = None;
                      bind_array = Some values;
                      bind_bytes = Some bytes;
                      bind_fields = Some (ref []);
                      bind_layout = ref layout;
                    }
                  in
                  fields := !(fields) @ [ (key, ref (VPtr target)) ];
                  Some target
            else
              match values.(index) with
              | VPtr target | VFieldPtr (target, 0) -> Some target
              | _ ->
                  let target =
                    {
                      bind_name = binding.bind_name ^ "@" ^ string_of_int index;
                      bind_type = owner_ty;
                      bind_value = ref (VInt index);
                      bind_string = None;
                      bind_array = Some values;
                      bind_bytes = Some bytes;
                      bind_fields = Some (ref []);
                      bind_layout = ref layout;
                    }
                  in
                  values.(index) <- VPtr target;
                  Some target
          else None
      | _ -> struct_binding_from_pointer ptr)
  | _ -> struct_binding_from_pointer ptr

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

let struct_field_type structs ty field_name =
  match struct_field_layout structs ty field_name with
  | Some field -> Some field.field_type
  | None -> None

let pointer_delta_for_value structs ty value delta =
  match ty, value with
  | TPtr elem, (VArrayPtr (binding, _) | VFieldPtr (binding, _)) -> (
      match binding.bind_type, binding.bind_bytes with
      | TUnsignedChar, Some _ ->
          let elem_size = match struct_size structs elem with Some size -> size | None -> sizeof_type elem in
          delta * elem_size
      | _ -> delta)
  | TPtr elem, _ ->
      let elem_size = match struct_size structs elem with Some size -> size | None -> sizeof_type elem in
      delta * elem_size
  | _ -> delta

let rec pointer_owner_type structs env expr fallback =
  match expr with
  | EVar name -> (
      try
        match (find_binding name env).bind_type with
        | TPtr ty -> ty
        | _ -> fallback
      with Compile_error _ -> fallback)
  | EUpdateExpr (name, _, _) -> (
      try
        match (find_binding name env).bind_type with
        | TPtr ty -> ty
        | _ -> fallback
      with Compile_error _ -> fallback)
  | EIndex (EVar name, _) -> (
      try
        let binding = find_binding name env in
        match binding.bind_array, binding.bind_type with
        | Some _, TPtr ty -> ty
        | _, TPtr (TPtr ty) -> ty
        | _ -> fallback
      with Compile_error _ -> fallback)
  | EIndex (base, _) -> (
      match pointer_owner_type structs env base fallback with
      | TPtr ty -> ty
      | _ -> fallback)
  | EMember (base, field) -> (
      let owner_ty =
        match base with
        | EVar name -> (
            try (find_binding name env).bind_type with Compile_error _ -> TVoid)
        | _ -> fallback
      in
      match struct_field_type structs owner_ty field with
      | Some (TPtr ty) -> ty
      | _ -> fallback)
  | EPtrMember (base, field) -> (
      let owner_ty = pointer_owner_type structs env base TVoid in
      match struct_field_type structs owner_ty field with
      | Some (TPtr ty) -> ty
      | _ -> fallback)
  | EUnary (Addr, EVar name) -> (
      try (find_binding name env).bind_type with Compile_error _ -> fallback)
  | EUnary (Deref, ptr) -> (
      match pointer_owner_type structs env ptr fallback with
      | TPtr ty -> ty
      | _ -> fallback)
  | ECast (TPtr ty, _) -> ty
  | _ -> fallback

let expression_pointer_delta structs env expr value delta =
  pointer_delta_for_value structs (TPtr (pointer_owner_type structs env expr TVoid)) value delta

let binding_byte_base binding =
  match binding.bind_bytes, !(binding.bind_value) with
  | Some _, VInt offset -> offset
  | _ -> 0

let binding_field_byte_offset binding layout =
  binding_byte_base binding + layout.field_offset

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
      bind_fields = None;
      bind_layout = ref None;
    }

let struct_name_for_fields ty =
  match ty with
  | TOther name ->
      if has_prefix "struct " name then Some (String.sub name 7 (String.length name - 7))
      else Some name
  | _ -> None

let struct_field_names_for_type structs ty =
  match struct_name_for_fields ty with
  | None -> []
  | Some name -> (
      match list_find_opt (fun layout -> layout.struct_name = name) structs with
      | Some layout -> List.map (fun field -> field.field_name) layout.struct_fields
      | None -> [])

let prefixed_struct_field_pointer structs binding field ty =
  let names = struct_field_names_for_type structs ty in
  match names with
  | [] -> scalar_field_pointer binding field
  | _ ->
      let parent_fields = binding_fields binding in
      let fields =
        ref
          (List.map
             (fun name -> (name, field_cell parent_fields (field ^ "." ^ name)))
             names)
      in
      VPtr
        {
          bind_name = binding.bind_name ^ "." ^ field;
          bind_type = ty;
          bind_value = field_cell parent_fields field;
          bind_string = None;
          bind_array = None;
          bind_bytes = binding.bind_bytes;
          bind_fields = Some fields;
          bind_layout = ref (struct_layout_fields structs ty);
        }

let field_pointer structs binding owner_ty field =
  match struct_field_layout structs owner_ty field with
  | Some layout ->
      if layout.field_is_array then VFieldPtr (binding, binding_field_byte_offset binding layout)
      else if struct_field_names_for_type structs layout.field_type <> [] then prefixed_struct_field_pointer structs binding field layout.field_type
      else if (match layout.field_type with TPtr _ -> true | _ -> false) then scalar_field_pointer binding field
      else if has_prefix "__alloc" binding.bind_name then scalar_field_pointer binding field
      else VFieldPtr (binding, layout.field_offset)
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

let tcc_error_recover env args =
  match find_binding_opt "tcc_state" env with
  | Some state_binding -> (
      match struct_binding_from_pointer !(state_binding.bind_value) with
      | Some state ->
          let fields = binding_fields state in
          let nb_errors = field_cell fields "nb_errors" in
          nb_errors := VInt (int_of_value !(nb_errors) + 1);
          trace ("_tcc_error args: " ^ String.concat " | " (List.map trace_string_arg args));
          trace ("_tcc_error recovery enabled=" ^ value_summary (!(field_cell fields "error_set_jmp_enabled")));
          if truth_value (!(field_cell fields "error_set_jmp_enabled")) then raise (Longjmp 1)
          else raise (Fatal_exit 1)
      | None -> raise (Fatal_exit 1))
  | None -> raise (Fatal_exit 1)

let trace_local_value env name =
  match find_binding_opt name env with
  | Some binding -> name ^ "=" ^ value_summary !(binding.bind_value)
  | None -> name ^ "=<missing>"

let trace_tcc_expect env values =
  if trace_enabled () then
    let file_line =
      match find_binding_opt "file" env with
      | Some binding -> (
          match struct_binding_from_pointer !(binding.bind_value) with
          | Some file ->
              " file.line_num=" ^ value_summary !(field_cell (binding_fields file) "line_num")
          | None -> "")
      | None -> ""
    in
    let gnu_ext =
      match find_binding_opt "tcc_state" env with
      | Some binding -> (
          match struct_binding_from_pointer !(binding.bind_value) with
          | Some state -> " tcc_state.gnu_ext=" ^ value_summary !(field_cell (binding_fields state) "gnu_ext")
          | None -> "")
      | None -> ""
    in
    trace
      ("expect args: " ^ String.concat " | " (List.map trace_string_arg values) ^ " "
       ^ trace_local_value env "tok" ^ " " ^ trace_local_value env "v" ^ " "
       ^ trace_local_value env "l" ^ " " ^ trace_local_value env "td" ^ " "
       ^ trace_local_value env "n" ^ file_line ^ gnu_ext)

let pointer_delta a b =
  match (a, b) with
  | VPtr x, VPtr y -> if x == y then Some 0 else None
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
      match pointer_delta a b with Some delta -> VInt delta | None -> fail ("unsupported subtraction: " ^ value_summary a ^ " - " ^ value_summary b))

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
        | EVar name ->
            let binding = find_binding name env in
            (match binding.bind_array with
            | Some _ -> read_binding_index binding index_value
            | None ->
                let ptr = !(binding.bind_value) in
                let delta = pointer_delta_for_value structs binding.bind_type ptr index_value in
                let elem_ty = match binding.bind_type with TPtr ty -> ty | _ -> TVoid in
                read_pointer_as elem_ty (add_to_value ptr delta))
        | EMember (EVar name, field) ->
            let binding = find_binding name env in
            (match struct_field_layout structs binding.bind_type field with
            | Some layout ->
                if layout.field_is_array then read_pointer_as layout.field_type (VFieldPtr (binding, binding_field_byte_offset binding layout + index_value))
                else
                let expr = EMember (EVar name, field) in
                let ptr = eval_value funcs structs globals env expr in
                let delta = expression_pointer_delta structs env expr ptr index_value in
                read_pointer_as (pointer_owner_type structs env expr TVoid) (add_to_value ptr delta)
            | _ -> !(field_index_cell (binding_fields binding) field index_value))
        | EPtrMember (base, field) ->
            let owner_ty = pointer_owner_type structs env base TVoid in
            let ptr = eval_value funcs structs globals env base in
            let target =
              match typed_struct_binding_from_pointer structs ptr owner_ty with
              | Some target -> target
              | None -> fail ("not a struct pointer for index " ^ field ^ ": " ^ value_summary ptr)
            in
            (match struct_field_layout structs owner_ty field with
            | Some layout ->
                if layout.field_is_array then read_pointer_as layout.field_type (VFieldPtr (target, binding_field_byte_offset target layout + index_value))
                else
                let expr = EPtrMember (base, field) in
                let ptr = eval_value funcs structs globals env expr in
                let delta = expression_pointer_delta structs env expr ptr index_value in
                read_pointer_as (pointer_owner_type structs env expr TVoid) (add_to_value ptr delta)
            | _ -> !(field_index_cell (binding_fields target) field index_value))
        | EString text -> VInt (string_byte text index_value)
        | expr ->
            let ptr = eval_value funcs structs globals env expr in
            let delta = expression_pointer_delta structs env expr ptr index_value in
            read_pointer_as (pointer_owner_type structs env expr TVoid) (add_to_value ptr delta)
      in
      value
  | EMember (EMember (base, parent), field) ->
      eval_value funcs structs globals env (EMember (base, parent ^ "." ^ field))
  | EMember (EPtrMember (base, parent), field) ->
      eval_value funcs structs globals env (EPtrMember (base, parent ^ "." ^ field))
  | EMember (base, field) ->
      let binding =
        match base with
        | EVar name -> find_binding name env
        | EIndex (indexed_base, index) ->
            let index_value = eval_expr funcs structs globals env index in
            let ptr = eval_value funcs structs globals env indexed_base in
            let address = add_to_value ptr (expression_pointer_delta structs env indexed_base ptr index_value) in
            let owner_ty = pointer_owner_type structs env indexed_base TVoid in
            (match typed_struct_binding_from_pointer structs address owner_ty with
            | Some target -> target
            | None -> fail ("not an indexed struct for member " ^ field ^ ": " ^ value_summary address))
        | EUnary (Deref, ptr) -> (
            let owner_ty = pointer_owner_type structs env ptr TVoid in
            let ptr_value = eval_value funcs structs globals env ptr in
            match typed_struct_binding_from_pointer structs ptr_value owner_ty with
            | Some target -> target
            | None ->
                fail
                  ("not a struct pointer for assign " ^ field ^ " via " ^ expr_summary ptr ^ ": "
                   ^ value_summary ptr_value))
        | _ -> fail ("unsupported member expression: " ^ expr_summary base ^ "." ^ field)
      in
      (match struct_field_layout structs binding.bind_type field with
      | Some layout ->
          if layout.field_is_array then VFieldPtr (binding, binding_field_byte_offset binding layout)
          else !(field_cell (binding_fields binding) field)
      | None ->
          if field = "tab" then field_array_pointer binding field
          else !(field_cell (binding_fields binding) field))
  | EPtrMember (EVar name, field) ->
      let pointer_binding = find_binding name env in
      let owner_ty =
        match pointer_binding.bind_type with
        | TPtr ty -> ty
        | _ -> TVoid
      in
      let ptr = eval_value funcs structs globals env (EVar name) in
      (match ptr with
      | VInt 0 -> VInt 0
      | _ ->
          let target =
            match typed_struct_binding_from_pointer structs ptr owner_ty with
            | Some target -> target
            | None ->
                trace ("not struct pointer field " ^ field ^ " from " ^ name ^ " = " ^ value_summary ptr);
                fail ("not a struct pointer field " ^ field ^ " from " ^ name ^ " = " ^ value_summary ptr)
          in
          (match struct_field_layout structs owner_ty field with
          | Some layout ->
              if layout.field_is_array then VFieldPtr (target, binding_field_byte_offset target layout)
              else
                !(field_cell (binding_fields target) field)
          | None ->
              if field = "tab" then field_array_pointer target field
              else !(field_cell (binding_fields target) field)))
  | EPtrMember (base, field) ->
      let owner_ty = pointer_owner_type structs env base TVoid in
      let ptr = eval_value funcs structs globals env base in
      (match ptr with
      | VInt 0 -> VInt 0
      | _ ->
          let target =
            match typed_struct_binding_from_pointer structs ptr owner_ty with
            | Some target -> target
            | None ->
                trace ("not struct pointer field " ^ field ^ " from expression = " ^ value_summary ptr);
                fail ("not a struct pointer field " ^ field ^ " from expression = " ^ value_summary ptr)
          in
          (match struct_field_layout structs owner_ty field with
          | Some layout ->
              if layout.field_is_array then VFieldPtr (target, binding_field_byte_offset target layout)
              else !(field_cell (binding_fields target) field)
          | None ->
              if field = "tab" then field_array_pointer target field
              else !(field_cell (binding_fields target) field)))
  | EAssignExpr (name, expr) ->
      let target = find_binding name env in
      (match target.bind_fields, expr with
      | Some _, EVar source_name -> (
          let source = find_binding source_name env in
          match source.bind_fields with
          | Some _ ->
              copy_struct_fields target source;
              VInt 0
          | None ->
              let value = eval_value funcs structs globals env expr in
              let _ = assoc_set_value name value env in
              !(target.bind_value))
      | Some _, EUnary (Deref, ptr_expr) -> (
          let ptr_value = eval_value funcs structs globals env ptr_expr in
          match struct_binding_from_pointer ptr_value with
          | Some source ->
              copy_struct_fields target source;
              VInt 0
          | None ->
              let value = read_pointer_as (pointer_owner_type structs env ptr_expr TVoid) ptr_value in
              let _ = assoc_set_value name value env in
              !(target.bind_value))
      | _ ->
          let value = eval_value funcs structs globals env expr in
          let _ = assoc_set_value name value env in
          !(target.bind_value))
  | EAssignDeref (ptr, expr) ->
      let ptr_value = eval_value funcs structs globals env ptr in
      let owner_ty = pointer_owner_type structs env ptr TVoid in
      let struct_source =
        if struct_field_names_for_type structs owner_ty = [] then None
        else
          match expr with
          | EVar name -> (
              try
                let source = find_binding name env in
                match source.bind_fields with
                | Some _ -> Some source
                | None -> None
              with Compile_error _ -> None)
          | EUnary (Deref, source_ptr) -> struct_binding_from_pointer (eval_value funcs structs globals env source_ptr)
          | _ -> None
      in
      (match struct_source with
      | Some source ->
          if option_is_some source.bind_fields then
            match typed_struct_binding_from_pointer structs ptr_value owner_ty with
            | Some target ->
                copy_struct_fields target source;
                VInt 0
            | None ->
                let value = eval_value funcs structs globals env expr in
                write_pointer_as owner_ty ptr_value value
          else
            let value = eval_value funcs structs globals env expr in
            write_pointer_as owner_ty ptr_value value
      | None ->
          let value = eval_value funcs structs globals env expr in
          write_pointer_as owner_ty ptr_value value)
  | EAssignIndex (base, index, expr) ->
      let index_value = eval_expr funcs structs globals env index in
      let value = eval_value funcs structs globals env expr in
      let written =
        match base with
        | EVar name ->
            let binding = find_binding name env in
            (match binding.bind_array with
            | Some _ -> write_binding_index binding index_value value
            | None ->
                let ptr = !(binding.bind_value) in
                let delta = pointer_delta_for_value structs binding.bind_type ptr index_value in
                let elem_ty = match binding.bind_type with TPtr ty -> ty | _ -> TVoid in
                write_pointer_as elem_ty (add_to_value ptr delta) value)
        | EMember (EVar name, field) ->
            let binding = find_binding name env in
            (match struct_field_layout structs binding.bind_type field with
            | Some layout ->
                if layout.field_is_array then write_pointer_as layout.field_type (VFieldPtr (binding, binding_field_byte_offset binding layout + index_value)) value
                else
                let expr = EMember (EVar name, field) in
                let ptr = eval_value funcs structs globals env expr in
                let delta = expression_pointer_delta structs env expr ptr index_value in
                write_pointer_as (pointer_owner_type structs env expr TVoid) (add_to_value ptr delta) value
            | _ ->
                let cell = field_index_cell (binding_fields binding) field index_value in
                cell := value;
                value)
        | EPtrMember (base, field) ->
            let owner_ty = pointer_owner_type structs env base TVoid in
            let ptr = eval_value funcs structs globals env base in
            let target =
              match typed_struct_binding_from_pointer structs ptr owner_ty with
              | Some target -> target
              | None -> fail ("not a struct pointer for index assign " ^ field ^ ": " ^ value_summary ptr)
            in
            (match struct_field_layout structs owner_ty field with
            | Some layout ->
                if layout.field_is_array then write_pointer_as layout.field_type (VFieldPtr (target, binding_field_byte_offset target layout + index_value)) value
                else
                let expr = EPtrMember (base, field) in
                let ptr = eval_value funcs structs globals env expr in
                let delta = expression_pointer_delta structs env expr ptr index_value in
                write_pointer_as (pointer_owner_type structs env expr TVoid) (add_to_value ptr delta) value
            | _ ->
                let cell = field_index_cell (binding_fields target) field index_value in
                cell := value;
                value)
        | expr ->
            let ptr = eval_value funcs structs globals env expr in
            let delta = expression_pointer_delta structs env expr ptr index_value in
            write_pointer_as (pointer_owner_type structs env expr TVoid) (add_to_value ptr delta) value
      in
      written
  | EAssignMember (EMember (base, parent), field, expr) ->
      eval_value funcs structs globals env (EAssignMember (base, parent ^ "." ^ field, expr))
  | EAssignMember (EPtrMember (base, parent), field, expr) ->
      eval_value funcs structs globals env (EAssignMember (EUnary (Deref, base), parent ^ "." ^ field, expr))
  | EAssignMember (base, field, expr) ->
      let binding =
        match base with
        | EVar name -> find_binding name env
        | EIndex (indexed_base, index) ->
            let index_value = eval_expr funcs structs globals env index in
            let ptr = eval_value funcs structs globals env indexed_base in
            let address = add_to_value ptr (expression_pointer_delta structs env indexed_base ptr index_value) in
            let owner_ty = pointer_owner_type structs env indexed_base TVoid in
            (match typed_struct_binding_from_pointer structs address owner_ty with
            | Some target -> target
            | None -> fail ("not an indexed struct for assign " ^ field ^ ": " ^ value_summary address))
        | EUnary (Deref, ptr) -> (
            let owner_ty = pointer_owner_type structs env ptr TVoid in
            let ptr_value = eval_value funcs structs globals env ptr in
            match typed_struct_binding_from_pointer structs ptr_value owner_ty with
            | Some target -> target
            | None ->
                fail
                  ("not a struct pointer for member " ^ field ^ " via " ^ expr_summary ptr ^ ": "
                   ^ value_summary ptr_value))
        | _ -> fail ("unsupported member expression: " ^ expr_summary base ^ "." ^ field)
      in
      (match expr with
      | EUnary (Deref, ptr_expr) -> (
          let ptr_value = eval_value funcs structs globals env ptr_expr in
          match binding.bind_fields, struct_binding_from_pointer ptr_value with
          | Some _, Some source ->
              if option_is_some source.bind_fields then (
                copy_struct_fields_prefixed binding field source;
                let cell = field_cell (binding_fields binding) field in
                cell := VPtr source;
                VInt 0)
              else
                let value = read_pointer_as (pointer_owner_type structs env ptr_expr TVoid) ptr_value in
                let cell = field_cell (binding_fields binding) field in
                cell := value;
                value
          | _ ->
              let value = read_pointer_as (pointer_owner_type structs env ptr_expr TVoid) ptr_value in
              let cell = field_cell (binding_fields binding) field in
              cell := value;
              value)
      | _ ->
          let value = eval_value funcs structs globals env expr in
          let cell = field_cell (binding_fields binding) field in
          cell := value;
          value)
  | EUpdateExpr (name, delta, prefix) ->
      let binding = find_binding name env in
      let old_value = !(binding.bind_value) in
      let delta = pointer_delta_for_value structs binding.bind_type old_value delta in
      let new_value = coerce_value binding.bind_type (add_to_value old_value delta) in
      binding.bind_value := new_value;
      if prefix then new_value else old_value
  | EUpdateLvalue (target, delta, prefix) ->
      (match target with
      | EIndex (base, index) ->
          let index_value = eval_expr funcs structs globals env index in
          let ptr =
            match base with
            | EVar name ->
                let binding = find_binding name env in
                (match binding.bind_array with
                | Some _ -> VPtr binding
                | None ->
                    let ptr = !(binding.bind_value) in
                    add_to_value ptr (pointer_delta_for_value structs binding.bind_type ptr index_value))
            | expr ->
                let ptr = eval_value funcs structs globals env expr in
                let delta = expression_pointer_delta structs env expr ptr index_value in
                add_to_value ptr delta
          in
          let elem_ty =
            match base with
            | EVar name -> (
                match (find_binding name env).bind_type with TPtr ty -> ty | _ -> pointer_owner_type structs env base TVoid)
            | _ -> pointer_owner_type structs env base TVoid
          in
          let old_value =
            match base with
            | EVar name ->
                let binding = find_binding name env in
                (match binding.bind_array with Some _ -> read_binding_index binding index_value | None -> read_pointer_as elem_ty ptr)
            | _ -> read_pointer_as elem_ty ptr
          in
          let new_value = add_to_value old_value (pointer_delta_for_value structs elem_ty old_value delta) in
          let _ =
            match base with
            | EVar name ->
                let binding = find_binding name env in
                (match binding.bind_array with Some _ -> write_binding_index binding index_value new_value | None -> write_pointer_as elem_ty ptr new_value)
            | _ -> write_pointer_as elem_ty ptr new_value
          in
          if prefix then new_value else old_value
      | EUnary (Deref, ptr_expr) ->
          let ptr = eval_value funcs structs globals env ptr_expr in
          let elem_ty = pointer_owner_type structs env ptr_expr TVoid in
          let old_value = read_pointer_as elem_ty ptr in
          let new_value = add_to_value old_value (pointer_delta_for_value structs elem_ty old_value delta) in
          let _ = write_pointer_as elem_ty ptr new_value in
          if prefix then new_value else old_value
      | _ ->
          let cell =
            match target with
            | EMember (EVar name, field) ->
                field_cell (binding_fields (find_binding name env)) field
            | EPtrMember (base, field) ->
                let binding =
                  let owner_ty = pointer_owner_type structs env base TVoid in
                  let ptr_value = eval_value funcs structs globals env base in
                  match typed_struct_binding_from_pointer structs ptr_value owner_ty with
                  | Some target -> target
                  | None -> fail ("not a struct pointer for update " ^ field ^ ": " ^ value_summary ptr_value)
                in
                field_cell (binding_fields binding) field
            | _ -> fail "unsupported update target"
          in
          let old_value = !(cell) in
          let new_value = add_to_value old_value delta in
          cell := new_value;
          if prefix then new_value else old_value)
  | EUnary (Neg, e) -> VInt (- eval_expr funcs structs globals env e)
  | EUnary (Not, e) -> VInt (bool_int (not (truth_value (eval_value funcs structs globals env e))))
  | EUnary (BNot, e) -> VInt (bitwise_not (eval_expr funcs structs globals env e))
  | ECond (cond, yes, no) ->
      if truth_value (eval_value funcs structs globals env cond) then eval_value funcs structs globals env yes else eval_value funcs structs globals env no
  | EUnary (Deref, e) -> read_pointer_as (pointer_owner_type structs env e TVoid) (eval_value funcs structs globals env e)
  | EUnary (Addr, EVar name) ->
      let binding = find_binding name env in
      (match binding.bind_fields with Some _ -> VFieldPtr (binding, 0) | None -> VPtr binding)
  | EUnary (Addr, EIndex (base, index)) ->
      let index_value = eval_expr funcs structs globals env index in
      let ptr = eval_value funcs structs globals env base in
      add_to_value ptr (expression_pointer_delta structs env base ptr index_value)
  | EUnary (Addr, EMember (EVar name, field)) ->
      let binding = find_binding name env in
      field_pointer structs binding binding.bind_type field
  | EUnary (Addr, EPtrMember (ECast (TPtr owner_ty, EInt 0), field)) ->
      VInt (match struct_field_offset structs owner_ty field with Some offset -> offset | None -> 0)
  | EUnary (Addr, EPtrMember (EVar name, field)) ->
      let pointer_binding = find_binding name env in
      let owner_ty =
        match pointer_binding.bind_type with
        | TPtr ty -> ty
        | _ -> TVoid
      in
      let target =
        let ptr_value = eval_value funcs structs globals env (EVar name) in
        match typed_struct_binding_from_pointer structs ptr_value owner_ty with
        | Some target -> target
        | None -> fail ("not a struct pointer for address " ^ field ^ ": " ^ value_summary ptr_value)
      in
      field_pointer structs target owner_ty field
  | EUnary (Addr, EPtrMember (base, field)) ->
      let owner_ty = pointer_owner_type structs env base TVoid in
      let target =
        let ptr_value = eval_value funcs structs globals env base in
        match typed_struct_binding_from_pointer structs ptr_value owner_ty with
        | Some target -> target
        | None -> fail ("not a struct pointer for address " ^ field ^ ": " ^ value_summary ptr_value)
      in
      field_pointer structs target owner_ty field
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
  | EBinary (Add, a, b) ->
      let av = eval_value funcs structs globals env a in
      let bv = eval_value funcs structs globals env b in
      (match av, bv with
      | (VArrayPtr _ | VFieldPtr _ | VStringPtr _ as ptr), VInt n ->
          add_to_value ptr (expression_pointer_delta structs env a ptr n)
      | VInt n, (VArrayPtr _ | VFieldPtr _ | VStringPtr _ as ptr) ->
          add_to_value ptr (expression_pointer_delta structs env b ptr n)
      | _ -> add_values av bv)
  | EBinary (Sub, a, b) ->
      let av = eval_value funcs structs globals env a in
      let bv = eval_value funcs structs globals env b in
      (match av, bv with
      | (VArrayPtr _ | VFieldPtr _ | VStringPtr _ as ptr), VInt n ->
          add_to_value ptr (- expression_pointer_delta structs env a ptr n)
      | _ -> sub_values av bv)
  | EBinary ((Lt | Le | Gt | Ge) as op, a, b) ->
      let av = eval_value funcs structs globals env a in
      let bv = eval_value funcs structs globals env b in
      let result =
        match pointer_compare av bv with
        | Some cmp -> (
            match op with
            | Lt -> cmp < 0
            | Le -> cmp <= 0
            | Gt -> cmp > 0
            | Ge -> cmp >= 0
            | _ -> fail "internal non-comparison operator")
        | None ->
            if is_pointer_value av || is_pointer_value bv then false
            else (
              let cmp = compare (int_of_value av) (int_of_value bv) in
              match op with
              | Lt -> cmp < 0
              | Le -> cmp <= 0
              | Gt -> cmp > 0
              | Ge -> cmp >= 0
              | _ -> fail "internal non-comparison operator")
      in
      VInt (bool_int result)
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
      | Land | Lor -> fail "internal short-circuit operator")
  | ECall ("_exit", [ arg ]) -> VInt (eval_expr funcs structs globals env arg)
  | ECall (name, args) ->
      let values = List.map (call_arg funcs structs globals env) args in
      let target =
        match find_binding_opt name env with
        | Some binding -> (match !(binding.bind_value) with VFunc target -> target | _ -> name)
        | None -> name
      in
      if target = "expect" then trace_tcc_expect env values;
      if target = "_tcc_error" then tcc_error_recover env values
      else (match eval_builtin_call target values with
      | Some value -> value
      | None -> eval_func funcs structs globals target values)
  | ECallExpr (callee, args) ->
      let values = List.map (call_arg funcs structs globals env) args in
      let target =
        match eval_value funcs structs globals env callee with
        | VFunc name -> name
        | _ -> fail "called expression is not a function"
      in
      if target = "_tcc_error" then tcc_error_recover env values
      else (match eval_builtin_call target values with
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
	  | EUnary (Deref, EVar name) -> (
	      match find_binding_opt name env with
	      | Some binding -> sizeof_type binding.bind_type
	      | None -> 4)
	  | EUnary (Deref, _) -> 4
	  | EIndex _ -> 1
  | expr -> (
      match eval_value funcs structs globals env expr with
      | VInt _ -> 4
      | VPtr _ | VArrayPtr _ | VFieldPtr _ | VStringPtr _ | VFunc _ -> 8)

and eval_expr funcs structs globals env expr =
  let value = eval_value funcs structs globals env expr in
  (match value with
  | VInt n -> n
  | _ ->
      trace ("integer context for " ^ expr_summary expr ^ " = " ^ value_summary value);
      int_of_value value)

and call_arg funcs structs globals env expr =
  eval_value funcs structs globals env expr

and bind_params params args =
  match (params, args) with
  | [], _ -> []
  | param :: params, value :: args ->
      {
        bind_name = param.param_name;
        bind_type = param.param_type;
        bind_value = ref (coerce_value param.param_type value);
        bind_string = None;
        bind_array = None;
        bind_bytes = None;
        bind_fields = None;
        bind_layout = ref None;
      }
      :: bind_params params args
  | _ :: _, [] -> fail "internal parameter binding arity mismatch"

and eval_func funcs structs globals name args =
  trace ("call " ^ name ^ "/" ^ string_of_int (List.length args));
  if name = "_tcc_warning" || name = "_tcc_error" || name = "_tcc_error_noabort" then
    trace (name ^ " args: " ^ String.concat " | " (List.map trace_string_arg args));
  let fn =
    match list_find_opt (fun fn -> fn.name = name) funcs with
    | Some fn -> fn
    | None -> fail ("unknown function: " ^ name)
  in
  if (if fn.variadic then not (has_at_least fn.params args) else not (same_length fn.params args)) then fail ("wrong argument count: " ^ name) else
  let env = bind_params fn.params args @ globals in
  List.iter (set_binding_layout structs) env;
  let env = assoc_decl_full (Some name) None None (TPtr TChar) "__func__" (VStringPtr (name, 0)) env in
  let rec flat_label_stmt stmt =
    match stmt with
    | Labeled (name, body) -> Label name :: flat_label_stmt body
    | _ -> [ stmt ]
  in
  let rec flat_label_stmts stmts =
    match stmts with
    | [] -> []
    | stmt :: rest -> flat_label_stmt stmt @ flat_label_stmts rest
  in
  let flat_body = Array.of_list (flat_label_stmts fn.body) in
  let flat_label_index label =
    let rec loop i =
      if i >= Array.length flat_body then None
      else
        match flat_body.(i) with
        | Label name -> if name = label then Some (i + 1) else loop (i + 1)
        | _ -> loop (i + 1)
    in
    loop 0
  in
  let rec run_flat_at i env =
    if i >= Array.length flat_body then Continue env
    else
      match exec_stmt funcs structs globals env flat_body.(i) with
      | Continue env' -> run_flat_at (i + 1) env'
      | Jumped (label, env') -> (
          match flat_label_index label with
          | Some j -> run_flat_at j env'
          | None -> Jumped (label, env'))
      | other -> other
  in
  let local_label_tail label stmt =
    let rec loop stmts =
      match stmts with
      | [] -> None
      | Label name :: rest -> if name = label then Some rest else loop rest
      | _ :: rest -> loop rest
    in
    loop (label_flatten_stmt stmt)
  in
  let rec first_label_run label stmts env =
    match stmts with
    | [] -> None
    | stmt :: rest -> (
        match stmt_from_label label stmt env with
        | Some (Continue env') -> Some (exec_block funcs structs globals rest env')
        | Some result -> Some result
        | None -> first_label_run label rest env)
  and stmt_from_label label stmt env =
    match stmt with
    | While (cond, body) -> (
        match local_label_tail label body with
        | None -> stmt_child_from_label label stmt env
        | Some rest ->
            let rec loop env =
              if truth_value (eval_value funcs structs globals env cond) then
                match exec_stmt funcs structs globals env body with
                | Continue env' -> loop env'
                | Continued env' -> loop env'
                | Broke env' -> Continue env'
                | Jumped (label, env') -> (
                    match local_label_tail label body with
                    | Some rest -> run_from_tail rest env'
                    | None -> Jumped (label, env'))
                | other -> other
              else Continue env
            and run_from_tail rest env =
              match exec_block funcs structs globals rest env with
              | Continue env' -> loop env'
              | Continued env' -> loop env'
              | Broke env' -> Continue env'
              | other -> other
            in
            Some (run_from_tail rest env))
    | DoWhile (body, cond) -> (
        match local_label_tail label body with
        | None -> stmt_child_from_label label stmt env
        | Some rest ->
            let rec loop env =
              match exec_stmt funcs structs globals env body with
              | Continue env' -> if truth_value (eval_value funcs structs globals env' cond) then loop env' else Continue env'
              | Continued env' -> if truth_value (eval_value funcs structs globals env' cond) then loop env' else Continue env'
              | Broke env' -> Continue env'
              | Jumped (label, env') -> (
                  match local_label_tail label body with
                  | Some rest -> run_from_tail rest env'
                  | None -> Jumped (label, env'))
              | other -> other
            and run_from_tail rest env =
              match exec_block funcs structs globals rest env with
              | Continue env' -> if truth_value (eval_value funcs structs globals env' cond) then loop env' else Continue env'
              | Continued env' -> if truth_value (eval_value funcs structs globals env' cond) then loop env' else Continue env'
              | Broke env' -> Continue env'
              | other -> other
            in
            Some (run_from_tail rest env))
    | For (init, cond, post, body) -> (
        match local_label_tail label body with
        | None -> stmt_child_from_label label stmt env
        | Some rest ->
            let env = match init with Some s -> exec_simple funcs structs globals env s | None -> env in
            let rec after_body env =
              let env' = match post with Some s -> exec_simple funcs structs globals env s | None -> env in
              loop env'
            and loop env =
              let go = match cond with Some e -> truth_value (eval_value funcs structs globals env e) | None -> true in
              if go then
                match exec_stmt funcs structs globals env body with
                | Continue env' -> after_body env'
                | Continued env' -> after_body env'
                | Broke env' -> Continue env'
                | Jumped (label, env') -> (
                    match local_label_tail label body with
                    | Some rest -> run_from_tail rest env'
                    | None -> Jumped (label, env'))
                | other -> other
              else Continue env
            and run_from_tail rest env =
              match exec_block funcs structs globals rest env with
              | Continue env' -> after_body env'
              | Continued env' -> after_body env'
              | Broke env' -> Continue env'
              | other -> other
            in
            Some (run_from_tail rest env))
    | _ -> stmt_child_from_label label stmt env
  and stmt_child_from_label label stmt env =
    match stmt with
    | Block body -> first_label_run label body env
    | If (_, yes, Some no) -> (
        match stmt_from_label label yes env with Some result -> Some result | None -> stmt_from_label label no env)
    | If (_, yes, None) -> stmt_from_label label yes env
    | Switch (_, cases) ->
        let rec case_bodies cases acc =
          match cases with
          | [] -> List.rev acc
          | SwitchCase (_, body) :: rest -> case_bodies rest (List.rev_append body acc)
        in
        first_label_run label (case_bodies cases []) env
    | Label name ->
        if name = label then Some (Continue env) else None
    | Labeled (name, body) ->
        if name = label then Some (exec_stmt funcs structs globals env body) else stmt_from_label label body env
    | _ -> None
  in
  let rec finish result =
    match result with
    | Jumped (label, env) -> (
        match first_label_run label fn.body env with
        | Some result -> finish result
        | None -> (
            match flat_label_index label with
            | Some i -> finish (run_flat_at i env)
            | None -> fail ("unresolved goto in " ^ name ^ ": " ^ label)))
    | other -> other
  in
  let maybe_error1_longjmp () =
    if name = "error1" then
      match args with
      | VInt mode :: _ ->
        if mode = 2 then
          (match find_binding_opt "tcc_state" env with
          | Some state_binding -> (
              match struct_binding_from_pointer !(state_binding.bind_value) with
              | Some state ->
                  if truth_value (!(field_cell (binding_fields state) "error_set_jmp_enabled")) then raise (Longjmp 1)
              | None -> ())
          | None -> ())
      | _ -> ()
  in
  let result = finish (exec_block funcs structs globals fn.body env) in
  maybe_error1_longjmp ();
  match result with
  | Returned value ->
      let value = coerce_value fn.ret_type value in
      value
  | Continue _ -> VInt 0
  | Jumped (label, _) -> fail ("unresolved goto in " ^ name ^ ": " ^ label)
  | Broke _ -> fail "break outside loop"
  | Continued _ -> fail ("continue outside loop in " ^ name)

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
                | EInt (-1), Some (EString text) -> String.length text + 1
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
      let binding = find_binding name env in
      set_binding_layout structs binding;
      (match init with
      | Some (EInitList values) ->
          let binding = find_binding name env in
          (match binding.bind_array with
          | Some array ->
              let struct_array_fields = struct_fields structs ty in
              let make_struct_element i field_values =
                let fields = ref [] in
                let bytes =
                  match struct_size structs ty with
                  | Some size -> Some (Array.make size (VInt 0))
                  | None -> None
                in
                let element =
                  {
                    bind_name = name ^ "[" ^ string_of_int i ^ "]";
                    bind_type = ty;
                    bind_value = ref (VInt 0);
                    bind_string = None;
                    bind_array = None;
                    bind_bytes = bytes;
                    bind_fields = Some fields;
                    bind_layout = ref (struct_layout_fields structs ty);
                  }
                in
                let rec fill_fields fields values =
                  match (fields, values) with
                  | field :: fields, value_expr :: values ->
                      let cell = field_cell (binding_fields element) field in
                      cell := eval_value funcs structs globals env value_expr;
                      fill_fields fields values
                  | _ -> ()
                in
                fill_fields struct_array_fields field_values;
                VPtr element
              in
              let rec fill i values =
                match values with
                | [] -> ()
                | value_expr :: values ->
                    if i < Array.length array then
                      array.(i) <-
                        (match (value_expr, struct_array_fields) with
                        | EInitList field_values, _ :: _ -> make_struct_element i field_values
                        | _ -> coerce_value binding.bind_type (eval_value funcs structs globals env value_expr));
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
      | Some (EString text) ->
          let binding = find_binding name env in
          (match binding.bind_array with
          | Some array -> fill_string_array array text
          | None -> ());
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
      | Some _, EVar source_name -> (
          let source = find_binding source_name env in
          match source.bind_fields with
          | Some _ ->
              copy_struct_fields target source;
              env
          | None -> assoc_set_value name (eval_value funcs structs globals env expr) env)
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
      let old_value = !(binding.bind_value) in
      let delta = pointer_delta_for_value structs binding.bind_type old_value delta in
      binding.bind_value := coerce_value binding.bind_type (add_to_value old_value delta);
      env

and exec_stmt funcs structs globals env stmt =
  let is_setjmp_call expr =
    match expr with
    | ECall ("setjmp", _) -> true
    | ECallExpr (EVar "setjmp", _) -> true
    | _ -> false
  in
  let is_setjmp_zero_cond expr =
    match expr with
    | EBinary (Eq, call, EInt 0) | EBinary (Eq, EInt 0, call) -> is_setjmp_call call
    | _ -> false
  in
  let local_label_tail label stmt =
    let rec loop stmts =
      match stmts with
      | [] -> None
      | Label name :: rest -> if name = label then Some rest else loop rest
      | _ :: rest -> loop rest
    in
    loop (label_flatten_stmt stmt)
  in
  match stmt with
  | Simple simple -> (
      try Continue (exec_simple funcs structs globals env simple) with Exit_code code -> Returned (VInt code))
  | Return None -> Returned (VInt 0)
  | Return (Some expr) -> Returned (eval_value funcs structs globals env expr)
  | Goto label -> Jumped (label, env)
  | Label _ -> Continue env
  | Labeled (_, stmt) -> exec_stmt funcs structs globals env stmt
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
      if is_setjmp_zero_cond cond then (
        try
          if truth_value (eval_value funcs structs globals env cond) then exec_stmt funcs structs globals env yes
          else (
            match no with Some stmt -> exec_stmt funcs structs globals env stmt | None -> Continue env)
        with Longjmp _ -> (
          match no with Some stmt -> exec_stmt funcs structs globals env stmt | None -> Continue env))
      else if truth_value (eval_value funcs structs globals env cond) then exec_stmt funcs structs globals env yes
      else (
        match no with Some stmt -> exec_stmt funcs structs globals env stmt | None -> Continue env)
  | While (cond, body) ->
      let rec run_body_from_label label env =
        match local_label_tail label body with
        | None -> Jumped (label, env)
        | Some rest -> (
            match exec_block funcs structs globals rest env with
            | Continue env' -> loop env'
            | Continued env' -> loop env'
            | Broke env' -> Continue env'
            | other -> other)
      and loop env =
        if truth_value (eval_value funcs structs globals env cond) then
          match exec_stmt funcs structs globals env body with
          | Continue env' -> loop env'
          | Continued env' -> loop env'
          | Broke env' -> Continue env'
          | Jumped (label, env') -> run_body_from_label label env'
          | other -> other
        else Continue env
      in
      loop env
  | DoWhile (body, cond) ->
      let rec run_body_from_label label env =
        match local_label_tail label body with
        | None -> Jumped (label, env)
        | Some rest -> (
            match exec_block funcs structs globals rest env with
            | Continue env' -> if truth_value (eval_value funcs structs globals env' cond) then loop env' else Continue env'
            | Continued env' -> if truth_value (eval_value funcs structs globals env' cond) then loop env' else Continue env'
            | Broke env' -> Continue env'
            | other -> other)
      and loop env =
        match exec_stmt funcs structs globals env body with
        | Continue env' -> if truth_value (eval_value funcs structs globals env' cond) then loop env' else Continue env'
        | Continued env' -> if truth_value (eval_value funcs structs globals env' cond) then loop env' else Continue env'
        | Broke env' -> Continue env'
        | Jumped (label, env') -> run_body_from_label label env'
        | other -> other
      in
      loop env
  | For (init, cond, post, body) ->
      let env = match init with Some s -> exec_simple funcs structs globals env s | None -> env in
      let rec after_body env =
        let env' = match post with Some s -> exec_simple funcs structs globals env s | None -> env in
        loop env'
      and run_body_from_label label env =
        match local_label_tail label body with
        | None -> Jumped (label, env)
        | Some rest -> (
            match exec_block funcs structs globals rest env with
            | Continue env' -> after_body env'
            | Continued env' -> after_body env'
            | Broke env' -> Continue env'
            | other -> other)
      and loop env =
        let go = match cond with Some e -> truth_value (eval_value funcs structs globals env e) | None -> true in
        if go then
          match exec_stmt funcs structs globals env body with
          | Continue env' -> after_body env'
          | Continued env' -> after_body env'
          | Broke env' -> Continue env'
          | Jumped (label, env') -> run_body_from_label label env'
          | other -> other
        else Continue env
      in
      loop env
  | Switch (value, cases) ->
      let switch_value = eval_expr funcs structs globals env value in
      trace ("switch " ^ expr_summary value ^ "=" ^ string_of_int switch_value);
      let rec append_case_bodies cases acc =
        match cases with
        | [] -> List.rev acc
        | SwitchCase (_, body) :: rest -> append_case_bodies rest (List.rev_append body acc)
      in
      let all_body = append_case_bodies cases [] in
      let rec body_after_label label stmts =
        match stmts with
        | [] -> None
        | Label name :: rest -> if name = label then Some rest else body_after_label label rest
        | Labeled (name, body) :: rest -> if name = label then Some (body :: rest) else body_after_label label rest
        | _ :: rest -> body_after_label label rest
      in
      let rec finish result =
        match result with
        | Broke env -> Continue env
        | Jumped (label, env) -> (
            match body_after_label label all_body with
            | Some rest -> finish (exec_block funcs structs globals rest env)
            | None -> Jumped (label, env))
        | other -> other
      in
      let rec select default cases =
        match cases with
        | [] -> (
            match default with
            | Some cases -> cases
            | None -> [])
        | (SwitchCase (label, _) as current) :: rest -> (
            match label with
            | Some expr ->
                let label_value = eval_expr funcs structs globals env expr in
                trace ("case " ^ expr_summary expr ^ "=" ^ string_of_int label_value);
                if label_value = switch_value then current :: rest else select default rest
            | None -> select (Some (current :: rest)) rest)
      in
      let rec run cases env =
        match cases with
        | [] -> Continue env
        | SwitchCase (_, body) :: rest -> (
            match exec_block funcs structs globals body env with
            | Continue env -> run rest env
            | Broke env -> Continue env
            | Jumped _ as jumped -> finish jumped
            | Continued _ as continued -> continued
            | Returned _ as returned -> returned)
      in
      run (select None cases) env

and flatten_stmt stmt =
  match stmt with
  | If (_, yes, Some no) -> flatten_stmt yes @ flatten_stmt no
  | If (_, yes, None) -> flatten_stmt yes
  | While (_, body) -> flatten_stmt body
  | DoWhile (body, _) -> flatten_stmt body
  | For (_, _, _, body) -> flatten_stmt body
  | Switch (_, cases) ->
      let rec case_bodies cases acc =
        match cases with
        | [] -> List.rev acc
        | SwitchCase (_, body) :: rest -> case_bodies rest (List.rev_append (flatten_stmts body) acc)
      in
      case_bodies cases []
  | Block body -> flatten_stmts body
  | Labeled (name, stmt) -> Label name :: flatten_stmt stmt
  | Simple _ | Return _ | Goto _ | Label _ | Break | ContinueStmt -> [ stmt ]

and flatten_stmts stmts =
  match stmts with
  | [] -> []
  | stmt :: rest -> flatten_stmt stmt @ flatten_stmts rest

and label_flatten_stmt stmt =
  match stmt with
  | Block body -> label_flatten_stmts body
  | Labeled (name, stmt) -> Label name :: label_flatten_stmt stmt
  | If (_, yes, Some no) -> stmt :: (label_flatten_stmt yes @ label_flatten_stmt no)
  | If (_, yes, None) -> stmt :: label_flatten_stmt yes
  | While (_, body) -> stmt :: label_flatten_stmt body
  | DoWhile (body, _) -> stmt :: label_flatten_stmt body
  | For (_, _, _, body) -> stmt :: label_flatten_stmt body
  | Switch (_, cases) ->
      let rec case_labels cases acc =
        match cases with
        | [] -> List.rev acc
        | SwitchCase (_, body) :: rest -> case_labels rest (List.rev_append (label_flatten_stmts body) acc)
      in
      stmt :: case_labels cases []
  | _ -> [ stmt ]

and label_flatten_stmts stmts =
  match stmts with
  | [] -> []
  | stmt :: rest -> label_flatten_stmt stmt @ label_flatten_stmts rest

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
          match label_index label with
          | Some j -> run_at j env'
          | None -> Jumped (label, env'))
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

let main_argv_value args =
  let rec values_of_args args =
    match args with
    | [] -> [ VInt 0 ]
    | arg :: rest -> VStringPtr (arg, 0) :: values_of_args rest
  in
  let values = Array.of_list (values_of_args args) in
  let binding =
    {
      bind_name = "__argv";
      bind_type = TPtr TChar;
      bind_value = ref (VInt 0);
      bind_string = None;
      bind_array = Some values;
      bind_bytes = None;
      bind_fields = None;
      bind_layout = ref None;
    }
  in
  VArrayPtr (binding, 0)

let main_entry_args fn host_args =
  match fn.params with
  | [] -> []
  | [ argc ] ->
      if same_c_type argc.param_type TInt then [ VInt (List.length host_args) ]
      else fail "unsupported main parameters"
  | [ argc; argv ] ->
      if same_c_type argc.param_type TInt && is_main_argv_type argv.param_type then
        if host_args = [] then [ VInt 0; VInt 0 ]
        else [ VInt (List.length host_args); main_argv_value host_args ]
      else fail "unsupported main parameters"
  | _ -> fail "unsupported main parameters"

let compile_with_args host_args src =
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
        { bind_name = name; bind_type = TInt; bind_value = ref (VInt value); bind_string = None; bind_array = None; bind_bytes = None; bind_fields = None; bind_layout = ref None })
      program.constants
  in
	  let globals =
	    trace "globals";
	    List.fold_left
	      (fun env global ->
	        trace ("global " ^ global.global_name);
	        exec_simple program.funcs program.structs env env (SDecl (global.global_type, global.global_name, global.global_init, global.global_array_size)))
	      constants program.globals
	  in
  let main =
    match list_find_opt (fun fn -> fn.name = "main") program.funcs with
    | Some fn -> fn
    | None -> fail "missing main"
  in
  trace "eval main";
  let exit_code =
    try int_of_value (eval_func program.funcs program.structs globals "main" (main_entry_args main host_args)) with
    | Fatal_exit code -> code
  in
  m1_of_exit exit_code

let compile src =
  compile_with_args [] src

let read_stdin () =
  host_read_stdin ()

type driver_config = {
  driver_input : string option;
  driver_output : string option;
  driver_host_args : string list;
}

let empty_driver_config =
  { driver_input = None; driver_output = None; driver_host_args = [] }

let set_driver_input config path =
  match config.driver_input with
  | None -> { config with driver_input = Some path }
  | Some _ -> fail ("multiple input files: " ^ path)

let driver_config_from_argv () =
  let host_args =
    let rec gather i acc =
      if i >= host_arg_count () then List.rev acc
      else if host_arg_at i = "--host-arg" then
        if i + 1 >= host_arg_count () then fail "--host-arg requires a value"
        else gather (i + 2) (host_arg_at (i + 1) :: acc)
      else gather (i + 1) acc
    in
    gather 1 []
  in
  let rec parse i config =
    if i >= host_arg_count () then { config with driver_host_args = host_args }
    else
      let arg = host_arg_at i in
      if arg = "--trace" then (
        trace_requested := true;
        parse (i + 1) config)
      else if arg = "--emit-m1" then parse (i + 1) config
      else if arg = "-c" then parse (i + 1) config
      else if arg = "-S" then parse (i + 1) config
      else if arg = "--host-arg" then
        if i + 1 >= host_arg_count () then fail "--host-arg requires a value"
        else parse (i + 2) config
      else if arg = "-o" then
        if i + 1 >= host_arg_count () then fail "-o requires an output file"
        else parse (i + 2) { config with driver_output = Some (host_arg_at (i + 1)) }
      else if String.length arg > 0 && arg.[0] = '-' then
        fail ("unknown option: " ^ arg)
      else
        parse (i + 1) (set_driver_input config arg)
  in
  parse 1 empty_driver_config

let read_driver_input config =
  match config.driver_input with
  | Some path -> host_read_text_file path
  | None -> read_stdin ()

let write_driver_output config text =
  match config.driver_output with
  | Some path -> host_write_file path text
  | None -> host_stdout text

let () =
  try
    let config = driver_config_from_argv () in
    let src = read_driver_input config in
    write_driver_output config (compile_with_args config.driver_host_args src)
  with
  | Parse_error msg ->
      host_stderr_line ("ccc-host-ocaml: parse error: " ^ msg);
      host_exit 1
  | Compile_error msg ->
      host_stderr_line ("ccc-host-ocaml: compile error: " ^ msg);
      host_exit 1
