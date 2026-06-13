(* ccc part 30: C parser; port of Hcc.Parser.
   The ParseLite monad is explicit: every parser returns 'a presult
   (POk v / PFail) and steps are sequenced with pbind, which is the
   direct spelling of the reference's >>= chain. Repetition and choice
   come from a small combinator kit (p_many / p_optional / p_alt /
   p_try_or / p_until_punct / p_parens) with Parsec's consumption rule:
   failure without consumption backtracks, failure after consumption
   propagates. Cursor and environment (token array, typedef scope map,
   enum constants) remain global mutable state; the error
   position/message refs record the FIRST failure since the last
   backtrack, exactly like the old p_failed flag did. *)

type 'a presult = POk of 'a | PFail

(* ---- state ---- *)

let p_dummy_bytes = bytes_create 0
let p_dummy_tok = Tok (1, 1, TkPunct p_dummy_bytes)

let p_toks = ref (array_make 1 p_dummy_tok)
let p_ntoks = ref 0
let p_pos = ref 0

let p_types = ref scope_empty
let p_consts = ref []
let p_constmap = ref SymE

let p_failed = ref false
let p_eline = ref 1
let p_ecol = ref 1
let p_emsg = ref p_dummy_bytes

(* quoted rendering of a string, like Haskell's show *)
let show_quoted b =
  let out = buf_new (bytes_length b + 2) in
  buf_push out ch_dquote;
  let n = bytes_length b in
  iter_range 0 n
    (fun i ->
      (let c = bytes_get b i in
       (if c = ch_dquote || c = ch_bslash then buf_push out ch_bslash);
       buf_push out c));
  buf_push out ch_dquote;
  buf_take out

(* error recording: first failure since the last backtrack wins *)
let p_record_fail tok msg =
  if !p_failed then ()
  else
    (let (line, col, kind) = (match tok with Tok (l, c, k) -> (l, c, k)) in
     p_failed := true;
     p_eline := line;
     p_ecol := col;
     let b = buf_new 64 in
     buf_add_bytes b msg;
     buf_add_str b " near ";
     buf_add_bytes b (show_quoted (token_text kind));
     p_emsg := buf_take b)

let p_record_eof () =
  if !p_failed then ()
  else
    (p_failed := true;
     p_eline := 1;
     p_ecol := 1;
     p_emsg := str_to_bytes "unexpected end of input")

let p_fail_tok tok msg = (p_record_fail tok msg; PFail)

let p_fail_tok_str tok msg = (p_record_fail tok (str_to_bytes msg); PFail)

let p_fail_eof () = (p_record_eof (); PFail)

(* fail at the current token (eof message when input is exhausted) *)
let p_fail_here msg =
  if !p_pos < !p_ntoks then p_fail_tok (array_get !p_toks !p_pos) msg
  else p_fail_eof ()

(* ---- cursor primitives ---- *)

let p_peek_maybe () =
  if !p_pos < !p_ntoks then Some (array_get !p_toks !p_pos) else None

let p_peek () =
  if !p_pos < !p_ntoks then POk (array_get !p_toks !p_pos)
  else p_fail_eof ()

(* only called after a successful peek, so it cannot run off the end *)
let p_advance () = p_pos := !p_pos + 1

let eat_punct s =
  if !p_pos < !p_ntoks then
    (match array_get !p_toks !p_pos with
     | Tok (_, _, TkPunct p) ->
         if bytes_eq_str p s then (p_pos := !p_pos + 1; true) else false
     | _ -> false)
  else false

let need_punct s =
  if eat_punct s then POk ()
  else
    (let b = buf_new 32 in
     buf_add_str b "expected ";
     buf_add_bytes b (show_quoted (str_to_bytes s));
     p_fail_here (buf_take b))

let eat_ident s =
  if !p_pos < !p_ntoks then
    (match array_get !p_toks !p_pos with
     | Tok (_, _, TkIdent p) ->
         if bytes_eq_str p s then (p_pos := !p_pos + 1; true) else false
     | _ -> false)
  else false

let optional_ident () =
  if !p_pos < !p_ntoks then
    (match array_get !p_toks !p_pos with
     | Tok (_, _, TkIdent s) -> (p_pos := !p_pos + 1; s)
     | _ -> p_dummy_bytes)
  else p_dummy_bytes

let peek_second_punct s =
  if !p_pos + 1 < !p_ntoks then
    (match array_get !p_toks (!p_pos + 1) with
     | Tok (_, _, TkPunct p) -> bytes_eq_str p s
     | _ -> false)
  else false

(* ---- environment ---- *)

let lookup_parser_type name = scope_lookup name !p_types

let bind_parser_type name ty = p_types := scope_insert name ty !p_types

let lookup_parser_constant name = sym_lookup name !p_constmap

let bind_parser_constant name value =
  p_consts := (name, value) :: !p_consts;
  p_constmap := sym_insert name value !p_constmap

(* snapshot for backtracking: cursor + environment *)
let p_save () = (!p_pos, !p_types, !p_consts, !p_constmap)

let p_restore s =
  let (pos, ty, cs, cm) = s in
  p_pos := pos;
  p_types := ty;
  p_consts := cs;
  p_constmap := cm

let snap_pos s = let (pos, _, _, _) = s in pos

(* ---- the monad ---- *)

let pbind r f =
  match r with
  | POk x -> f x
  | PFail -> PFail

(* tryP p <|> q: always backtrack on failure of p *)
let p_try_or p q =
  let save = p_save () in
  match p () with
  | POk v -> POk v
  | PFail -> (p_restore save; p_failed := false; q ())

(* Parsec <|>: backtrack only when p failed without consuming *)
let p_alt p q =
  let save = p_save () in
  match p () with
  | POk v -> POk v
  | PFail ->
      if !p_pos = snap_pos save then (p_restore save; p_failed := false; q ())
      else PFail

let p_map r f =
  match r with
  | POk v -> POk (f v)
  | PFail -> PFail

(* manyP p: repeat until p fails; failure without consumption ends the
   repetition, failure after consumption propagates *)
let p_many p =
  let rec go () =
    let save = p_save () in
    match p () with
    | POk v -> p_map (go ()) (fun rest -> v :: rest)
    | PFail ->
        if !p_pos = snap_pos save then (p_restore save; p_failed := false; POk [])
        else PFail in
  go ()

(* optionalP p: a missing item is None, consumed-then-failed propagates *)
let p_optional p =
  p_alt (fun () -> p_map (p ()) (fun v -> Some v)) (fun () -> POk None)

(* repeat p until the closing punct, collecting results *)
let p_until_punct close p =
  let rec go () =
    if eat_punct close then POk []
    else
      pbind (p ()) (fun v ->
      pbind (go ()) (fun rest -> POk (v :: rest))) in
  go ()

(* "(" p ")" *)
let p_parens p =
  pbind (need_punct "(") (fun _ ->
  pbind (p ()) (fun v ->
  pbind (need_punct ")") (fun _ -> POk v)))

(* monadic helpers that need only the primitives above *)

let need_ident () =
  pbind (p_peek ()) (fun tok ->
    match tok with
    | Tok (_, _, TkIdent s) -> (p_advance (); POk s)
    | _ -> p_fail_tok_str tok "expected identifier")

let need_ident_value expected =
  pbind (p_peek ()) (fun tok ->
    match tok with
    | Tok (_, _, TkIdent s) ->
        if bytes_eq_str s expected then (p_advance (); POk ())
        else
          (let b = buf_new 32 in
           buf_add_str b "expected ";
           buf_add_bytes b (show_quoted (str_to_bytes expected));
           p_fail_tok tok (buf_take b))
    | _ ->
        (let b = buf_new 32 in
         buf_add_str b "expected ";
         buf_add_bytes b (show_quoted (str_to_bytes expected));
         p_fail_tok tok (buf_take b)))

(* ---- keyword tables ---- *)

let builtin_type_names =
  ["void"; "_Bool"; "int"; "char"; "signed"; "unsigned"; "short"; "long";
   "float"; "double"; "struct"; "union"; "enum"]

let storage_and_qualifiers =
  ["const"; "volatile"; "static"; "extern"; "register"; "inline"; "auto";
   "restrict"; "_Noreturn"; "_Atomic"]

let unsupported_qualifiers =
  ["_Thread_local"; "__thread"; "_Alignas"; "_Generic"]

let compound_assign_ops =
  [("+=", "+"); ("-=", "-"); ("*=", "*"); ("/=", "/"); ("%=", "%");
   ("<<=", "<<"); (">>=", ">>"); ("&=", "&"); ("^=", "^"); ("|=", "|")]

let prefix_unary_ops = ["++"; "--"; "+"; "-"; "!"; "~"; "*"; "&"]

let postfix_start_puncts = ["("; "["; "."; "->"; "++"; "--"]

let simple_base_types =
  [("void", CVoid); ("_Bool", CBool); ("int", CInt); ("char", CChar);
   ("float", CFloat); ("double", CDouble)]

let is_builtin_type_name n = bytes_eq_any n builtin_type_names

let is_storage_or_qualifier n = bytes_eq_any n storage_and_qualifiers

let is_unsupported_qualifier n = bytes_eq_any n unsupported_qualifiers

let starts_type_name n =
  is_builtin_type_name n || is_storage_or_qualifier n || bytes_eq_str n "typedef"

let token_starts_type tok =
  match tok with
  | Tok (_, _, TkIdent name) ->
      if starts_type_name name then true
      else is_some (lookup_parser_type name)
  | _ -> false

(* ---- forward structure: the parser proper ----
   The big mutually recursive group mirrors Hcc.Parser. *)

let rec parse_program_decls () =
  match p_peek_maybe () with
  | None -> POk []
  | Some _ ->
      pbind (top_decl ()) (fun d ->
      pbind (parse_program_decls ()) (fun rest ->
      POk (d :: rest)))

and top_decl () =
  if eat_punct ";" then POk (DTypeDecl [])
  else if eat_ident "_Static_assert" then parse_static_assert ()
  else if eat_ident "typedef" then typedef_decl ()
  else
    (* optionalP (tryP standaloneAggregateDecl) *)
    p_try_or standalone_aggregate_decl top_decl_no_struct

and parse_static_assert () =
  pbind (need_punct "(") (fun _ ->
    let toks = take_static_assert_expr () in
    match parse_const_expr !p_consts toks with
    | Some (value, []) ->
        if value = 0 then p_fail_here (str_to_bytes "_Static_assert failed")
        else
          pbind (skip_static_assert_message ()) (fun _ ->
          pbind (need_punct ")") (fun _ ->
          pbind (need_punct ";") (fun _ ->
          POk (DTypeDecl []))))
    | Some (_, tok :: _) ->
        p_fail_tok_str tok "unexpected tokens in _Static_assert expression"
    | None ->
        (let b = buf_new 64 in
         buf_add_str b "invalid _Static_assert expression: ";
         buf_add_bytes b !ce_err;
         p_fail_here (buf_take b)))

(* collect tokens up to the matching close paren or top-level comma *)
and take_static_assert_expr () =
  let rec go depth acc =
    if !p_pos >= !p_ntoks then list_rev acc   (* Haskell returns [] on eof; harmless *)
    else
      (let tok = array_get !p_toks !p_pos in
       match tok with
       | Tok (_, _, TkPunct p) ->
           if bytes_eq_str p "(" then (p_pos := !p_pos + 1; go (depth + 1) (tok :: acc))
           else if bytes_eq_str p ")" && depth = 0 then list_rev acc
           else if bytes_eq_str p ")" then (p_pos := !p_pos + 1; go (depth - 1) (tok :: acc))
           else if bytes_eq_str p "," && depth = 0 then list_rev acc
           else (p_pos := !p_pos + 1; go depth (tok :: acc))
       | _ -> (p_pos := !p_pos + 1; go depth (tok :: acc))) in
  go 0 []

and skip_static_assert_message () =
  if eat_punct "," then
    pbind (p_peek ()) (fun tok ->
      match tok with
      | Tok (_, _, TkString _) -> (p_advance (); POk ())
      | _ -> p_fail_tok_str tok "expected string literal in _Static_assert")
  else POk ()

and top_decl_no_struct () =
  let is_extern = leading_extern_qualifier () in
  pbind (parse_ctype ()) (fun ty0 ->
    if eat_punct ";" then POk (DTypeDecl [ty0])
    else
      pbind (declarator ty0) (fun ty_name ->
        let (ty, name) = ty_name in
        if eat_punct "(" then
          pbind (parameters ()) (fun params ->
          pbind (skip_attributes ()) (fun _ ->
            if eat_punct ";" then POk (DPrototype (ty, name, params))
            else
              pbind (compound ()) (fun body ->
              POk (DFunction (ty, name, params, body)))))
        else
          pbind (p_optional_initializer ()) (fun init0 ->
          pbind (declaration_items_tail ty0) (fun rest ->
          POk (global_decl is_extern ((ty, name, init0) :: rest))))))

(* optionalP (eatPunct "=" >> initializerExpr): the initializer parser
   runs even without '=', failing without consumption *)
and p_optional_initializer () =
  p_optional
    (fun () ->
      let _eq = eat_punct "=" in
      initializer_expr ())

and global_decl is_extern decls =
  let all_uninit ds =
    list_for_all
      (fun d -> (let (_, _, i) = d in (match i with None -> true | Some _ -> false))) ds in
  if is_extern && all_uninit decls then
    DExternGlobals
      (list_map (fun d -> (let (ty, name, _) = d in (ty, name))) decls)
  else
    (match decls with
     | [(ty, name, init0)] -> DGlobal (ty, name, init0)
     | _ -> DGlobals decls)

and leading_extern_qualifier () =
  let rec go i =
    if i < !p_ntoks then
      (match array_get !p_toks i with
       | Tok (_, _, TkIdent name) ->
           if bytes_eq_str name "extern" then true
           else if is_storage_or_qualifier name then go (i + 1)
           else false
       | _ -> false)
    else false in
  go !p_pos

and typedef_decl () =
  pbind (parse_ctype ()) (fun ty0 ->
  pbind (typedef_item ty0) (fun first ->
  pbind (typedef_items_tail ty0) (fun rest ->
    (list_iter
       (fun it ->
         (let (name, ty) = it in
          if bytes_length name > 0 then bind_parser_type name ty))
       (first :: rest);
     POk (DTypeDecl
       (list_map (fun it -> (let (_, ty) = it in ty)) (first :: rest)))))))

and typedef_item ty0 =
  pbind (declarator ty0) (fun ty_name ->
    let (ty, name) = ty_name in
    pbind (optional_function_suffix ty) (fun ty2 ->
    pbind (skip_attributes ()) (fun _ ->
    POk (name, ty2))))

and typedef_items_tail ty0 =
  p_until_punct ";" (fun () ->
    pbind (need_punct ",") (fun _ -> typedef_item ty0))

and standalone_aggregate_decl () =
  pbind (p_peek ()) (fun tok ->
    pbind
      (match tok with
       | Tok (_, _, TkIdent n) ->
           if bytes_eq_str n "struct" then (p_advance (); POk false)
           else if bytes_eq_str n "union" then (p_advance (); POk true)
           else p_fail_tok_str tok "expected aggregate declaration"
       | _ -> p_fail_tok_str tok "expected aggregate declaration")
      (fun is_union ->
        let tag = optional_ident () in
        pbind (need_punct "{") (fun _ ->
        pbind (aggregate_fields_until_close ()) (fun fields ->
        pbind (need_punct ";") (fun _ ->
        POk (DStructDecl (is_union, tag, fields)))))))

and aggregate_fields_until_close () =
  p_map (p_until_punct "}" field_decl)
    (fun fss -> list_concat_map (fun fs -> fs) fss)

and field_decl () =
  pbind (parse_ctype ()) (fun ty0 ->
  pbind (field_declarator ty0) (fun first ->
  pbind (p_many_comma_field ty0) (fun rest ->
  pbind (need_punct ";") (fun _ ->
  POk (first :: rest)))))

(* manyP (needPunct "," >> fieldDeclarator ty0) *)
and p_many_comma_field ty0 =
  p_many (fun () ->
    pbind (need_punct ",") (fun _ -> field_declarator ty0))

and field_declarator ty0 =
  if eat_punct "(" then
    pbind (pointer_stars ty0) (fun ty ->
      let name = optional_ident () in
      pbind (need_punct ")") (fun _ ->
        let fn_tail = eat_punct "(" in
        pbind (if fn_tail then parameters () else POk []) (fun fn_params ->
          let fn_ty =
            if fn_tail then function_suffix_type ty fn_params else CPtr ty in
          pbind (array_suffixes fn_ty) (fun ty2 ->
          POk (Field (ty2, name))))))
  else
    pbind (pointer_stars ty0) (fun ty ->
      let name = optional_ident () in
      if eat_punct ":" then
        pbind (assign_expr ()) (fun _bits -> POk (Field (ty, name)))
      else
        pbind (array_suffixes ty) (fun ty2 ->
        POk (Field (ty2, name))))

and parameters () =
  if eat_punct ")" then POk []
  else if parameter_void_only () then POk []
  else
    pbind (parameter ()) (fun first ->
    pbind (parameter_tail ()) (fun rest ->
    pbind (need_punct ")") (fun _ ->
    POk (first :: rest))))

and parameter_void_only () =
  if !p_pos + 1 < !p_ntoks then
    (match array_get !p_toks !p_pos with
     | Tok (_, _, TkIdent n) ->
         if bytes_eq_str n "void" then
           (match array_get !p_toks (!p_pos + 1) with
            | Tok (_, _, TkPunct p) ->
                if bytes_eq_str p ")" then (p_pos := !p_pos + 2; true) else false
            | _ -> false)
         else false
     | _ -> false)
  else false

and parameter_tail () =
  if eat_punct "," then
    (if eat_punct "..." then POk []
     else
       pbind (parameter ()) (fun p ->
       pbind (parameter_tail ()) (fun ps ->
       POk (p :: ps))))
  else POk []

and parameter () =
  pbind (parse_ctype ()) (fun ty0 ->
  pbind (parameter_declarator ty0) (fun ty_name ->
    let (ty, name) = ty_name in
    POk (Param (ty, name))))

and parameter_declarator ty0 =
  if eat_punct "(" then
    pbind (pointer_stars ty0) (fun ty ->
      let name = optional_ident () in
      pbind (need_punct ")") (fun _ ->
        let fn_tail = eat_punct "(" in
        pbind (if fn_tail then parameters () else POk []) (fun fn_params ->
          POk ((if fn_tail then function_suffix_type ty fn_params else CPtr ty), name))))
  else
    pbind (pointer_stars ty0) (fun ty ->
      let name = optional_ident () in
      let fn_tail = eat_punct "(" in
      pbind (if fn_tail then parameters () else POk []) (fun fn_params ->
        let ty_fn =
          if fn_tail then CPtr (CFunc (ty, param_types fn_params)) else ty in
        pbind (array_suffixes ty_fn) (fun ty2 ->
        POk (ty2, name))))

and compound () =
  pbind (need_punct "{") (fun _ ->
    (* withParserScope: types enter/leave, constants restored on leave *)
    let saved_consts = !p_consts in
    let saved_cm = !p_constmap in
    p_types := scope_enter !p_types;
    let body = stmts_until_close () in
    p_types := scope_leave !p_types;
    p_consts := saved_consts;
    p_constmap := saved_cm;
    body)

and stmts_until_close () = p_until_punct "}" parse_stmt

and parse_stmt () =
  pbind (p_peek ()) (fun tok ->
    match tok with
    | Tok (_, _, TkIdent name) ->
        if bytes_eq_str name "typedef" then
          (p_advance ();
           pbind (typedef_decl ()) (fun _ -> POk STypedef))
        else if bytes_eq_str name "return" then (p_advance (); parse_return ())
        else if bytes_eq_str name "if" then (p_advance (); parse_if ())
        else if bytes_eq_str name "while" then (p_advance (); parse_while ())
        else if bytes_eq_str name "do" then (p_advance (); parse_do_while ())
        else if bytes_eq_str name "for" then (p_advance (); parse_for ())
        else if bytes_eq_str name "switch" then (p_advance (); parse_switch ())
        else if bytes_eq_str name "case" then
          (p_advance ();
           pbind (p_expr ()) (fun v ->
           pbind (need_punct ":") (fun _ -> POk (SCase v))))
        else if bytes_eq_str name "default" then
          (p_advance ();
           pbind (need_punct ":") (fun _ -> POk SDefault))
        else if bytes_eq_str name "break" then
          (p_advance ();
           pbind (need_punct ";") (fun _ -> POk SBreak))
        else if bytes_eq_str name "continue" then
          (p_advance ();
           pbind (need_punct ";") (fun _ -> POk SContinue))
        else if bytes_eq_str name "goto" then
          (p_advance ();
           pbind (need_ident ()) (fun l ->
           pbind (need_punct ";") (fun _ -> POk (SGoto l))))
        else if peek_second_punct ":" then
          (p_advance ();
           pbind (need_punct ":") (fun _ -> POk (SLabel name)))
        else if identifier_starts_declaration () then parse_decl_stmt ()
        else if starts_type_name name then parse_decl_stmt ()
        else parse_expr_stmt ()
    | Tok (_, _, TkPunct p) ->
        if bytes_eq_str p ";" then (p_advance (); POk (SExpr (EInt (str_to_bytes "0"))))
        else if bytes_eq_str p "{" then
          pbind (compound ()) (fun b -> POk (SBlock b))
        else parse_expr_stmt ()
    | _ -> parse_expr_stmt ())

and parse_expr_stmt () =
  pbind (p_expr ()) (fun e ->
  pbind (need_punct ";") (fun _ -> POk (SExpr e)))

and parse_return () =
  if eat_punct ";" then POk (SReturn None)
  else
    pbind (p_expr ()) (fun e ->
    pbind (need_punct ";") (fun _ -> POk (SReturn (Some e))))

and parse_if () =
  pbind (p_parens p_expr) (fun cond ->
  pbind (stmt_as_block ()) (fun yes ->
    let has_else = eat_ident "else" in
    pbind (if has_else then stmt_as_block () else POk []) (fun no ->
    POk (SIf (cond, yes, no)))))

and parse_while () =
  pbind (p_parens p_expr) (fun cond ->
  pbind (stmt_as_block ()) (fun body ->
  POk (SWhile (cond, body))))

and parse_do_while () =
  pbind (stmt_as_block ()) (fun body ->
  pbind (need_ident_value "while") (fun _ ->
  pbind (p_parens p_expr) (fun cond ->
  pbind (need_punct ";") (fun _ ->
  POk (SDoWhile (body, cond))))))

and parse_for () =
  pbind (need_punct "(") (fun _ ->
  pbind (optional_expr_until ";") (fun init0 ->
  pbind (optional_expr_until ";") (fun cond ->
  pbind (optional_expr_until ")") (fun step ->
  pbind (stmt_as_block ()) (fun body ->
  POk (SFor (init0, cond, step, body)))))))

and parse_switch () =
  pbind (p_parens p_expr) (fun v ->
  pbind (stmt_as_block ()) (fun body ->
  POk (SSwitch (v, body))))

and optional_expr_until punct =
  if eat_punct punct then POk None
  else
    pbind (p_expr ()) (fun e ->
    pbind (need_punct punct) (fun _ -> POk (Some e)))

and stmt_as_block () =
  pbind (p_peek ()) (fun tok ->
    match tok with
    | Tok (_, _, TkPunct p) ->
        if bytes_eq_str p "{" then
          pbind (compound ()) (fun b -> POk [SBlock b])
        else stmt_as_block_single ()
    | _ -> stmt_as_block_single ())

and stmt_as_block_single () =
  pbind (parse_stmt ()) (fun first ->
    match first with
    | SLabel _ ->
        pbind (parse_stmt ()) (fun body -> POk [first; body])
    | _ -> POk [first])

and parse_decl_stmt () =
  pbind (parse_ctype ()) (fun ty0 ->
    if eat_punct ";" then POk (SExpr (EInt (str_to_bytes "0")))
    else
      (* optionalP (tryP (localPrototype ty0)) *)
      p_try_or
        (fun () ->
          pbind (local_prototype ty0) (fun _ ->
          POk (SExpr (EInt (str_to_bytes "0")))))
        (fun () ->
          pbind (declaration_item ty0) (fun first ->
          pbind (declaration_items_tail ty0) (fun rest ->
          POk (match first :: rest with
               | [(ty, name, init0)] -> SDecl (ty, name, init0)
               | items -> SDecls items)))))

and local_prototype ty0 =
  pbind (pointer_stars ty0) (fun _ty ->
  pbind (need_ident ()) (fun _name ->
  pbind (need_punct "(") (fun _ ->
  pbind (skip_balanced_parens 1) (fun _ ->
  pbind (skip_attributes ()) (fun _ ->
  need_punct ";")))))

and skip_balanced_parens depth =
  if depth <= 0 then POk ()
  else
    pbind (p_peek ()) (fun tok ->
      match tok with
      | Tok (_, _, TkPunct p) ->
          if bytes_eq_str p "(" then (p_advance (); skip_balanced_parens (depth + 1))
          else if bytes_eq_str p ")" then (p_advance (); skip_balanced_parens (depth - 1))
          else (p_advance (); skip_balanced_parens depth)
      | _ -> (p_advance (); skip_balanced_parens depth))

and declaration_item ty0 =
  pbind (declarator ty0) (fun ty_name ->
    let (ty, name) = ty_name in
    pbind (skip_attributes ()) (fun _ ->
    pbind (p_optional_initializer ()) (fun init0 ->
    POk (ty, name, init0))))

and declaration_items_tail ty0 =
  p_until_punct ";" (fun () ->
    pbind (need_punct ",") (fun _ -> declaration_item ty0))

(* ---- types ---- *)

and parse_ctype () =
  pbind (skip_qualifiers ()) (fun _ ->
  pbind (parse_base_type ()) (fun ty ->
  pbind (skip_qualifiers ()) (fun _ ->
  POk ty)))

and parse_base_type () =
  pbind (p_peek ()) (fun tok ->
    match tok with
    | Tok (_, _, TkIdent name) ->
        (match
           list_find (fun kc -> (let (kw, _) = kc in bytes_eq_str name kw))
             simple_base_types
         with
         | Some kc -> (let (_, cty) = kc in (p_advance (); POk cty))
         | None ->
             if bytes_eq_str name "signed" then (p_advance (); POk (signed_base_type ()))
             else if bytes_eq_str name "unsigned" then (p_advance (); POk (unsigned_base_type ()))
             else if bytes_eq_str name "short" then (p_advance (); POk (optional_kw "int" CShort))
             else if bytes_eq_str name "long" then (p_advance (); POk (long_base_type ()))
             else if bytes_eq_str name "struct" then aggregate_type false
             else if bytes_eq_str name "union" then aggregate_type true
             else if bytes_eq_str name "enum" then enum_type ()
             else
               (p_advance ();
                match lookup_parser_type name with
                | Some ty -> POk ty
                | None -> POk (CNamed name)))
    | _ -> p_fail_tok_str tok "expected type")

and optional_kw kw ty = ((if eat_ident kw then ()); ty)

and signed_base_type () =
  if eat_ident "char" then CChar
  else if eat_ident "short" then optional_kw "int" CShort
  else if eat_ident "int" then CInt
  else CInt

and unsigned_base_type () =
  if eat_ident "char" then CUnsignedChar
  else if eat_ident "short" then optional_kw "int" CUnsignedShort
  else if eat_ident "long" then unsigned_long_tail ()
  else if eat_ident "int" then CUnsigned
  else CUnsigned

and unsigned_long_tail () =
  if eat_ident "long" then optional_kw "int" CUnsignedLongLong
  else if eat_ident "int" then CUnsignedLong
  else CUnsignedLong

and long_base_type () =
  if eat_ident "double" then CLongDouble
  else if eat_ident "int" then CLong
  else if eat_ident "long" then optional_kw "int" CLongLong
  else CLong

and aggregate_type is_union =
  p_advance ();
  let name = optional_ident () in
  if eat_punct "{" then
    pbind (aggregate_fields_until_close ()) (fun fields ->
      if bytes_length name = 0 then
        POk (if is_union then CUnionDef fields else CStructDef fields)
      else
        POk (if is_union then CUnionNamed (name, fields) else CStructNamed (name, fields)))
  else POk (if is_union then CUnion name else CStruct name)

and enum_type () =
  p_advance ();
  let name = optional_ident () in
  if eat_punct "{" then
    pbind (parse_enum_body 0) (fun _ -> POk (CEnum name))
  else POk (CEnum name)

and parse_enum_body next_value =
  if eat_punct "}" then POk ()
  else if eat_punct "," then parse_enum_body next_value
  else
    pbind (need_ident ()) (fun name ->
    pbind (enum_value next_value) (fun value ->
      (bind_parser_constant name value;
       if eat_punct "," then
         (if eat_punct "}" then POk () else parse_enum_body (value + 1))
       else need_punct "}")))

and enum_value next_value =
  if eat_punct "=" then
    (let toks = take_enum_value_expr () in
     match parse_const_expr !p_consts toks with
     | Some (value, trailing) ->
         (let all_ignorable ts =
            list_for_all
              (fun t ->
                match t with
                | Tok (_, _, TkPunct p) -> bytes_eq_str p ")"
                | _ -> false)
              ts in
          if all_ignorable trailing then POk value
          else
            (match trailing with
             | tok :: _ ->
                 (let b = buf_new 64 in
                  buf_add_str b "unexpected tokens in enum initializer: ";
                  buf_add_bytes b (token_text (tok_kind tok));
                  p_fail_tok tok (buf_take b))
             | [] ->
                 p_fail_here (str_to_bytes "unexpected tokens in enum initializer")))
     | None ->
         (let b = buf_new 64 in
          buf_add_str b "invalid enum initializer: ";
          buf_add_bytes b !ce_err;
          p_fail_here (buf_take b)))
  else POk next_value

and take_enum_value_expr () =
  let rec go braces parens brackets acc =
    if !p_pos >= !p_ntoks then list_rev acc
    else
      (let tok = array_get !p_toks !p_pos in
       match tok with
       | Tok (_, _, TkPunct p) ->
           if bytes_eq_str p "," && braces = 0 && parens = 0 && brackets = 0 then
             list_rev acc
           else if bytes_eq_str p "}" && braces = 0 && parens = 0 && brackets = 0 then
             list_rev acc
           else if bytes_eq_str p "{" then
             (p_pos := !p_pos + 1; go (braces + 1) parens brackets (tok :: acc))
           else if bytes_eq_str p "}" then
             (p_pos := !p_pos + 1; go (imax 0 (braces - 1)) parens brackets (tok :: acc))
           else if bytes_eq_str p "(" then
             (p_pos := !p_pos + 1; go braces (parens + 1) brackets (tok :: acc))
           else if bytes_eq_str p ")" then
             (p_pos := !p_pos + 1; go braces (imax 0 (parens - 1)) brackets (tok :: acc))
           else if bytes_eq_str p "[" then
             (p_pos := !p_pos + 1; go braces parens (brackets + 1) (tok :: acc))
           else if bytes_eq_str p "]" then
             (p_pos := !p_pos + 1; go braces parens (imax 0 (brackets - 1)) (tok :: acc))
           else (p_pos := !p_pos + 1; go braces parens brackets (tok :: acc))
       | _ -> (p_pos := !p_pos + 1; go braces parens brackets (tok :: acc))) in
  go 0 0 0 []

and skip_qualifiers () =
  match p_peek_maybe () with
  | Some (Tok (_, _, TkIdent name)) ->
      if is_unsupported_qualifier name then
        (let b = buf_new 48 in
         buf_add_bytes b name;
         buf_add_str b " is not supported";
         p_fail_here (buf_take b))
      else if is_storage_or_qualifier name then (p_advance (); skip_qualifiers ())
      else if bytes_eq_str name "__attribute__" || bytes_eq_str name "__extension__" then
        pbind (skip_attributes ()) (fun _ -> skip_qualifiers ())
      else POk ()
  | _ -> POk ()

and skip_attributes () =
  match p_peek_maybe () with
  | Some (Tok (_, _, TkIdent name)) ->
      if bytes_eq_str name "__attribute__" then
        (p_advance ();
         if eat_punct "(" then
           pbind (skip_balanced_parens 1) (fun _ -> skip_attributes ())
         else skip_attributes ())
      else if bytes_eq_str name "__extension__" then
        (p_advance (); skip_attributes ())
      else POk ()
  | _ -> POk ()

and declarator ty0 =
  pbind (pointer_stars ty0) (fun ty -> direct_declarator ty)

and direct_declarator ty =
  if eat_punct "(" then
    pbind (declarator ty) (fun inner ->
      let (inner_ty, name) = inner in
      pbind (need_punct ")") (fun _ ->
      pbind (grouped_declarator_suffixes inner_ty) (fun ty2 ->
      pbind (skip_attributes ()) (fun _ ->
      POk (ty2, name)))))
  else
    pbind (need_ident ()) (fun name ->
    pbind (array_suffixes ty) (fun ty2 ->
    pbind (skip_attributes ()) (fun _ ->
    POk (ty2, name))))

and grouped_declarator_suffixes ty =
  if eat_punct "(" then
    pbind (parameters ()) (fun params ->
      grouped_declarator_suffixes (function_suffix_type ty params))
  else array_suffixes ty

and function_suffix_type ty params =
  match ty with
  | CPtr inner -> CPtr (CFunc (inner, param_types params))
  | _ -> CFunc (ty, param_types params)

and optional_function_suffix ty =
  if eat_punct "(" then
    pbind (parameters ()) (fun params ->
    POk (CFunc (ty, param_types params)))
  else POk ty

and pointer_stars ty =
  if eat_punct "*" then
    pbind (skip_qualifiers ()) (fun _ -> pointer_stars (CPtr ty))
  else POk ty

and array_suffixes ty =
  if eat_punct "[" then
    (* optionalP expr: empty bounds fail without consumption *)
    pbind (p_optional p_expr) (fun bound ->
    pbind (need_punct "]") (fun _ ->
    array_suffixes (CArray (ty, bound))))
  else POk ty

(* ---- expressions ---- *)

and p_expr () = expression 0

and assign_expr () = expression 1

and initializer_expr () =
  if eat_punct "{" then
    pbind (initializer_list ()) (fun items -> POk (EInitList items))
  else assign_expr ()

and initializer_list () =
  if eat_punct "}" then POk []
  else
    pbind (initializer_expr ()) (fun v ->
      if eat_punct "," then
        (if eat_punct "}" then POk [v]
         else
           pbind (initializer_list ()) (fun rest -> POk (v :: rest)))
      else
        pbind (need_punct "}") (fun _ -> POk [v]))

and expression minprec =
  pbind (unary_expr ()) (fun u ->
  pbind (parse_postfix u) (fun lhs ->
  expr_climb minprec lhs))

and expr_climb minprec lhs =
  match p_peek_maybe () with
  | None -> POk lhs
  | Some (Tok (_, _, TkPunct op)) ->
      if bytes_eq_str op "?" && minprec <= 2 then
        (p_advance ();
         pbind (p_expr ()) (fun yes ->
         pbind (need_punct ":") (fun _ ->
         pbind (expression 2) (fun no ->
         expr_climb minprec (ECond (lhs, yes, no))))))
      else
        (let prec = binop_prec op in
         if prec >= 0 && prec >= minprec then
           (p_advance ();
            pbind (expression (if binop_right_assoc op then prec else prec + 1)) (fun rhs ->
            expr_climb minprec (assign_node op lhs rhs)))
         else POk lhs)
  | Some _ -> POk lhs

and assign_node op lhs rhs =
  if bytes_eq_str op "=" then EAssign (lhs, rhs)
  else
    (match
       list_find (fun fb -> (let (full, _) = fb in bytes_eq_str op full))
         compound_assign_ops
     with
     | Some fb -> (let (_, base) = fb in ECompoundAssign (str_to_bytes base, lhs, rhs))
     | None -> EBinary (op, lhs, rhs))

and unary_expr () =
  pbind (p_peek ()) (fun tok ->
    match tok with
    | Tok (_, _, TkPunct op) ->
        if bytes_eq_any op prefix_unary_ops then
          (p_advance ();
           pbind (unary_expr ()) (fun inner ->
           pbind (parse_postfix inner) (fun inner2 ->
           POk (EUnary (op, inner2)))))
        else if bytes_eq_str op "(" then
          (p_advance ();
           let is_cast =
             (match p_peek_maybe () with
              | Some t -> token_starts_type t
              | None -> false) in
           if is_cast then
             pbind (type_name ()) (fun ty ->
             pbind (need_punct ")") (fun _ ->
             pbind (unary_expr ()) (fun inner ->
             pbind (parse_postfix inner) (fun inner2 ->
             POk (ECast (ty, inner2))))))
           else
             pbind (p_expr ()) (fun e ->
             pbind (need_punct ")") (fun _ -> POk e)))
        else p_fail_tok_str tok "expected expression"
    | Tok (_, _, TkIdent s) ->
        if bytes_eq_str s "sizeof" then (p_advance (); parse_sizeof ())
        else
          (p_advance ();
           match lookup_parser_constant s with
           | Some value -> POk (EInt (int_to_bytes value))
           | None -> POk (EVar s))
    | Tok (_, _, TkInt s) -> (p_advance (); POk (EInt s))
    | Tok (_, _, TkFloat s) -> (p_advance (); POk (EFloat s))
    | Tok (_, _, TkChar s) -> (p_advance (); POk (EChar s))
    | Tok (_, _, TkString _) ->
        pbind (string_literal ()) (fun s -> POk (EString s))
    | _ -> p_fail_tok_str tok "expected expression")

and type_name () =
  pbind (parse_ctype ()) (fun ty -> pointer_stars ty)

and parse_sizeof () =
  if eat_punct "(" then sizeof_paren ()
  else
    pbind (unary_expr ()) (fun inner ->
    pbind (parse_postfix inner) (fun inner2 ->
    POk (ESizeofExpr inner2)))

and sizeof_paren () =
  let starts =
    (match p_peek_maybe () with
     | Some t -> token_starts_type t
     | None -> false) in
  if starts then
    (* speculative: typeName ")" with no postfix continuation *)
    (let save = p_save () in
     match
       pbind (type_name ()) (fun ty ->
       pbind (need_punct ")") (fun _ -> POk ty))
     with
     | POk ty ->
         if postfix_continues () then
           (p_restore save; p_failed := false; sizeof_paren_expr ())
         else POk (ESizeofType ty)
     | PFail -> (p_restore save; p_failed := false; sizeof_paren_expr ()))
  else sizeof_paren_expr ()

and sizeof_paren_expr () =
  pbind (p_expr ()) (fun v ->
  pbind (need_punct ")") (fun _ ->
  pbind (parse_postfix v) (fun v2 ->
  POk (ESizeofExpr v2))))

and postfix_continues () =
  match p_peek_maybe () with
  | Some (Tok (_, _, TkPunct p)) -> bytes_eq_any p postfix_start_puncts
  | _ -> false

and parse_postfix base =
  match p_peek_maybe () with
  | Some (Tok (_, _, TkPunct p)) ->
      if bytes_eq_str p "(" then
        (p_advance ();
         pbind (call_arguments ()) (fun args ->
         parse_postfix (ECall (base, args))))
      else if bytes_eq_str p "[" then
        (p_advance ();
         pbind (p_expr ()) (fun ix ->
         pbind (need_punct "]") (fun _ ->
         parse_postfix (EIndex (base, ix)))))
      else if bytes_eq_str p "." then
        (p_advance ();
         pbind (need_ident ()) (fun name ->
         parse_postfix (EMember (base, name))))
      else if bytes_eq_str p "->" then
        (p_advance ();
         pbind (need_ident ()) (fun name ->
         parse_postfix (EPtrMember (base, name))))
      else if bytes_eq_str p "++" then
        (p_advance (); parse_postfix (EPostfix (str_to_bytes "++", base)))
      else if bytes_eq_str p "--" then
        (p_advance (); parse_postfix (EPostfix (str_to_bytes "--", base)))
      else POk base
  | _ -> POk base

and call_arguments () =
  if eat_punct ")" then POk []
  else
    pbind (assign_expr ()) (fun first ->
    pbind (p_many_comma_args ()) (fun rest ->
    pbind (need_punct ")") (fun _ ->
    POk (first :: rest))))

and p_many_comma_args () =
  p_many (fun () ->
    pbind (need_punct ",") (fun _ -> assign_expr ()))

(* adjacent string literals are concatenated; the result re-encodes every
   content byte as a hex escape *)
and string_literal () =
  pbind (need_string ()) (fun first ->
  pbind (p_many need_string) (fun rest ->
  POk (join_strings (first :: rest))))

and need_string () =
  pbind (p_peek ()) (fun tok ->
    match tok with
    | Tok (_, _, TkString s) -> (p_advance (); POk s)
    | _ -> p_fail_tok_str tok "expected string literal")

and join_strings strings =
  let out = buf_new 64 in
  buf_push out ch_dquote;
  let one s =
    (* decoded content bytes minus the trailing NUL *)
    let bs = string_bytes s in
    let rec emit l =
      match l with
      | [] -> ()
      | [_] -> ()   (* drop terminator *)
      | b :: rest ->
          (buf_push out ch_bslash;
           buf_push out ch_x;
           (* decoded bytes are 0..255, so native / and mod are exact *)
           let h1 = b / 16 in
           let h2 = b mod 16 in
           buf_push out (if h1 < 10 then ch_0 + h1 else ch_a + h1 - 10);
           buf_push out (if h2 < 10 then ch_0 + h2 else ch_a + h2 - 10);
           emit rest) in
    emit bs in
  list_iter one strings;
  buf_push out ch_dquote;
  buf_take out

(* ---- declaration-start prediction ---- *)

and identifier_starts_declaration () =
  if !p_pos < !p_ntoks then
    (match array_get !p_toks !p_pos with
     | Tok (_, _, TkIdent name) ->
         if starts_type_name name then true
         else if is_some (lookup_parser_type name) then
           typedef_declarator_follows (!p_pos + 1)
         else false
     | _ -> false)
  else false

and typedef_declarator_follows i =
  if i < !p_ntoks then
    (match array_get !p_toks i with
     | Tok (_, _, TkIdent name) ->
         if is_storage_or_qualifier name then typedef_declarator_follows (i + 1)
         else true
     | Tok (_, _, TkPunct p) -> bytes_eq_str p "*"
     | _ -> false)
  else false

(* ---- entry point ---- *)

let parse_program toks =
  (* token list -> array *)
  let n = list_length toks in
  let arr = array_make (imax 1 n) p_dummy_tok in
  list_iteri (fun i t -> array_set arr i t) toks;
  p_toks := arr;
  p_ntoks := n;
  p_pos := 0;
  p_types := scope_empty;
  p_constmap := SymE;
  p_consts := [];
  (* builtin type aliases, inserted in list order: FILE and FUNCTION,
     then the opaque named integer types, then the va_list family *)
  bind_parser_type (str_to_bytes "FILE") (CStruct (str_to_bytes "FILE"));
  bind_parser_type (str_to_bytes "FUNCTION") CLong;
  list_iter
    (fun n -> bind_parser_type (str_to_bytes n) (CNamed (str_to_bytes n)))
    ["size_t"; "ssize_t"; "time_t"; "ptrdiff_t"; "intptr_t"; "uintptr_t";
     "int8_t"; "int16_t"; "int32_t"; "int64_t";
     "uint8_t"; "uint16_t"; "uint32_t"; "uint64_t"];
  list_iter
    (fun n -> bind_parser_type (str_to_bytes n) (CPtr CVoid))
    ["va_list"; "__builtin_va_list"; "jmp_buf"];
  p_failed := false;
  match parse_program_decls () with
  | PFail -> None
  | POk decls ->
      if !p_pos < !p_ntoks then
        (p_record_fail (array_get !p_toks !p_pos) (str_to_bytes "trailing tokens");
         None)
      else Some decls

(* render the recorded parse error like showPos ++ ": " ++ msg *)
let parse_error_render () =
  let b = buf_new 64 in
  buf_add_int b !p_eline;
  buf_push b ch_colon;
  buf_add_int b !p_ecol;
  buf_add_str b ": ";
  buf_add_bytes b !p_emsg;
  buf_take b
