(* ccc part 30: C parser; port of Hcc.Parser.
   The ParseLite monad becomes global mutable state: a token array with a
   cursor, the parser environment (typedef scope map, enum constants), and
   a failure flag. Functions return dummies once p_failed is set; callers
   check the flag after every sub-parse, which is the explicit spelling of
   the reference's >>= chain. Backtracking (pTry/pOptional) restores a
   snapshot of cursor + environment; consumption is "cursor moved". *)

(* ---- state ---- *)

let p_dummy_bytes = bytes_create 0
let p_dummy_tok = Tok (1, 1, TkPunct p_dummy_bytes)
let p_dummy_expr = EInt p_dummy_bytes
let p_dummy_stmt = SBreak
let p_dummy_decl = DTypeDecl []
let p_dummy_param = Param (CVoid, p_dummy_bytes)
let p_dummy_field = Field (CVoid, p_dummy_bytes)

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

let p_fail_tok tok msg =
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

let p_fail_tok_str tok msg = p_fail_tok tok (str_to_bytes msg)

let p_fail_eof () =
  if !p_failed then ()
  else
    (p_failed := true;
     p_eline := 1;
     p_ecol := 1;
     p_emsg := str_to_bytes "unexpected end of input")

(* ---- cursor primitives ---- *)

let p_peek_maybe () =
  if !p_pos < !p_ntoks then Some (array_get !p_toks !p_pos) else None

let p_peek () =
  if !p_pos < !p_ntoks then array_get !p_toks !p_pos
  else (p_fail_eof (); p_dummy_tok)

let p_advance () =
  if !p_pos < !p_ntoks then p_pos := !p_pos + 1 else p_fail_eof ()

let eat_punct s =
  if !p_pos < !p_ntoks then
    (match array_get !p_toks !p_pos with
     | Tok (_, _, TkPunct p) ->
         if bytes_eq_str p s then (p_pos := !p_pos + 1; true) else false
     | _ -> false)
  else false

let need_punct s =
  if eat_punct s then ()
  else
    (let b = buf_new 32 in
     buf_add_str b "expected ";
     buf_add_bytes b (show_quoted (str_to_bytes s));
     p_fail_tok (p_peek ()) (buf_take b))

let eat_ident s =
  if !p_pos < !p_ntoks then
    (match array_get !p_toks !p_pos with
     | Tok (_, _, TkIdent p) ->
         if bytes_eq_str p s then (p_pos := !p_pos + 1; true) else false
     | _ -> false)
  else false

let need_ident () =
  let tok = p_peek () in
  match tok with
  | Tok (_, _, TkIdent s) -> (p_advance (); s)
  | _ -> (p_fail_tok_str tok "expected identifier"; p_dummy_bytes)

let optional_ident () =
  if !p_pos < !p_ntoks then
    (match array_get !p_toks !p_pos with
     | Tok (_, _, TkIdent s) -> (p_pos := !p_pos + 1; s)
     | _ -> p_dummy_bytes)
  else p_dummy_bytes

let need_ident_value expected =
  let tok = p_peek () in
  match tok with
  | Tok (_, _, TkIdent s) ->
      if bytes_eq_str s expected then p_advance ()
      else
        (let b = buf_new 32 in
         buf_add_str b "expected ";
         buf_add_bytes b (show_quoted (str_to_bytes expected));
         p_fail_tok tok (buf_take b))
  | _ ->
      (let b = buf_new 32 in
       buf_add_str b "expected ";
       buf_add_bytes b (show_quoted (str_to_bytes expected));
       p_fail_tok tok (buf_take b))

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

(* ---- keyword tables ---- *)

let is_builtin_type_name n =
  bytes_eq_str n "void" || bytes_eq_str n "_Bool" || bytes_eq_str n "int" ||
  bytes_eq_str n "char" || bytes_eq_str n "signed" || bytes_eq_str n "unsigned" ||
  bytes_eq_str n "short" || bytes_eq_str n "long" || bytes_eq_str n "float" ||
  bytes_eq_str n "double" || bytes_eq_str n "struct" || bytes_eq_str n "union" ||
  bytes_eq_str n "enum"

let is_storage_or_qualifier n =
  bytes_eq_str n "const" || bytes_eq_str n "volatile" || bytes_eq_str n "static" ||
  bytes_eq_str n "extern" || bytes_eq_str n "register" || bytes_eq_str n "inline" ||
  bytes_eq_str n "auto" || bytes_eq_str n "restrict" ||
  bytes_eq_str n "_Noreturn" || bytes_eq_str n "_Atomic"

let is_unsupported_qualifier n =
  bytes_eq_str n "_Thread_local" || bytes_eq_str n "__thread" ||
  bytes_eq_str n "_Alignas" || bytes_eq_str n "_Generic"

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
  | None -> []
  | Some _ ->
      let d = top_decl () in
      if !p_failed then []
      else
        (let rest = parse_program_decls () in
         d :: rest)

and top_decl () =
  if eat_punct ";" then DTypeDecl []
  else if eat_ident "_Static_assert" then parse_static_assert ()
  else if eat_ident "typedef" then typedef_decl ()
  else
    (* optionalP (tryP standaloneAggregateDecl) *)
    (let save = p_save () in
     let d = standalone_aggregate_decl () in
     if !p_failed then
       (p_restore save;
        p_failed := false;
        top_decl_no_struct ())
     else d)

and parse_static_assert () =
  need_punct "(";
  if !p_failed then p_dummy_decl
  else
    (let toks = take_static_assert_expr () in
     match parse_const_expr !p_consts toks with
     | Some (value, []) ->
         if value = 0 then
           (p_fail_tok_str (p_peek ()) "_Static_assert failed"; p_dummy_decl)
         else
           (skip_static_assert_message ();
            if !p_failed then p_dummy_decl
            else
              (need_punct ")";
               need_punct ";";
               DTypeDecl []))
     | Some (_, tok :: _) ->
         (p_fail_tok_str tok "unexpected tokens in _Static_assert expression";
          p_dummy_decl)
     | None ->
         (let b = buf_new 64 in
          buf_add_str b "invalid _Static_assert expression: ";
          buf_add_bytes b !ce_err;
          p_fail_tok (p_peek ()) (buf_take b);
          p_dummy_decl))

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
    (let tok = p_peek () in
     match tok with
     | Tok (_, _, TkString _) -> p_advance ()
     | _ -> p_fail_tok_str tok "expected string literal in _Static_assert")

and top_decl_no_struct () =
  let is_extern = leading_extern_qualifier () in
  let ty0 = parse_ctype () in
  if !p_failed then p_dummy_decl
  else if eat_punct ";" then DTypeDecl [ty0]
  else
    (let (ty, name) = declarator ty0 in
     if !p_failed then p_dummy_decl
     else if eat_punct "(" then
       (let params = parameters () in
        if !p_failed then p_dummy_decl
        else
          (skip_attributes ();
           if eat_punct ";" then DPrototype (ty, name, params)
           else
             (let body = compound () in
              if !p_failed then p_dummy_decl
              else DFunction (ty, name, params, body))))
     else
       (let init0 = p_optional_initializer () in
        if !p_failed then p_dummy_decl
        else
          (let rest = declaration_items_tail ty0 in
           if !p_failed then p_dummy_decl
           else global_decl is_extern ((ty, name, init0) :: rest))))

(* optionalP (eatPunct "=" >> initializerExpr): the initializer parser
   runs even without '=', failing without consumption *)
and p_optional_initializer () =
  let save = p_save () in
  let _eq = eat_punct "=" in
  let v = initializer_expr () in
  if !p_failed then
    (if !p_pos = snap_pos save then
       (p_restore save; p_failed := false; None)
     else None)
  else Some v

and global_decl is_extern decls =
  let rec all_uninit ds =
    match ds with
    | [] -> true
    | (_, _, i) :: rest -> (match i with None -> all_uninit rest | Some _ -> false) in
  if is_extern && all_uninit decls then
    (let rec pairs ds =
       match ds with
       | [] -> []
       | (ty, name, _) :: rest -> (ty, name) :: pairs rest in
     DExternGlobals (pairs decls))
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
  let ty0 = parse_ctype () in
  if !p_failed then p_dummy_decl
  else
    (let first = typedef_item ty0 in
     if !p_failed then p_dummy_decl
     else
       (let rest = typedef_items_tail ty0 in
        if !p_failed then p_dummy_decl
        else
          (let rec bind_all items =
             match items with
             | [] -> ()
             | (name, ty) :: tl ->
                 ((if bytes_length name > 0 then bind_parser_type name ty);
                  bind_all tl) in
           bind_all (first :: rest);
           let rec types items =
             match items with
             | [] -> []
             | (_, ty) :: tl -> ty :: types tl in
           DTypeDecl (types (first :: rest)))))

and typedef_item ty0 =
  let (ty, name) = declarator ty0 in
  if !p_failed then (p_dummy_bytes, CVoid)
  else
    (let ty2 = optional_function_suffix ty in
     if !p_failed then (p_dummy_bytes, CVoid)
     else (skip_attributes (); (name, ty2)))

and typedef_items_tail ty0 =
  if eat_punct ";" then []
  else
    (need_punct ",";
     if !p_failed then []
     else
       (let item = typedef_item ty0 in
        if !p_failed then []
        else
          (let rest = typedef_items_tail ty0 in
           item :: rest)))

and standalone_aggregate_decl () =
  let tok = p_peek () in
  let is_union =
    (match tok with
     | Tok (_, _, TkIdent n) ->
         if bytes_eq_str n "struct" then (p_advance (); false)
         else if bytes_eq_str n "union" then (p_advance (); true)
         else (p_fail_tok_str tok "expected aggregate declaration"; false)
     | _ -> (p_fail_tok_str tok "expected aggregate declaration"; false)) in
  if !p_failed then p_dummy_decl
  else
    (let tag = optional_ident () in
     need_punct "{";
     if !p_failed then p_dummy_decl
     else
       (let fields = aggregate_fields_until_close () in
        if !p_failed then p_dummy_decl
        else
          (need_punct ";";
           if !p_failed then p_dummy_decl
           else DStructDecl (is_union, tag, fields))))

and aggregate_fields_until_close () =
  if eat_punct "}" then []
  else
    (let fs = field_decl () in
     if !p_failed then []
     else
       (let rest = aggregate_fields_until_close () in
        list_append fs rest))

and field_decl () =
  let ty0 = parse_ctype () in
  if !p_failed then []
  else
    (let first = field_declarator ty0 in
     if !p_failed then []
     else
       (let rest = p_many_comma_field ty0 in
        if !p_failed then []
        else
          (need_punct ";";
           first :: rest)))

(* manyP (needPunct "," >> fieldDeclarator ty0) *)
and p_many_comma_field ty0 =
  let save = p_save () in
  need_punct ",";
  if !p_failed then
    (if !p_pos = snap_pos save then (p_restore save; p_failed := false; [])
     else [])
  else
    (let f = field_declarator ty0 in
     if !p_failed then []
     else
       (let rest = p_many_comma_field ty0 in
        f :: rest))

and field_declarator ty0 =
  if eat_punct "(" then
    (let ty = pointer_stars ty0 in
     let name = optional_ident () in
     need_punct ")";
     if !p_failed then p_dummy_field
     else
       (let fn_tail = eat_punct "(" in
        let fn_params = if fn_tail then parameters () else [] in
        if !p_failed then p_dummy_field
        else
          (let fn_ty =
             if fn_tail then function_suffix_type ty fn_params else CPtr ty in
           let ty2 = array_suffixes fn_ty in
           if !p_failed then p_dummy_field
           else Field (ty2, name))))
  else
    (let ty = pointer_stars ty0 in
     let name = optional_ident () in
     if eat_punct ":" then
       (let _bits = assign_expr () in
        if !p_failed then p_dummy_field
        else Field (ty, name))
     else
       (let ty2 = array_suffixes ty in
        if !p_failed then p_dummy_field
        else Field (ty2, name)))

and parameters () =
  if eat_punct ")" then []
  else if parameter_void_only () then []
  else
    (let first = parameter () in
     if !p_failed then []
     else
       (let rest = parameter_tail () in
        if !p_failed then []
        else
          (need_punct ")";
           first :: rest)))

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
    (if eat_punct "..." then []
     else
       (let p = parameter () in
        if !p_failed then []
        else
          (let ps = parameter_tail () in
           p :: ps)))
  else []

and parameter () =
  let ty0 = parse_ctype () in
  if !p_failed then p_dummy_param
  else
    (let (ty, name) = parameter_declarator ty0 in
     Param (ty, name))

and parameter_declarator ty0 =
  if eat_punct "(" then
    (let ty = pointer_stars ty0 in
     let name = optional_ident () in
     need_punct ")";
     if !p_failed then (CVoid, p_dummy_bytes)
     else
       (let fn_tail = eat_punct "(" in
        let fn_params = if fn_tail then parameters () else [] in
        if !p_failed then (CVoid, p_dummy_bytes)
        else
          ((if fn_tail then function_suffix_type ty fn_params else CPtr ty), name)))
  else
    (let ty = pointer_stars ty0 in
     let name = optional_ident () in
     let fn_tail = eat_punct "(" in
     let fn_params = if fn_tail then parameters () else [] in
     if !p_failed then (CVoid, p_dummy_bytes)
     else
       (let ty_fn =
          if fn_tail then CPtr (CFunc (ty, param_types fn_params)) else ty in
        let ty2 = array_suffixes ty_fn in
        if !p_failed then (CVoid, p_dummy_bytes)
        else (ty2, name)))

and compound () =
  need_punct "{";
  if !p_failed then []
  else
    (* withParserScope: types enter/leave, constants restored on leave *)
    (let saved_consts = !p_consts in
     let saved_cm = !p_constmap in
     p_types := scope_enter !p_types;
     let body = stmts_until_close () in
     p_types := scope_leave !p_types;
     p_consts := saved_consts;
     p_constmap := saved_cm;
     body)

and stmts_until_close () =
  if eat_punct "}" then []
  else
    (let s = parse_stmt () in
     if !p_failed then []
     else
       (let rest = stmts_until_close () in
        s :: rest))

and parse_stmt () =
  let tok = p_peek () in
  if !p_failed then p_dummy_stmt
  else
    (match tok with
     | Tok (_, _, TkIdent name) ->
         if bytes_eq_str name "typedef" then
           (p_advance ();
            let _ = typedef_decl () in
            if !p_failed then p_dummy_stmt else STypedef)
         else if bytes_eq_str name "return" then (p_advance (); parse_return ())
         else if bytes_eq_str name "if" then (p_advance (); parse_if ())
         else if bytes_eq_str name "while" then (p_advance (); parse_while ())
         else if bytes_eq_str name "do" then (p_advance (); parse_do_while ())
         else if bytes_eq_str name "for" then (p_advance (); parse_for ())
         else if bytes_eq_str name "switch" then (p_advance (); parse_switch ())
         else if bytes_eq_str name "case" then
           (p_advance ();
            let v = p_expr () in
            if !p_failed then p_dummy_stmt
            else (need_punct ":"; SCase v))
         else if bytes_eq_str name "default" then
           (p_advance (); need_punct ":"; SDefault)
         else if bytes_eq_str name "break" then
           (p_advance (); need_punct ";"; SBreak)
         else if bytes_eq_str name "continue" then
           (p_advance (); need_punct ";"; SContinue)
         else if bytes_eq_str name "goto" then
           (p_advance ();
            let l = need_ident () in
            if !p_failed then p_dummy_stmt
            else (need_punct ";"; SGoto l))
         else if peek_second_punct ":" then
           (p_advance (); need_punct ":"; SLabel name)
         else if identifier_starts_declaration () then parse_decl_stmt ()
         else if starts_type_name name then parse_decl_stmt ()
         else parse_expr_stmt ()
     | Tok (_, _, TkPunct p) ->
         if bytes_eq_str p ";" then (p_advance (); SExpr (EInt (str_to_bytes "0")))
         else if bytes_eq_str p "{" then
           (let b = compound () in
            if !p_failed then p_dummy_stmt else SBlock b)
         else parse_expr_stmt ()
     | _ -> parse_expr_stmt ())

and parse_expr_stmt () =
  let e = p_expr () in
  if !p_failed then p_dummy_stmt
  else (need_punct ";"; SExpr e)

and parse_return () =
  if eat_punct ";" then SReturn None
  else
    (let e = p_expr () in
     if !p_failed then p_dummy_stmt
     else (need_punct ";"; SReturn (Some e)))

and parse_if () =
  need_punct "(";
  if !p_failed then p_dummy_stmt
  else
    (let cond = p_expr () in
     if !p_failed then p_dummy_stmt
     else
       (need_punct ")";
        let yes = stmt_as_block () in
        if !p_failed then p_dummy_stmt
        else
          (let has_else = eat_ident "else" in
           let no = if has_else then stmt_as_block () else [] in
           if !p_failed then p_dummy_stmt
           else SIf (cond, yes, no))))

and parse_while () =
  need_punct "(";
  if !p_failed then p_dummy_stmt
  else
    (let cond = p_expr () in
     if !p_failed then p_dummy_stmt
     else
       (need_punct ")";
        let body = stmt_as_block () in
        if !p_failed then p_dummy_stmt
        else SWhile (cond, body)))

and parse_do_while () =
  let body = stmt_as_block () in
  if !p_failed then p_dummy_stmt
  else
    (need_ident_value "while";
     need_punct "(";
     if !p_failed then p_dummy_stmt
     else
       (let cond = p_expr () in
        if !p_failed then p_dummy_stmt
        else
          (need_punct ")";
           need_punct ";";
           SDoWhile (body, cond))))

and parse_for () =
  need_punct "(";
  if !p_failed then p_dummy_stmt
  else
    (let init0 = optional_expr_until ";" in
     if !p_failed then p_dummy_stmt
     else
       (let cond = optional_expr_until ";" in
        if !p_failed then p_dummy_stmt
        else
          (let step = optional_expr_until ")" in
           if !p_failed then p_dummy_stmt
           else
             (let body = stmt_as_block () in
              if !p_failed then p_dummy_stmt
              else SFor (init0, cond, step, body)))))

and parse_switch () =
  need_punct "(";
  if !p_failed then p_dummy_stmt
  else
    (let v = p_expr () in
     if !p_failed then p_dummy_stmt
     else
       (need_punct ")";
        let body = stmt_as_block () in
        if !p_failed then p_dummy_stmt
        else SSwitch (v, body)))

and optional_expr_until punct =
  if eat_punct punct then None
  else
    (let e = p_expr () in
     if !p_failed then None
     else (need_punct punct; Some e))

and stmt_as_block () =
  let tok = p_peek () in
  if !p_failed then []
  else
    (match tok with
     | Tok (_, _, TkPunct p) ->
         if bytes_eq_str p "{" then
           (let b = compound () in
            if !p_failed then [] else [SBlock b])
         else stmt_as_block_single ()
     | _ -> stmt_as_block_single ())

and stmt_as_block_single () =
  let first = parse_stmt () in
  if !p_failed then []
  else
    (match first with
     | SLabel _ ->
         (let body = parse_stmt () in
          if !p_failed then [] else [first; body])
     | _ -> [first])

and parse_decl_stmt () =
  let ty0 = parse_ctype () in
  if !p_failed then p_dummy_stmt
  else if eat_punct ";" then SExpr (EInt (str_to_bytes "0"))
  else
    (* optionalP (tryP (localPrototype ty0)) *)
    (let save = p_save () in
     local_prototype ty0;
     if !p_failed then
       (p_restore save;
        p_failed := false;
        let first = declaration_item ty0 in
        if !p_failed then p_dummy_stmt
        else
          (let rest = declaration_items_tail ty0 in
           if !p_failed then p_dummy_stmt
           else
             (match first :: rest with
              | [(ty, name, init0)] -> SDecl (ty, name, init0)
              | items -> SDecls items)))
     else SExpr (EInt (str_to_bytes "0")))

and local_prototype ty0 =
  let _ty = pointer_stars ty0 in
  let _name = need_ident () in
  if !p_failed then ()
  else
    (need_punct "(";
     if !p_failed then ()
     else
       (skip_balanced_parens 1;
        if !p_failed then ()
        else
          (skip_attributes ();
           need_punct ";")))

and skip_balanced_parens depth =
  if depth <= 0 then ()
  else
    (let tok = p_peek () in
     if !p_failed then ()
     else
       (match tok with
        | Tok (_, _, TkPunct p) ->
            if bytes_eq_str p "(" then (p_advance (); skip_balanced_parens (depth + 1))
            else if bytes_eq_str p ")" then (p_advance (); skip_balanced_parens (depth - 1))
            else (p_advance (); skip_balanced_parens depth)
        | _ -> (p_advance (); skip_balanced_parens depth)))

and declaration_item ty0 =
  let (ty, name) = declarator ty0 in
  if !p_failed then (CVoid, p_dummy_bytes, None)
  else
    (skip_attributes ();
     let init0 = p_optional_initializer () in
     (ty, name, init0))

and declaration_items_tail ty0 =
  if eat_punct ";" then []
  else
    (need_punct ",";
     if !p_failed then []
     else
       (let item = declaration_item ty0 in
        if !p_failed then []
        else
          (let rest = declaration_items_tail ty0 in
           item :: rest)))

(* ---- types ---- *)

and parse_ctype () =
  skip_qualifiers ();
  if !p_failed then CVoid
  else
    (let ty = parse_base_type () in
     if !p_failed then CVoid
     else (skip_qualifiers (); ty))

and parse_base_type () =
  let tok = p_peek () in
  if !p_failed then CVoid
  else
    (match tok with
     | Tok (_, _, TkIdent name) ->
         if bytes_eq_str name "void" then (p_advance (); CVoid)
         else if bytes_eq_str name "_Bool" then (p_advance (); CBool)
         else if bytes_eq_str name "int" then (p_advance (); CInt)
         else if bytes_eq_str name "char" then (p_advance (); CChar)
         else if bytes_eq_str name "signed" then (p_advance (); signed_base_type ())
         else if bytes_eq_str name "unsigned" then (p_advance (); unsigned_base_type ())
         else if bytes_eq_str name "short" then (p_advance (); optional_kw "int" CShort)
         else if bytes_eq_str name "long" then (p_advance (); long_base_type ())
         else if bytes_eq_str name "float" then (p_advance (); CFloat)
         else if bytes_eq_str name "double" then (p_advance (); CDouble)
         else if bytes_eq_str name "struct" then aggregate_type false
         else if bytes_eq_str name "union" then aggregate_type true
         else if bytes_eq_str name "enum" then enum_type ()
         else
           (p_advance ();
            match lookup_parser_type name with
            | Some ty -> ty
            | None -> CNamed name)
     | _ -> (p_fail_tok_str tok "expected type"; CVoid))

and optional_kw kw ty = ((if eat_ident kw then () else ()); ty)

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
    (let fields = aggregate_fields_until_close () in
     if !p_failed then CVoid
     else if bytes_length name = 0 then
       (if is_union then CUnionDef fields else CStructDef fields)
     else
       (if is_union then CUnionNamed (name, fields) else CStructNamed (name, fields)))
  else (if is_union then CUnion name else CStruct name)

and enum_type () =
  p_advance ();
  let name = optional_ident () in
  if eat_punct "{" then
    (parse_enum_body 0;
     if !p_failed then CVoid else CEnum name)
  else CEnum name

and parse_enum_body next_value =
  if eat_punct "}" then ()
  else if eat_punct "," then parse_enum_body next_value
  else
    (let name = need_ident () in
     if !p_failed then ()
     else
       (let value = enum_value next_value in
        if !p_failed then ()
        else
          (bind_parser_constant name value;
           if eat_punct "," then
             (if eat_punct "}" then () else parse_enum_body (value + 1))
           else need_punct "}")))

and enum_value next_value =
  if eat_punct "=" then
    (let toks = take_enum_value_expr () in
     match parse_const_expr !p_consts toks with
     | Some (value, trailing) ->
         (let rec all_ignorable ts =
            match ts with
            | [] -> true
            | Tok (_, _, TkPunct p) :: rest ->
                if bytes_eq_str p ")" then all_ignorable rest else false
            | _ -> false in
          if all_ignorable trailing then value
          else
            (match trailing with
             | tok :: _ ->
                 (let b = buf_new 64 in
                  buf_add_str b "unexpected tokens in enum initializer: ";
                  buf_add_bytes b (token_text (tok_kind tok));
                  p_fail_tok tok (buf_take b);
                  0)
             | [] ->
                 (p_fail_tok_str (p_peek ()) "unexpected tokens in enum initializer"; 0)))
     | None ->
         (let b = buf_new 64 in
          buf_add_str b "invalid enum initializer: ";
          buf_add_bytes b !ce_err;
          p_fail_tok (p_peek ()) (buf_take b);
          0))
  else next_value

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
         p_fail_tok (p_peek ()) (buf_take b))
      else if is_storage_or_qualifier name then (p_advance (); skip_qualifiers ())
      else if bytes_eq_str name "__attribute__" || bytes_eq_str name "__extension__" then
        (skip_attributes (); skip_qualifiers ())
      else ()
  | _ -> ()

and skip_attributes () =
  match p_peek_maybe () with
  | Some (Tok (_, _, TkIdent name)) ->
      if bytes_eq_str name "__attribute__" then
        (p_advance ();
         (if eat_punct "(" then skip_balanced_parens 1);
         if !p_failed then () else skip_attributes ())
      else if bytes_eq_str name "__extension__" then
        (p_advance (); skip_attributes ())
      else ()
  | _ -> ()

and declarator ty0 =
  let ty = pointer_stars ty0 in
  direct_declarator ty

and direct_declarator ty =
  if eat_punct "(" then
    (let (inner_ty, name) = declarator ty in
     if !p_failed then (CVoid, p_dummy_bytes)
     else
       (need_punct ")";
        let ty2 = grouped_declarator_suffixes inner_ty in
        if !p_failed then (CVoid, p_dummy_bytes)
        else (skip_attributes (); (ty2, name))))
  else
    (let name = need_ident () in
     if !p_failed then (CVoid, p_dummy_bytes)
     else
       (let ty2 = array_suffixes ty in
        if !p_failed then (CVoid, p_dummy_bytes)
        else (skip_attributes (); (ty2, name))))

and grouped_declarator_suffixes ty =
  if eat_punct "(" then
    (let params = parameters () in
     if !p_failed then CVoid
     else grouped_declarator_suffixes (function_suffix_type ty params))
  else array_suffixes ty

and function_suffix_type ty params =
  match ty with
  | CPtr inner -> CPtr (CFunc (inner, param_types params))
  | _ -> CFunc (ty, param_types params)

and optional_function_suffix ty =
  if eat_punct "(" then
    (let params = parameters () in
     if !p_failed then CVoid
     else CFunc (ty, param_types params))
  else ty

and pointer_stars ty =
  if eat_punct "*" then
    (skip_qualifiers ();
     if !p_failed then CVoid
     else pointer_stars (CPtr ty))
  else ty

and array_suffixes ty =
  if eat_punct "[" then
    (* optionalP expr: empty bounds fail without consumption *)
    (let save = p_save () in
     let e = p_expr () in
     let bound =
       if !p_failed then
         (if !p_pos = snap_pos save then (p_restore save; p_failed := false; None)
          else None)
       else Some e in
     if !p_failed then CVoid
     else
       (need_punct "]";
        if !p_failed then CVoid
        else array_suffixes (CArray (ty, bound))))
  else ty

(* ---- expressions ---- *)

and p_expr () = expression 0

and assign_expr () = expression 1

and initializer_expr () =
  if eat_punct "{" then
    (let items = initializer_list () in
     if !p_failed then p_dummy_expr else EInitList items)
  else assign_expr ()

and initializer_list () =
  if eat_punct "}" then []
  else
    (let v = initializer_expr () in
     if !p_failed then []
     else if eat_punct "," then
       (if eat_punct "}" then [v]
        else
          (let rest = initializer_list () in
           v :: rest))
     else (need_punct "}"; [v]))

and expression minprec =
  let u = unary_expr () in
  if !p_failed then p_dummy_expr
  else
    (let lhs = parse_postfix u in
     if !p_failed then p_dummy_expr
     else expr_climb minprec lhs)

and expr_climb minprec lhs =
  match p_peek_maybe () with
  | None -> lhs
  | Some (Tok (_, _, TkPunct op)) ->
      if bytes_eq_str op "?" && minprec <= 2 then
        (p_advance ();
         let yes = p_expr () in
         if !p_failed then p_dummy_expr
         else
           (need_punct ":";
            let no = expression 2 in
            if !p_failed then p_dummy_expr
            else expr_climb minprec (ECond (lhs, yes, no))))
      else
        (let prec = binop_prec op in
         if prec >= 0 && prec >= minprec then
           (p_advance ();
            let rhs = expression (if binop_right_assoc op then prec else prec + 1) in
            if !p_failed then p_dummy_expr
            else expr_climb minprec (assign_node op lhs rhs))
         else lhs)
  | Some _ -> lhs

and assign_node op lhs rhs =
  if bytes_eq_str op "=" then EAssign (lhs, rhs)
  else if bytes_eq_str op "+=" then ECompoundAssign (str_to_bytes "+", lhs, rhs)
  else if bytes_eq_str op "-=" then ECompoundAssign (str_to_bytes "-", lhs, rhs)
  else if bytes_eq_str op "*=" then ECompoundAssign (str_to_bytes "*", lhs, rhs)
  else if bytes_eq_str op "/=" then ECompoundAssign (str_to_bytes "/", lhs, rhs)
  else if bytes_eq_str op "%=" then ECompoundAssign (str_to_bytes "%", lhs, rhs)
  else if bytes_eq_str op "<<=" then ECompoundAssign (str_to_bytes "<<", lhs, rhs)
  else if bytes_eq_str op ">>=" then ECompoundAssign (str_to_bytes ">>", lhs, rhs)
  else if bytes_eq_str op "&=" then ECompoundAssign (str_to_bytes "&", lhs, rhs)
  else if bytes_eq_str op "^=" then ECompoundAssign (str_to_bytes "^", lhs, rhs)
  else if bytes_eq_str op "|=" then ECompoundAssign (str_to_bytes "|", lhs, rhs)
  else EBinary (op, lhs, rhs)

and unary_expr () =
  let tok = p_peek () in
  if !p_failed then p_dummy_expr
  else
    (match tok with
     | Tok (_, _, TkPunct op) ->
         if bytes_eq_str op "++" || bytes_eq_str op "--" ||
            bytes_eq_str op "+" || bytes_eq_str op "-" ||
            bytes_eq_str op "!" || bytes_eq_str op "~" ||
            bytes_eq_str op "*" || bytes_eq_str op "&" then
           (p_advance ();
            let inner = unary_expr () in
            if !p_failed then p_dummy_expr
            else
              (let inner2 = parse_postfix inner in
               if !p_failed then p_dummy_expr
               else EUnary (op, inner2)))
         else if bytes_eq_str op "(" then
           (p_advance ();
            let is_cast =
              (match p_peek_maybe () with
               | Some t -> token_starts_type t
               | None -> false) in
            if is_cast then
              (let ty = type_name () in
               if !p_failed then p_dummy_expr
               else
                 (need_punct ")";
                  let inner = unary_expr () in
                  if !p_failed then p_dummy_expr
                  else
                    (let inner2 = parse_postfix inner in
                     if !p_failed then p_dummy_expr
                     else ECast (ty, inner2))))
            else
              (let e = p_expr () in
               if !p_failed then p_dummy_expr
               else (need_punct ")"; e)))
         else (p_fail_tok_str tok "expected expression"; p_dummy_expr)
     | Tok (_, _, TkIdent s) ->
         if bytes_eq_str s "sizeof" then (p_advance (); parse_sizeof ())
         else
           (p_advance ();
            match lookup_parser_constant s with
            | Some value -> EInt (int_to_bytes value)
            | None -> EVar s)
     | Tok (_, _, TkInt s) -> (p_advance (); EInt s)
     | Tok (_, _, TkFloat s) -> (p_advance (); EFloat s)
     | Tok (_, _, TkChar s) -> (p_advance (); EChar s)
     | Tok (_, _, TkString _) ->
         (let s = string_literal () in
          if !p_failed then p_dummy_expr else EString s)
     | _ -> (p_fail_tok_str tok "expected expression"; p_dummy_expr))

and type_name () =
  let ty = parse_ctype () in
  if !p_failed then CVoid else pointer_stars ty

and parse_sizeof () =
  if eat_punct "(" then sizeof_paren ()
  else
    (let inner = unary_expr () in
     if !p_failed then p_dummy_expr
     else
       (let inner2 = parse_postfix inner in
        if !p_failed then p_dummy_expr
        else ESizeofExpr inner2))

and sizeof_paren () =
  let starts =
    (match p_peek_maybe () with
     | Some t -> token_starts_type t
     | None -> false) in
  if starts then
    (* speculative: typeName ")" with no postfix continuation *)
    (let save = p_save () in
     let ty = type_name () in
     if not !p_failed then
       (need_punct ")";
        if not !p_failed && not (postfix_continues ()) then ESizeofType ty
        else (p_restore save; p_failed := false; sizeof_paren_expr ()))
     else (p_restore save; p_failed := false; sizeof_paren_expr ()))
  else sizeof_paren_expr ()

and sizeof_paren_expr () =
  let v = p_expr () in
  if !p_failed then p_dummy_expr
  else
    (need_punct ")";
     let v2 = parse_postfix v in
     if !p_failed then p_dummy_expr
     else ESizeofExpr v2)

and postfix_continues () =
  match p_peek_maybe () with
  | Some (Tok (_, _, TkPunct p)) ->
      bytes_eq_str p "(" || bytes_eq_str p "[" || bytes_eq_str p "." ||
      bytes_eq_str p "->" || bytes_eq_str p "++" || bytes_eq_str p "--"
  | _ -> false

and parse_postfix base =
  match p_peek_maybe () with
  | Some (Tok (_, _, TkPunct p)) ->
      if bytes_eq_str p "(" then
        (p_advance ();
         let args = call_arguments () in
         if !p_failed then p_dummy_expr
         else parse_postfix (ECall (base, args)))
      else if bytes_eq_str p "[" then
        (p_advance ();
         let ix = p_expr () in
         if !p_failed then p_dummy_expr
         else
           (need_punct "]";
            parse_postfix (EIndex (base, ix))))
      else if bytes_eq_str p "." then
        (p_advance ();
         let name = need_ident () in
         if !p_failed then p_dummy_expr
         else parse_postfix (EMember (base, name)))
      else if bytes_eq_str p "->" then
        (p_advance ();
         let name = need_ident () in
         if !p_failed then p_dummy_expr
         else parse_postfix (EPtrMember (base, name)))
      else if bytes_eq_str p "++" then
        (p_advance (); parse_postfix (EPostfix (str_to_bytes "++", base)))
      else if bytes_eq_str p "--" then
        (p_advance (); parse_postfix (EPostfix (str_to_bytes "--", base)))
      else base
  | _ -> base

and call_arguments () =
  if eat_punct ")" then []
  else
    (let first = assign_expr () in
     if !p_failed then []
     else
       (let rest = p_many_comma_args () in
        if !p_failed then []
        else (need_punct ")"; first :: rest)))

and p_many_comma_args () =
  let save = p_save () in
  need_punct ",";
  if !p_failed then
    (if !p_pos = snap_pos save then (p_restore save; p_failed := false; [])
     else [])
  else
    (let a = assign_expr () in
     if !p_failed then []
     else
       (let rest = p_many_comma_args () in
        a :: rest))

(* adjacent string literals are concatenated; the result re-encodes every
   content byte as a hex escape *)
and string_literal () =
  let first = need_string () in
  if !p_failed then p_dummy_bytes
  else
    (let rest = p_many_strings () in
     join_strings (first :: rest))

and p_many_strings () =
  match p_peek_maybe () with
  | Some (Tok (_, _, TkString s)) ->
      (p_advance ();
       let rest = p_many_strings () in
       s :: rest)
  | _ -> []

and need_string () =
  let tok = p_peek () in
  match tok with
  | Tok (_, _, TkString s) -> (p_advance (); s)
  | _ -> (p_fail_tok_str tok "expected string literal"; p_dummy_bytes)

and join_strings strings =
  let out = buf_new 64 in
  buf_push out 34;
  let one s =
    (* decoded content bytes minus the trailing NUL *)
    let bs = string_bytes s in
    let rec emit l =
      match l with
      | [] -> ()
      | [_] -> ()   (* drop terminator *)
      | b :: rest ->
          (buf_push out 92;
           buf_push out 120;
           let h1 = hdiv b 16 in
           let h2 = hmod b 16 in
           buf_push out (if h1 < 10 then 48 + h1 else 97 + h1 - 10);
           buf_push out (if h2 < 10 then 48 + h2 else 97 + h2 - 10);
           emit rest) in
    emit bs in
  let rec go l =
    match l with
    | [] -> ()
    | s :: rest -> (one s; go rest) in
  go strings;
  buf_push out 34;
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
  let rec fill l i =
    match l with
    | [] -> ()
    | t :: rest -> (array_set arr i t; fill rest (i + 1)) in
  fill toks 0;
  p_toks := arr;
  p_ntoks := n;
  p_pos := 0;
  p_types := scope_empty;
  p_constmap := SymE;
  p_consts := [];
  (* builtin type aliases, inserted in list order *)
  bind_parser_type (str_to_bytes "FILE") (CStruct (str_to_bytes "FILE"));
  bind_parser_type (str_to_bytes "FUNCTION") CLong;
  bind_parser_type (str_to_bytes "size_t") (CNamed (str_to_bytes "size_t"));
  bind_parser_type (str_to_bytes "ssize_t") (CNamed (str_to_bytes "ssize_t"));
  bind_parser_type (str_to_bytes "time_t") (CNamed (str_to_bytes "time_t"));
  bind_parser_type (str_to_bytes "ptrdiff_t") (CNamed (str_to_bytes "ptrdiff_t"));
  bind_parser_type (str_to_bytes "intptr_t") (CNamed (str_to_bytes "intptr_t"));
  bind_parser_type (str_to_bytes "uintptr_t") (CNamed (str_to_bytes "uintptr_t"));
  bind_parser_type (str_to_bytes "int8_t") (CNamed (str_to_bytes "int8_t"));
  bind_parser_type (str_to_bytes "int16_t") (CNamed (str_to_bytes "int16_t"));
  bind_parser_type (str_to_bytes "int32_t") (CNamed (str_to_bytes "int32_t"));
  bind_parser_type (str_to_bytes "int64_t") (CNamed (str_to_bytes "int64_t"));
  bind_parser_type (str_to_bytes "uint8_t") (CNamed (str_to_bytes "uint8_t"));
  bind_parser_type (str_to_bytes "uint16_t") (CNamed (str_to_bytes "uint16_t"));
  bind_parser_type (str_to_bytes "uint32_t") (CNamed (str_to_bytes "uint32_t"));
  bind_parser_type (str_to_bytes "uint64_t") (CNamed (str_to_bytes "uint64_t"));
  bind_parser_type (str_to_bytes "va_list") (CPtr CVoid);
  bind_parser_type (str_to_bytes "__builtin_va_list") (CPtr CVoid);
  bind_parser_type (str_to_bytes "jmp_buf") (CPtr CVoid);
  p_failed := false;
  let decls = parse_program_decls () in
  if !p_failed then None
  else if !p_pos < !p_ntoks then
    (p_fail_tok_str (array_get !p_toks !p_pos) "trailing tokens"; None)
  else Some decls

(* render the recorded parse error like showPos ++ ": " ++ msg *)
let parse_error_render () =
  let b = buf_new 64 in
  buf_add_int b !p_eline;
  buf_push b 58;
  buf_add_int b !p_ecol;
  buf_add_str b ": ";
  buf_add_bytes b !p_emsg;
  buf_take b
