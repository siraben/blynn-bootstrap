(* ccc part 45: lowering helpers; ports of Hcc.LowerBuiltins,
   Hcc.LowerDataValues, Hcc.LowerLiterals, Hcc.LowerParams,
   Hcc.LowerTypeInfo, Hcc.LowerSwitchHelpers, Hcc.LowerImplicit and
   Hcc.LowerBootstrap. These call only the foundation and each other;
   they precede the 50-/52-/54-/56- Lower group. *)

(* ---- Hcc.LowerBuiltins ---- *)

let builtin_constant name =
  if bytes_eq_str name "NULL" then Some 0
  else if bytes_eq_str name "__null" then Some 0
  else if bytes_eq_str name "__LINE__" then Some 0
  else if bytes_eq_str name "char" then Some 1
  else if bytes_eq_str name "short" then Some 2
  else if bytes_eq_str name "int" then Some 4
  else if bytes_eq_str name "long" then Some 8
  else None

let is_ignored_side_effect_call name =
  if bytes_eq_str name "asm" then true
  else if bytes_eq_str name "oputs" then true
  else if bytes_eq_str name "eputs" then true
  else false

let is_signed_named_integer name =
  if bytes_eq_str name "signed_short" then true
  else if bytes_eq_str name "int8_t" then true
  else if bytes_eq_str name "int16_t" then true
  else if bytes_eq_str name "int32_t" then true
  else if bytes_eq_str name "int64_t" then true
  else if bytes_eq_str name "ssize_t" then true
  else if bytes_eq_str name "time_t" then true
  else if bytes_eq_str name "ptrdiff_t" then true
  else if bytes_eq_str name "intptr_t" then true
  else if bytes_eq_str name "Elf32_Sword" then true
  else if bytes_eq_str name "Elf64_Sword" then true
  else if bytes_eq_str name "Elf32_Sxword" then true
  else if bytes_eq_str name "Elf64_Sxword" then true
  else false

let named_integer_size name =
  if bytes_eq_str name "int8_t" then Some 1
  else if bytes_eq_str name "uint8_t" then Some 1
  else if bytes_eq_str name "signed_short" then Some 2
  else if bytes_eq_str name "unsigned_short" then Some 2
  else if bytes_eq_str name "int16_t" then Some 2
  else if bytes_eq_str name "uint16_t" then Some 2
  else if bytes_eq_str name "Elf32_Half" then Some 2
  else if bytes_eq_str name "Elf64_Half" then Some 2
  else if bytes_eq_str name "Elf32_Section" then Some 2
  else if bytes_eq_str name "Elf64_Section" then Some 2
  else if bytes_eq_str name "Elf32_Versym" then Some 2
  else if bytes_eq_str name "Elf64_Versym" then Some 2
  else if bytes_eq_str name "int32_t" then Some 4
  else if bytes_eq_str name "uint32_t" then Some 4
  else if bytes_eq_str name "Elf32_Word" then Some 4
  else if bytes_eq_str name "Elf64_Word" then Some 4
  else if bytes_eq_str name "Elf32_Sword" then Some 4
  else if bytes_eq_str name "Elf64_Sword" then Some 4
  else if bytes_eq_str name "Elf32_Addr" then Some 4
  else if bytes_eq_str name "Elf32_Off" then Some 4
  else if bytes_eq_str name "unsigned_long" then Some 8
  else if bytes_eq_str name "int64_t" then Some 8
  else if bytes_eq_str name "uint64_t" then Some 8
  else if bytes_eq_str name "size_t" then Some 8
  else if bytes_eq_str name "ssize_t" then Some 8
  else if bytes_eq_str name "time_t" then Some 8
  else if bytes_eq_str name "ptrdiff_t" then Some 8
  else if bytes_eq_str name "intptr_t" then Some 8
  else if bytes_eq_str name "uintptr_t" then Some 8
  else if bytes_eq_str name "addr_t" then Some 8
  else if bytes_eq_str name "Elf32_Xword" then Some 8
  else if bytes_eq_str name "Elf32_Sxword" then Some 8
  else if bytes_eq_str name "Elf64_Xword" then Some 8
  else if bytes_eq_str name "Elf64_Sxword" then Some 8
  else if bytes_eq_str name "Elf64_Addr" then Some 8
  else if bytes_eq_str name "Elf64_Off" then Some 8
  else None

(* ---- Hcc.LowerDataValues ---- *)

let rec zero_data n = if n <= 0 then [] else DByte 0 :: zero_data (n - 1)

let rec bytes_data values =
  match values with
  | [] -> []
  | byte :: rest -> DByte byte :: bytes_data rest

(* ---- Hcc.LowerLiterals ---- *)

let const_bin_op op a b =
  match eval_const_binop op a b with
  | Some v -> v
  | None -> 0

let exceeds_signed_int bytes =
  match bytes with
  | _ :: _ :: _ :: b3 :: b4 :: b5 :: b6 :: b7 :: _ ->
      b4 <> 0 || b5 <> 0 || b6 <> 0 || b7 <> 0 || b3 >= 128
  | _ -> false

let parse_int_bytes text =
  let bytes =
    natural_literal_bytes (bytes_sub text 0 (strip_int_suffix_end text)) in
  if exceeds_signed_int bytes then Some bytes else None

let int_const_operand text =
  match parse_int_bytes text with
  | Some bytes -> OImmBytes bytes
  | None -> OImm (parse_int text)

let float_const_operand text =
  OImmBytes (float_literal_bytes (float_literal_size text) text)

let lower_bin_op op =
  if bytes_eq_str op "+" then Some irop_add
  else if bytes_eq_str op "-" then Some irop_sub
  else if bytes_eq_str op "*" then Some irop_mul
  else if bytes_eq_str op "/" then Some irop_div
  else if bytes_eq_str op "%" then Some irop_mod
  else if bytes_eq_str op "<<" then Some irop_shl
  else if bytes_eq_str op ">>" then Some irop_shr
  else if bytes_eq_str op "==" then Some irop_eq
  else if bytes_eq_str op "!=" then Some irop_ne
  else if bytes_eq_str op "&" then Some irop_and
  else if bytes_eq_str op "|" then Some irop_or
  else if bytes_eq_str op "^" then Some irop_xor
  else if bytes_eq_str op "&&" then Some irop_and
  else if bytes_eq_str op "||" then Some irop_or
  else None

(* ---- Hcc.LowerParams ---- *)

let rec lower_params index params =
  match params with
  | [] -> []
  | Param (ty, name) :: rest ->
      let temp = fresh_temp () in
      bind_var name temp ty;
      let instrs = lower_params (index + 1) rest in
      IParam (temp, index) :: instrs

(* ---- Hcc.LowerTypeInfo ---- *)

let aggregate_fields ty =
  match ty with
  | CStructDef fields -> Some (false, fields)
  | CUnionDef fields -> Some (true, fields)
  | CStructNamed (name, fields) ->
      (bind_struct name false fields;
       Some (false, fields))
  | CUnionNamed (name, fields) ->
      (bind_struct name true fields;
       Some (true, fields))
  | CStruct name -> lookup_struct name
  | CUnion name -> lookup_struct name
  | CNamed name -> lookup_struct name
  | _ -> None

let is_aggregate_type ty =
  match ty with
  | CArray (_, _) -> true
  | CStruct _ -> true
  | CUnion _ -> true
  | CStructNamed (_, _) -> true
  | CUnionNamed (_, _) -> true
  | CStructDef _ -> true
  | CUnionDef _ -> true
  | _ -> false

let is_pointer_type ty =
  match ty with
  | CPtr _ -> true
  | CNamed name -> bytes_eq_str name "intptr_t" || bytes_eq_str name "uintptr_t"
  | _ -> false

(* ---- Hcc.LowerSwitchHelpers ---- *)

(* current_label : expr option option — None means "before the first
   case/default", Some None is a default label, Some (Some e) a case *)
let collect_switch_clause_finish_one current_label current_body clauses =
  match current_label with
  | None -> clauses
  | Some label -> SwitchClause (label, list_rev current_body) :: clauses

let rec collect_switch_clauses_finish current_label current_body clauses stmts =
  match stmts with
  | [] -> collect_switch_clause_finish_one current_label current_body clauses
  | stmt :: rest ->
      (match stmt with
       | SCase expr ->
           collect_switch_clauses_finish (Some (Some expr)) []
             (collect_switch_clause_finish_one current_label current_body clauses)
             rest
       | SDefault ->
           collect_switch_clauses_finish (Some None) []
             (collect_switch_clause_finish_one current_label current_body clauses)
             rest
       | _ ->
           (match current_label with
            | None ->
                collect_switch_clauses_finish current_label current_body clauses rest
            | Some _ ->
                collect_switch_clauses_finish current_label (stmt :: current_body)
                  clauses rest))

let collect_switch_clauses stmts =
  list_rev (collect_switch_clauses_finish None [] [] stmts)

let rec fresh_blocks count =
  if count <= 0 then []
  else
    (let first = fresh_block () in
     let rest = fresh_blocks (count - 1) in
     first :: rest)

let rec switch_default_target rest_id clauses =
  match clauses with
  | [] -> rest_id
  | pair :: rest ->
      (match pair with
       | (SwitchClause (label, _), bid) ->
           (match label with
            | None -> bid
            | Some _ -> switch_default_target rest_id rest))

let rec switch_cases clauses =
  match clauses with
  | [] -> []
  | pair :: rest ->
      (match pair with
       | (SwitchClause (label, _), bid) ->
           (match label with
            | Some value -> (value, bid) :: switch_cases rest
            | None -> switch_cases rest))

let switch_next_dispatch_target default_target tail_cases =
  match tail_cases with
  | [] -> default_target
  | _ -> fresh_block ()

let switch_fallthrough_target rest_id clauses =
  match clauses with
  | [] -> rest_id
  | pair :: _ ->
      (match pair with
       | (_, next_id) -> next_id)

(* ---- Hcc.LowerImplicit ---- *)

let switch_body_statements body =
  match body with
  | [SBlock stmts] -> stmts
  | _ -> body

(* Haskell elem on a list of byte strings *)
let rec lh_member_bytes name names =
  match names with
  | [] -> false
  | n :: rest -> if bytes_eq n name then true else lh_member_bytes name rest

(* the foldM over statements is inlined into register_implicit_calls *)
let rec register_implicit_calls locals stmts =
  match stmts with
  | [] -> ()
  | stmt :: rest ->
      let locals2 = register_implicit_calls_stmt locals stmt in
      register_implicit_calls locals2 rest

and register_implicit_calls_stmt locals stmt =
  match stmt with
  | SDecl (_, name, init_expr) ->
      (maybe_register_implicit_calls_expr locals init_expr;
       name :: locals)
  | SDecls decls -> register_implicit_calls_decls locals decls
  | SReturn expr -> (maybe_register_implicit_calls_expr locals expr; locals)
  | SExpr expr -> (register_implicit_calls_expr locals expr; locals)
  | SIf (cond, yes, no) ->
      (register_implicit_calls_expr locals cond;
       register_implicit_calls locals yes;
       register_implicit_calls locals no;
       locals)
  | SWhile (cond, body) ->
      (register_implicit_calls_expr locals cond;
       register_implicit_calls locals body;
       locals)
  | SDoWhile (body, cond) ->
      (register_implicit_calls locals body;
       register_implicit_calls_expr locals cond;
       locals)
  | SFor (init_expr, cond_expr, step_expr, body) ->
      (maybe_register_implicit_calls_expr locals init_expr;
       maybe_register_implicit_calls_expr locals cond_expr;
       maybe_register_implicit_calls_expr locals step_expr;
       register_implicit_calls locals body;
       locals)
  | SSwitch (value, body) ->
      (register_implicit_calls_expr locals value;
       register_implicit_calls locals (switch_body_statements body);
       locals)
  | SCase expr -> (register_implicit_calls_expr locals expr; locals)
  | SBlock body -> (register_implicit_calls locals body; locals)
  | _ -> locals

and register_implicit_calls_decls locals decls =
  match decls with
  | [] -> locals
  | decl :: rest ->
      (match decl with
       | (_, name, init_expr) ->
           (maybe_register_implicit_calls_expr locals init_expr;
            register_implicit_calls_decls (name :: locals) rest))

and maybe_register_implicit_calls_expr locals expr =
  match expr with
  | None -> ()
  | Some value -> register_implicit_calls_expr locals value

and register_implicit_calls_expr locals expr =
  match expr with
  | ECall (EVar name, args) ->
      ((if lh_member_bytes name locals || is_ignored_side_effect_call name then ()
        else
          (match lookup_global_type name with
           | Some _ -> ()
           | None -> bind_function name));
       register_implicit_calls_exprs locals args)
  | ECall (callee, args) ->
      (register_implicit_calls_expr locals callee;
       register_implicit_calls_exprs locals args)
  | EIndex (base, ix) ->
      (register_implicit_calls_expr locals base;
       register_implicit_calls_expr locals ix)
  | EMember (base, _) -> register_implicit_calls_expr locals base
  | EPtrMember (base, _) -> register_implicit_calls_expr locals base
  | EUnary (_, value) -> register_implicit_calls_expr locals value
  | ESizeofExpr value -> register_implicit_calls_expr locals value
  | ECast (_, value) -> register_implicit_calls_expr locals value
  | EPostfix (_, value) -> register_implicit_calls_expr locals value
  | EBinary (_, left, right) ->
      (register_implicit_calls_expr locals left;
       register_implicit_calls_expr locals right)
  | ECond (cond, yes, no) ->
      (register_implicit_calls_expr locals cond;
       register_implicit_calls_expr locals yes;
       register_implicit_calls_expr locals no)
  | EAssign (left, right) ->
      (register_implicit_calls_expr locals left;
       register_implicit_calls_expr locals right)
  | ECompoundAssign (_, left, right) ->
      (register_implicit_calls_expr locals left;
       register_implicit_calls_expr locals right)
  | _ -> ()

and register_implicit_calls_exprs locals exprs =
  match exprs with
  | [] -> ()
  | e :: rest ->
      (register_implicit_calls_expr locals e;
       register_implicit_calls_exprs locals rest)

(* ---- Hcc.LowerBootstrap ---- *)

let tm_fields =
  [Field (CInt, str_to_bytes "tm_sec");
   Field (CInt, str_to_bytes "tm_min");
   Field (CInt, str_to_bytes "tm_hour");
   Field (CInt, str_to_bytes "tm_mday");
   Field (CInt, str_to_bytes "tm_mon");
   Field (CInt, str_to_bytes "tm_year");
   Field (CInt, str_to_bytes "tm_wday");
   Field (CInt, str_to_bytes "tm_yday");
   Field (CInt, str_to_bytes "tm_isdst")]

let timeval_fields =
  [Field (CLong, str_to_bytes "tv_sec");
   Field (CLong, str_to_bytes "tv_usec")]

let file_struct_fields =
  [Field (CInt, str_to_bytes "fd");
   Field (CInt, str_to_bytes "bufmode");
   Field (CInt, str_to_bytes "bufpos");
   Field (CInt, str_to_bytes "file_pos");
   Field (CInt, str_to_bytes "buflen");
   Field (CPtr CChar, str_to_bytes "buffer");
   Field (CPtr (CStruct (str_to_bytes "__IO_FILE")), str_to_bytes "next");
   Field (CPtr (CStruct (str_to_bytes "__IO_FILE")), str_to_bytes "prev")]

let register_builtin_structs () =
  bind_struct (str_to_bytes "tm") false tm_fields;
  bind_struct (str_to_bytes "timeval") false timeval_fields;
  bind_struct (str_to_bytes "__IO_FILE") false file_struct_fields;
  bind_struct (str_to_bytes "FILE") false file_struct_fields
