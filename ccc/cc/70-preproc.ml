(* ccc part 70: token-level preprocessor; port of Hcc.IfFrame and
   Hcc.Preprocessor. PreprocessError is fatal here: the hcpp driver
   prefixes "INPUT:" and dies, so pp_die prints
   "<input>:<line>:<col>: <msg>" to stderr and exits 1 directly
   (pp_input is set by the driver before preprocess runs). *)

let pp_input = ref (bytes_create 0)

let pp_die line col msg =
  let b = buf_new 64 in
  buf_add_bytes b !pp_input;
  buf_push b 58;
  buf_add_int b line;
  buf_push b 58;
  buf_add_int b col;
  buf_add_str b ": ";
  buf_add_bytes b msg;
  die_bytes (buf_take b)

let pp_die_str line col s = pp_die line col (str_to_bytes s)

(* quoted rendering like Haskell's show; private copy of 30-parser's
   show_quoted (the parser part is not in the ccpp concatenation) *)
let pp_show_quoted b =
  let out = buf_new (bytes_length b + 2) in
  buf_push out 34;
  let n = bytes_length b in
  let rec go i =
    if i < n then
      (let c = bytes_get b i in
       (if c = 34 || c = 92 then buf_push out 92);
       buf_push out c;
       go (i + 1)) in
  go 0;
  buf_push out 34;
  buf_take out

(* ---- IfFrame: parent, taken, active ---- *)

type ifframe = IfFrame of bool * bool * bool

let if_stack_active frames =
  match frames with
  | [] -> true
  | IfFrame (_, _, active) :: _ -> active

let push_if_frame frames cond =
  let parent = if_stack_active frames in
  let active = parent && cond in
  IfFrame (parent, active, active) :: frames

let replace_elif_frame frames cond =
  match frames with
  | [] -> None
  | IfFrame (parent, taken, _) :: rest ->
      let active = parent && not taken && cond in
      Some (IfFrame (parent, taken || active, active) :: rest)

let replace_else_frame frames =
  match frames with
  | [] -> None
  | IfFrame (parent, taken, _) :: rest ->
      Some (IfFrame (parent, true, parent && not taken) :: rest)

let pop_if_frame frames =
  match frames with
  | [] -> None
  | _ :: rest -> Some rest

(* ---- byte-string helpers over TextUtil ---- *)

let pp_drop_spaces b =
  let n = bytes_length b in
  let rec go i = if i < n && cc_is_space (bytes_get b i) then go (i + 1) else i in
  let s = go 0 in
  bytes_sub b s (n - s)

let pp_trim b =
  let n = bytes_length b in
  let rec fwd i = if i < n && cc_is_space (bytes_get b i) then fwd (i + 1) else i in
  let s = fwd 0 in
  let rec back i = if i > s && cc_is_space (bytes_get b (i - 1)) then back (i - 1) else i in
  let e = back n in
  bytes_sub b s (e - s)

(* (prefix of ident chars, rest) like span isIdentChar *)
let pp_span_ident b =
  let n = bytes_length b in
  let rec go i = if i < n && cc_is_ident_char (bytes_get b i) then go (i + 1) else i in
  let k = go 0 in
  (bytes_sub b 0 k, bytes_sub b k (n - k))

let pp_take_while_ident b =
  let n = bytes_length b in
  let rec go i = if i < n && cc_is_ident_char (bytes_get b i) then go (i + 1) else i in
  bytes_sub b 0 (go 0)

let pp_all_digits b =
  let n = bytes_length b in
  let rec go i = if i >= n then true else if cc_is_digit (bytes_get b i) then go (i + 1) else false in
  go 0

let pp_all_ident_chars b =
  let n = bytes_length b in
  let rec go i = if i >= n then true else if cc_is_ident_char (bytes_get b i) then go (i + 1) else false in
  go 0

let pp_ends_with_dots b =
  let n = bytes_length b in
  n >= 3 && bytes_get b (n - 1) = 46 && bytes_get b (n - 2) = 46 &&
  bytes_get b (n - 3) = 46

let rec pp_name_elem name names =
  match names with
  | [] -> false
  | n :: rest -> if bytes_eq n name then true else pp_name_elem name rest

let rec pp_take_n n l =
  if n <= 0 then []
  else
    (match l with
     | [] -> []
     | x :: rest -> x :: pp_take_n (n - 1) rest)

let rec pp_drop_n n l =
  if n <= 0 then l
  else
    (match l with
     | [] -> []
     | _ :: rest -> pp_drop_n (n - 1) rest)

(* Preprocessor.stripLineComment: cut at "//" with no literal awareness *)
let pp_strip_line_comment b =
  let n = bytes_length b in
  let out = buf_new n in
  let rec go i =
    if i < n then
      (let c = bytes_get b i in
       if c = 47 && i + 1 < n && bytes_get b (i + 1) = 47 then ()
       else (buf_push out c; go (i + 1))) in
  go 0;
  buf_take out

(* ---- types ---- *)

type macro =
  | ObjectMacro of bytes * token list
  | FunctionMacro of bytes * bytes list * bytes option * token list

(* raw tokens, expanded tokens *)
type macroarg = MacroArg of token list * token list

type chunk = Chunk of bytes list * token list

type boundargs = BoundMacroArgs of macroarg symtree * macroarg list

type directive = Directive of bytes * bytes

(* ---- token source: chunks with hidden macro names ---- *)

let pp_source_from_tokens toks =
  match toks with
  | [] -> []
  | _ -> [Chunk ([], toks)]

let pp_prepend_chunk hidden toks source =
  match toks with
  | [] -> source
  | _ -> Chunk (hidden, toks) :: source

let rec pp_pop_source source =
  match source with
  | [] -> None
  | Chunk (_, []) :: rest -> pp_pop_source rest
  | Chunk (hidden, tok :: toks) :: rest ->
      Some (hidden, tok, pp_prepend_chunk hidden toks rest)

let rec pp_drop_inactive_token toks =
  match toks with
  | [] -> []
  | Chunk (_, []) :: xs -> pp_drop_inactive_token xs
  | Chunk (hidden, _ :: xs) :: rest -> pp_prepend_chunk hidden xs rest

(* ---- directive text parsing ---- *)

let pp_parse_directive text =
  let t = pp_drop_spaces text in
  if bytes_length t > 0 && bytes_get t 0 = 35 then
    (let rest = pp_drop_spaces (bytes_sub t 1 (bytes_length t - 1)) in
     let n = bytes_length rest in
     let rec go i = if i < n && cc_is_ident_char (bytes_get rest i) then go (i + 1) else i in
     let k = go 0 in
     Directive (bytes_sub rest 0 k, pp_drop_spaces (bytes_sub rest k (n - k))))
  else Directive (bytes_create 0, bytes_create 0)

let pp_directive_name text =
  let t = pp_drop_spaces text in
  if bytes_length t > 0 && cc_is_ident_start (bytes_get t 0) then
    Some (pp_take_while_ident text)
  else None

(* ---- macro definition parsing ---- *)

(* lex a replacement list behind a dummy token so '#' is never
   beginning-of-line; positions are synthetic like the reference *)
let pp_lex_replacement text =
  let b = buf_new (bytes_length text + 20) in
  buf_add_str b "__hcc_macro_dummy ";
  buf_add_bytes b (pp_drop_spaces text);
  match lex_c (buf_take b) with
  | [] -> []
  | _ :: toks -> toks

let pp_take_macro_params line col text =
  let n = bytes_length text in
  let b = buf_new n in
  let rec go depth i =
    if i >= n then pp_die_str line col "unterminated macro parameter list"
    else
      (let c = bytes_get text i in
       if c = 41 && depth = 1 then (buf_take b, bytes_sub text (i + 1) (n - i - 1))
       else if c = 41 then (buf_push b c; go (depth - 1) (i + 1))
       else if c = 40 then (buf_push b c; go (depth + 1) (i + 1))
       else (buf_push b c; go depth (i + 1))) in
  go 1 0

let pp_split_commas text =
  let n = bytes_length text in
  let cur = buf_new 16 in
  let rec go depth i acc =
    if i >= n then list_rev (buf_take cur :: acc)
    else
      (let c = bytes_get text i in
       if c = 44 && depth = 0 then
         (let piece = buf_take cur in
          buf_clear cur;
          go depth (i + 1) (piece :: acc))
       else if c = 40 then (buf_push cur c; go (depth + 1) (i + 1) acc)
       else if c = 41 then (buf_push cur c; go (imax 0 (depth - 1)) (i + 1) acc)
       else (buf_push cur c; go depth (i + 1) acc)) in
  go 0 0 []

let rec pp_trim_non_empty pieces =
  match pieces with
  | [] -> []
  | piece :: rest ->
      let trimmed = pp_trim piece in
      if bytes_length trimmed = 0 then pp_trim_non_empty rest
      else trimmed :: pp_trim_non_empty rest

let pp_parse_macro_params line col text =
  let pieces = pp_trim_non_empty (pp_split_commas text) in
  let rec parse_pieces params variadic rest =
    match rest with
    | [] -> (list_rev params, variadic)
    | piece :: more ->
        if bytes_eq_str piece "..." then
          parse_pieces params (Some (str_to_bytes "__VA_ARGS__")) more
        else if pp_ends_with_dots piece then
          (let name = pp_trim (bytes_sub piece 0 (bytes_length piece - 3)) in
           if pp_all_ident_chars name && bytes_length name > 0 then
             parse_pieces params (Some name) more
           else
             (let b = buf_new 48 in
              buf_add_str b "bad variadic macro parameter: ";
              buf_add_bytes b piece;
              pp_die line col (buf_take b)))
        else if pp_all_ident_chars piece && bytes_length piece > 0 then
          parse_pieces (piece :: params) variadic more
        else
          (let b = buf_new 48 in
           buf_add_str b "bad macro parameter: ";
           buf_add_bytes b piece;
           pp_die line col (buf_take b)) in
  parse_pieces [] None pieces

let pp_parse_function_macro line col name text =
  let (param_text, body_text) = pp_take_macro_params line col text in
  let (params, variadic) = pp_parse_macro_params line col param_text in
  FunctionMacro (name, params, variadic, pp_lex_replacement body_text)

let pp_parse_macro_definition line col text =
  let t = pp_drop_spaces text in
  if bytes_length t > 0 && cc_is_ident_start (bytes_get t 0) then
    (let (name, after_name) = pp_span_ident t in
     if bytes_length after_name > 0 && bytes_get after_name 0 = 40 then
       pp_parse_function_macro line col name
         (bytes_sub after_name 1 (bytes_length after_name - 1))
     else ObjectMacro (name, pp_lex_replacement after_name))
  else pp_die_str line col "#define without macro name"

let pp_macro_name macro =
  match macro with
  | ObjectMacro (name, _) -> name
  | FunctionMacro (name, _, _, _) -> name

(* ---- token helpers ---- *)

let pp_same_token_kind a b =
  match (a, b) with
  | (TkIdent x, TkIdent y) -> bytes_eq x y
  | (TkInt x, TkInt y) -> bytes_eq x y
  | (TkFloat x, TkFloat y) -> bytes_eq x y
  | (TkChar x, TkChar y) -> bytes_eq x y
  | (TkString x, TkString y) -> bytes_eq x y
  | (TkPunct x, TkPunct y) -> bytes_eq x y
  | (TkDirective x, TkDirective y) -> bytes_eq x y
  | _ -> false

let pp_same_token left right =
  match (left, right) with
  | (Tok (_, _, lk), Tok (_, _, rk)) -> pp_same_token_kind lk rk

let pp_same_single_token toks original =
  match toks with
  | [tok] -> pp_same_token tok original
  | _ -> false

let rec pp_relocate line col toks =
  match toks with
  | [] -> []
  | Tok (_, _, kind) :: rest -> Tok (line, col, kind) :: pp_relocate line col rest

let pp_take_defined_operand_source toks =
  match pp_pop_source toks with
  | None -> ([], toks)
  | Some (_, t1, after1) ->
      (match t1 with
       | Tok (_, _, TkPunct p1) ->
           if bytes_eq_str p1 "(" then
             (match pp_pop_source after1 with
              | Some (_, t2, after2) ->
                  (match t2 with
                   | Tok (_, _, TkIdent _) ->
                       (match pp_pop_source after2 with
                        | Some (_, t3, after3) ->
                            (match t3 with
                             | Tok (_, _, TkPunct p3) ->
                                 if bytes_eq_str p3 ")" then ([t1; t2; t3], after3)
                                 else ([], toks)
                             | _ -> ([], toks))
                        | None -> ([], toks))
                   | _ -> ([], toks))
              | None -> ([], toks))
           else ([], toks)
       | Tok (_, _, TkIdent _) -> ([t1], after1)
       | _ -> ([], toks))

let rec pp_argument_macro_names macros toks =
  match toks with
  | [] -> []
  | Tok (_, _, TkIdent name) :: rest ->
      if sym_member name macros then name :: pp_argument_macro_names macros rest
      else pp_argument_macro_names macros rest
  | _ :: rest -> pp_argument_macro_names macros rest

let rec pp_macro_arg_hidden_names macros args =
  match args with
  | [] -> []
  | MacroArg (raw, _) :: rest ->
      list_append (pp_argument_macro_names macros raw)
        (pp_macro_arg_hidden_names macros rest)

let pp_comma_token line col = Tok (line, col, TkPunct (str_to_bytes ","))

let pp_join_variadic_args line col args =
  match args with
  | [] -> []
  | first :: rest ->
      let rec with_commas more =
        match more with
        | [] -> []
        | a :: r -> pp_comma_token line col :: list_append a (with_commas r) in
      list_append first (with_commas rest)

let pp_insert_bound_arg name arg bound =
  match bound with
  | BoundMacroArgs (arg_map, arg_list) ->
      BoundMacroArgs (sym_insert name arg arg_map, arg :: arg_list)

let pp_stringify_tokens toks =
  let out = buf_new 32 in
  buf_push out 34;
  let add_escaped text =
    let n = bytes_length text in
    let rec go i =
      if i < n then
        (let c = bytes_get text i in
         (if c = 92 || c = 34 then buf_push out 92);
         buf_push out c;
         go (i + 1)) in
    go 0 in
  let rec render ts first =
    match ts with
    | [] -> ()
    | t :: rest ->
        ((if not first then buf_push out 32);
         add_escaped (token_text (tok_kind t));
         render rest false) in
  render toks true;
  buf_push out 34;
  buf_take out

let pp_paste_tokens line col left right =
  let b = buf_new 16 in
  buf_add_bytes b (token_text (tok_kind left));
  buf_add_bytes b (token_text (tok_kind right));
  match lex_c (buf_take b) with
  | [Tok (_, _, kind)] -> Tok (line, col, kind)
  | _ -> pp_die_str line col "token paste did not form one token"

let pp_next_paste_operand args xs =
  match xs with
  | [] -> ([], [])
  | tok :: rest ->
      (match tok with
       | Tok (_, _, TkIdent name) ->
           (match sym_lookup name args with
            | Some (MacroArg (raw, _)) -> (raw, rest)
            | None -> ([tok], rest))
       | _ -> ([tok], rest))

let rec pp_replace_defined_operators macros toks =
  match toks with
  | [] -> []
  | tok :: xs ->
      (match tok with
       | Tok (line, col, TkIdent name) ->
           if bytes_eq_str name "defined" then
             (let defined_token nm =
                Tok (line, col,
                     TkInt (str_to_bytes (if sym_member nm macros then "1" else "0"))) in
              match xs with
              | Tok (_, _, TkPunct p1) :: rest1 ->
                  if bytes_eq_str p1 "(" then
                    (match rest1 with
                     | Tok (_, _, TkIdent nm) :: Tok (_, _, TkPunct p2) :: rest2 ->
                         if bytes_eq_str p2 ")" then
                           defined_token nm :: pp_replace_defined_operators macros rest2
                         else pp_die_str line col "bad defined operator in #if expression"
                     | _ -> pp_die_str line col "bad defined operator in #if expression")
                  else pp_die_str line col "bad defined operator in #if expression"
              | Tok (_, _, TkIdent nm) :: rest1 ->
                  defined_token nm :: pp_replace_defined_operators macros rest1
              | _ -> pp_die_str line col "bad defined operator in #if expression")
           else tok :: pp_replace_defined_operators macros xs
       | _ -> tok :: pp_replace_defined_operators macros xs)

(* ---- the expansion / directive engine ---- *)

let rec pp_preprocess_go macros frames rest acc =
  match pp_pop_source rest with
  | None ->
      (match frames with
       | [] -> list_rev acc
       | _ -> pp_die_str 1 1 "unterminated conditional directive")
  | Some (_, Tok (line, col, TkDirective text), xs) ->
      pp_handle_directive macros frames line col text xs acc
  | Some _ ->
      if if_stack_active frames then
        (let (expanded, rest2) = pp_expand_next_source macros false [] rest in
         pp_preprocess_go macros frames rest2 (list_rev_append expanded acc))
      else pp_preprocess_go macros frames (pp_drop_inactive_token rest) acc

and pp_handle_directive macros frames line col text xs acc =
  let (name, rest) =
    match pp_parse_directive text with Directive (n, r) -> (n, r) in
  if bytes_eq_str name "define" then
    (if if_stack_active frames then
       (let macro = pp_parse_macro_definition line col rest in
        pp_preprocess_go (sym_insert (pp_macro_name macro) macro macros) frames xs acc)
     else pp_preprocess_go macros frames xs acc)
  else if bytes_eq_str name "undef" then
    (if if_stack_active frames then
       (match pp_directive_name rest with
        | Some nm -> pp_preprocess_go (sym_delete nm macros) frames xs acc
        | None -> pp_die_str line col "#undef without macro name")
     else pp_preprocess_go macros frames xs acc)
  else if bytes_eq_str name "include" then
    pp_preprocess_go macros frames xs acc
  else if bytes_eq_str name "ifdef" then
    (match pp_directive_name rest with
     | Some nm ->
         pp_preprocess_go macros (push_if_frame frames (sym_member nm macros)) xs acc
     | None -> pp_die_str line col "#ifdef without macro name")
  else if bytes_eq_str name "ifndef" then
    (match pp_directive_name rest with
     | Some nm ->
         pp_preprocess_go macros
           (push_if_frame frames (not (sym_member nm macros))) xs acc
     | None -> pp_die_str line col "#ifndef without macro name")
  else if bytes_eq_str name "if" then
    (let cond = pp_eval_if macros rest in
     pp_preprocess_go macros (push_if_frame frames cond) xs acc)
  else if bytes_eq_str name "elif" then
    (let cond = pp_eval_if macros rest in
     match replace_elif_frame frames cond with
     | Some frames2 -> pp_preprocess_go macros frames2 xs acc
     | None -> pp_die_str line col "#elif without #if")
  else if bytes_eq_str name "else" then
    (match replace_else_frame frames with
     | Some frames2 -> pp_preprocess_go macros frames2 xs acc
     | None -> pp_die_str line col "#else without #if")
  else if bytes_eq_str name "endif" then
    (match pop_if_frame frames with
     | Some frames2 -> pp_preprocess_go macros frames2 xs acc
     | None -> pp_die_str line col "#endif without #if")
  else if bytes_length name = 0 then
    pp_preprocess_go macros frames xs acc
  else if bytes_eq_str name "line" || bytes_eq_str name "pragma" then
    pp_preprocess_go macros frames xs acc
  else if pp_all_digits name then
    pp_preprocess_go macros frames xs acc
  else if if_stack_active frames then
    (let b = buf_new 48 in
     buf_add_str b "unsupported directive: #";
     buf_add_bytes b name;
     pp_die line col (buf_take b))
  else pp_preprocess_go macros frames xs acc

and pp_eval_if macros text =
  let toks = lex_c (pp_strip_line_comment text) in
  let replaced = pp_replace_defined_operators macros toks in
  let expanded = pp_expand_tokens macros false [] replaced in
  match parse_const_expr [] expanded with
  | Some (value, []) -> value <> 0
  | Some (_, tok :: _) ->
      (match tok with
       | Tok (tl, tc, kind) ->
           let b = buf_new 64 in
           buf_add_str b "trailing tokens in #if expression near ";
           buf_add_bytes b (pp_show_quoted (token_text kind));
           pp_die tl tc (buf_take b))
  | None -> pp_die 1 1 !ce_err

and pp_expand_next_source macros protect_defined disabled toks =
  match pp_pop_source toks with
  | None -> ([], [])
  | Some (hidden, tok, xs) ->
      (match tok with
       | Tok (line, col, TkIdent name) ->
           if protect_defined && bytes_eq_str name "defined" then
             (let (protected_toks, rest) = pp_take_defined_operand_source xs in
              (tok :: protected_toks, rest))
           else if pp_name_elem name hidden || pp_name_elem name disabled then
             ([tok], xs)
           else
             (match sym_lookup name macros with
              | None -> ([tok], xs)
              | Some macro ->
                  pp_expand_macro macros protect_defined
                    (list_append hidden disabled) tok line col name macro xs)
       | _ -> ([tok], xs))

and pp_expand_tokens_go macros protect_defined disabled rest acc =
  match rest with
  | [] -> list_rev acc
  | _ ->
      let (expanded, rest2) =
        pp_expand_next_source macros protect_defined disabled rest in
      pp_expand_tokens_go macros protect_defined disabled rest2
        (list_rev_append expanded acc)

and pp_expand_tokens macros protect_defined disabled toks =
  pp_expand_tokens_go macros protect_defined disabled
    (pp_source_from_tokens toks) []

and pp_expand_macro macros protect_defined disabled original line col name macro rest =
  match macro with
  | ObjectMacro (_, body) ->
      let replacement = pp_relocate line col body in
      if pp_same_single_token replacement original then ([original], rest)
      else ([], pp_prepend_chunk [name] replacement rest)
  | FunctionMacro (_, params, variadic, body) ->
      (match pp_pop_source rest with
       | Some (_, Tok (_, _, TkPunct p), after_open) ->
           if bytes_eq_str p "(" then
             (let (args, rest2) = pp_collect_invocation_args line col after_open in
              let expanded =
                pp_expand_function_macro macros protect_defined disabled line col
                  name params variadic body args in
              (expanded, rest2))
           else ([original], rest)
       | _ -> ([original], rest))

and pp_collect_invocation_args line col toks =
  pp_collect_args_go line col 1 [] [] toks

and pp_collect_args_go line col depth current args rest =
  match pp_pop_source rest with
  | None -> pp_die_str line col "unterminated macro invocation"
  | Some (_, tok, xs) ->
      (match tok with
       | Tok (_, _, TkPunct p) ->
           if bytes_eq_str p ")" && depth = 1 then
             (let final_args =
                match (args, current) with
                | ([], []) -> []
                | _ -> list_rev (list_rev current :: args) in
              (final_args, xs))
           else if bytes_eq_str p ")" then
             pp_collect_args_go line col (depth - 1) (tok :: current) args xs
           else if bytes_eq_str p "(" then
             pp_collect_args_go line col (depth + 1) (tok :: current) args xs
           else if bytes_eq_str p "," && depth = 1 then
             pp_collect_args_go line col depth [] (list_rev current :: args) xs
           else pp_collect_args_go line col depth (tok :: current) args xs
       | _ -> pp_collect_args_go line col depth (tok :: current) args xs)

and pp_expand_function_macro macros protect_defined disabled line col name params variadic body args =
  let bound =
    pp_bind_macro_args macros protect_defined disabled line col params variadic args in
  match bound with
  | BoundMacroArgs (arg_map, arg_list) ->
      let replaced = pp_substitute_macro_body line col arg_map body in
      let arg_hidden = pp_macro_arg_hidden_names macros arg_list in
      pp_expand_tokens macros protect_defined
        (name :: list_append arg_hidden disabled) replaced

and pp_bind_macro_args macros protect_defined disabled line col params variadic args =
  let fixed_count = list_length params in
  let nargs = list_length args in
  let variadic_missing = match variadic with None -> true | Some _ -> false in
  if nargs < fixed_count || (variadic_missing && nargs <> fixed_count) then
    pp_die_str line col "wrong number of macro arguments"
  else
    (let fixed =
       pp_bind_fixed macros protect_defined disabled line col SymE [] params
         (pp_take_n fixed_count args) in
     match variadic with
     | None -> fixed
     | Some vname ->
         let rest_args = pp_drop_n fixed_count args in
         let arg =
           pp_make_arg macros protect_defined disabled
             (pp_join_variadic_args line col rest_args) in
         pp_insert_bound_arg vname arg fixed)

and pp_bind_fixed macros protect_defined disabled line col arg_map arg_list ps args =
  match (ps, args) with
  | ([], []) -> BoundMacroArgs (arg_map, list_rev arg_list)
  | (p :: ps2, a :: as2) ->
      (let arg = pp_make_arg macros protect_defined disabled a in
       match pp_insert_bound_arg p arg (BoundMacroArgs (arg_map, arg_list)) with
       | BoundMacroArgs (m2, l2) ->
           pp_bind_fixed macros protect_defined disabled line col m2 l2 ps2 as2)
  | _ -> pp_die_str line col "wrong number of macro arguments"

and pp_make_arg macros protect_defined disabled raw =
  MacroArg (raw, pp_expand_tokens macros protect_defined disabled raw)

and pp_substitute_macro_body line col args body =
  pp_subst_go line col args body []

and pp_subst_go line col args rest acc =
  match rest with
  | [] -> list_rev acc
  | tok :: xs ->
      (match tok with
       | Tok (pl, pc, TkPunct p) ->
           if bytes_eq_str p "#" then
             (let stringized =
                match xs with
                | Tok (al, ac, TkIdent name) :: xs2 ->
                    (match sym_lookup name args with
                     | Some (MacroArg (raw, _)) ->
                         Some (Tok (al, ac, TkString (pp_stringify_tokens raw)), xs2)
                     | None -> None)
                | _ -> None in
              match stringized with
              | Some (stok, xs2) -> pp_subst_go line col args xs2 (stok :: acc)
              | None -> pp_subst_go line col args xs (tok :: acc))
           else if bytes_eq_str p "##" then
             (match acc with
              | [] -> pp_paste_with_previous line col args pl pc [] xs acc
              | previous :: before ->
                  pp_paste_with_previous line col args pl pc [previous] xs before)
           else pp_subst_go line col args xs (tok :: acc)
       | Tok (_, _, TkIdent name) ->
           (match sym_lookup name args with
            | Some (MacroArg (_, expanded)) ->
                pp_subst_go line col args xs (list_rev_append expanded acc)
            | None -> pp_subst_go line col args xs (tok :: acc))
       | _ -> pp_subst_go line col args xs (tok :: acc))

and pp_paste_with_previous line col args paste_line paste_col previous xs before =
  let (next, rest2) = pp_next_paste_operand args xs in
  match previous with
  | [ptok] ->
      (let prev_is_comma =
         match ptok with
         | Tok (_, _, TkPunct pc) -> bytes_eq_str pc ","
         | _ -> false in
       if prev_is_comma then
         (match next with
          | [] -> pp_subst_go line col args rest2 before
          | _ -> pp_subst_go line col args rest2 (list_rev_append next (ptok :: before)))
       else
         (match next with
          | [] -> pp_subst_go line col args rest2 (list_rev_append previous before)
          | n :: ns ->
              let pasted = pp_paste_tokens paste_line paste_col ptok n in
              pp_subst_go line col args rest2 (list_rev_append ns (pasted :: before))))
  | [] ->
      (match next with
       | [] -> pp_subst_go line col args rest2 before
       | _ -> pp_subst_go line col args rest2 (list_rev_append next before))
  | _ ->
      (match next with
       | [] -> pp_subst_go line col args rest2 (list_rev_append previous before)
       | _ -> pp_die_str line col "invalid token paste")

let preprocess toks = pp_preprocess_go SymE [] (pp_source_from_tokens toks) []
