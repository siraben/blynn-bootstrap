(* ccc part 40: IR types and the compile state; port of Hcc.TypesIr,
   Hcc.TypesLower and Hcc.CompileM. The CompileM state monad becomes a
   set of global refs; CompileError becomes a fatal diagnostic carrying
   the withErrorContext stack. Temps and block ids are plain ints. *)

(* binary operators carry their HCCIR code directly *)
let irop_add = 1
let irop_sub = 2
let irop_mul = 3
let irop_div = 4
let irop_mod = 5
let irop_shl = 6
let irop_shr = 7
let irop_sar = 8
let irop_eq = 9
let irop_ne = 10
let irop_lt = 11
let irop_le = 12
let irop_gt = 13
let irop_ge = 14
let irop_ult = 15
let irop_ule = 16
let irop_ugt = 17
let irop_uge = 18
let irop_and = 19
let irop_or = 20
let irop_xor = 21
let irop_udiv = 22
let irop_umod = 23

type operand =
  | OTemp of int
  | OImm of int
  | OImmBytes of int list
  | OGlobal of bytes
  | OFunction of bytes

type instr =
  | IParam of int * int
  | IAlloca of int * int
  | IConst of int * int
  | IConstBytes of int * int list
  | ICopy of int * operand
  | IAddrOf of int * int
  | ILoad64 of int * operand
  | ILoad32 of int * operand
  | ILoadS32 of int * operand
  | ILoad16 of int * operand
  | ILoadS16 of int * operand
  | ILoad8 of int * operand
  | ILoadS8 of int * operand
  | IStore64 of operand * operand
  | IStore32 of operand * operand
  | IStore16 of operand * operand
  | IStore8 of operand * operand
  | ISExt of int * int * operand
  | IZExt of int * int * operand
  | ITrunc of int * int * operand
  | IBin of int * int * operand * operand
  | ICond of int * instr list * operand * instr list * operand * instr list * operand
  | ICall of int option * bytes * operand list
  | ICallIndirect of int option * operand * operand list

type terminator =
  | TRet of operand option
  | TJump of int
  | TBranch of operand * int * int
  | TBranchCmp of int * operand * operand * int * int

type basicblock = BasicBlock of int * instr list * terminator

type datavalue =
  | DByte of int
  | DAddress of bytes

type dataitem = DataItem of bytes * datavalue list

type functionir = FunctionIr of bytes * basicblock list

type topitemir =
  | TopData of dataitem
  | TopFunction of functionir

(* lvalues and switch clauses (Hcc.TypesLower) *)
type lvalue =
  | LLocal of int * ctype
  | LAddress of operand * ctype

type switchclause = SwitchClause of expr option * stmt list

(* ---- compile state ---- *)

let cs_next_temp = ref 0
let cs_next_block = ref 0
let cs_next_label = ref 0
let cs_data_prefix = ref (str_to_bytes "HCC_DATA")
let cs_vars = ref scope_empty                    (* (temp, ctype) scopemap *)
let cs_structs = ref SymE                        (* (bool * field list) *)
let cs_struct_sizes = ref SymE                   (* int *)
let cs_struct_members = ref SymE                 (* (ctype * int) symtree *)
let cs_globals = ref SymE                        (* ctype *)
let cs_constants = ref SymE                      (* int *)
let cs_functions = ref SymE                      (* bool, used as a set *)
let cs_function_types = ref SymE                 (* ctype *)
let cs_labels = ref SymE                         (* block id *)
let cs_data_items = ref []                       (* dataitem list, newest first *)
let cs_break_targets = ref []
let cs_continue_targets = ref []
let cs_target_bits = ref 64
let cs_current_function = ref None               (* bytes option *)

(* error context stack, outermost last *)
let cc_contexts = ref []

let cc_throw msg =
  let rec emit ctxs =
    match ctxs with
    | [] -> ()
    | c :: rest -> (emit rest; err_bytes c; err_str ": ") in
  err_str "ccc: ";
  emit !cc_contexts;
  err_bytes msg;
  write_byte 2 10;
  exit 1

let cc_throw_str msg = cc_throw (str_to_bytes msg)

let with_error_context ctx action =
  cc_contexts := ctx :: !cc_contexts;
  let v = action () in
  (match !cc_contexts with
   | [] -> ()
   | _ :: rest -> cc_contexts := rest);
  v

let fresh_temp () =
  let n = !cs_next_temp in
  cs_next_temp := n + 1;
  n

let fresh_block () =
  let n = !cs_next_block in
  cs_next_block := n + 1;
  n

let fresh_label () =
  let n = !cs_next_label in
  cs_next_label := n + 1;
  let b = buf_new 8 in
  buf_push b 76;   (* L *)
  buf_add_int b n;
  buf_take b

let fresh_data_label () =
  let l = fresh_label () in
  let b = buf_new 32 in
  buf_add_bytes b !cs_data_prefix;
  buf_push b 95;   (* _ *)
  buf_add_bytes b l;
  buf_take b

let add_data_item item =
  let label = (match item with DataItem (l, _) -> l) in
  let rec remove items =
    match items with
    | [] -> []
    | DataItem (l2, vs) :: rest ->
        if bytes_eq l2 label then remove rest
        else DataItem (l2, vs) :: remove rest in
  cs_data_items := item :: remove !cs_data_items

let bind_var name temp ty = cs_vars := scope_insert name (temp, ty) !cs_vars

let bind_struct name is_union fields =
  cs_structs := sym_insert name (is_union, fields) !cs_structs;
  cs_struct_sizes := sym_delete name !cs_struct_sizes;
  cs_struct_members := sym_delete name !cs_struct_members

let bytes_prefix_of prefix b =
  let np = bytes_length prefix in
  if bytes_length b < np then false
  else
    (let rec go i =
       if i >= np then true
       else if bytes_get b i = bytes_get prefix i then go (i + 1)
       else false in
     go 0)

let reject_reserved_symbol kind name =
  if bytes_prefix_of (str_to_bytes "FUNCTION_") name ||
     bytes_prefix_of (str_to_bytes "HCC_DATA_") name then
    (let b = buf_new 64 in
     buf_add_str b kind;
     buf_add_str b " name ";
     buf_add_bytes b (show_quoted name);
     buf_add_str b " uses a reserved HCC label prefix";
     cc_throw (buf_take b))

let bind_global name ty =
  reject_reserved_symbol "global" name;
  cs_globals := sym_insert name ty !cs_globals

let bind_constant name value = cs_constants := sym_insert name value !cs_constants

let bind_function name =
  reject_reserved_symbol "function" name;
  cs_functions := sym_insert name true !cs_functions

let bind_function_type name ret_ty params =
  reject_reserved_symbol "function" name;
  cs_functions := sym_insert name true !cs_functions;
  cs_function_types :=
    sym_insert name (CFunc (ret_ty, param_types params)) !cs_function_types

let lookup_var_maybe name =
  match scope_lookup name !cs_vars with
  | Some (t, _) -> Some t
  | None -> None

let lookup_var_type name =
  match scope_lookup name !cs_vars with
  | Some (_, ty) -> Some ty
  | None -> None

let lookup_global_type name = sym_lookup name !cs_globals
let lookup_constant name = sym_lookup name !cs_constants
let lookup_function name = sym_member name !cs_functions
let lookup_function_type name = sym_lookup name !cs_function_types
let lookup_struct name = sym_lookup name !cs_structs
let lookup_struct_size_cache name = sym_lookup name !cs_struct_sizes
let cache_struct_size name size = cs_struct_sizes := sym_insert name size !cs_struct_sizes

let lookup_struct_member_cache struct_name field_name =
  match sym_lookup struct_name !cs_struct_members with
  | None -> None
  | Some members -> sym_lookup field_name members

let cache_struct_member struct_name field_name info =
  let members = opt_or (sym_lookup struct_name !cs_struct_members) SymE in
  cs_struct_members :=
    sym_insert struct_name (sym_insert field_name info members) !cs_struct_members

let target_word_size () = if !cs_target_bits = 32 then 4 else 8

let current_function_name () = !cs_current_function

let with_current_function name action =
  let saved = !cs_current_function in
  cs_current_function := Some name;
  let v = action () in
  cs_current_function := saved;
  v

let current_return_type () =
  match !cs_current_function with
  | None -> None
  | Some name ->
      (match lookup_function_type name with
       | Some (CFunc (ret_ty, _)) -> Some ret_ty
       | _ -> None)

let with_function_scope action =
  let saved_vars = !cs_vars in
  let saved_labels = !cs_labels in
  let saved_breaks = !cs_break_targets in
  let saved_conts = !cs_continue_targets in
  cs_vars := scope_empty;
  cs_labels := SymE;
  cs_break_targets := [];
  cs_continue_targets := [];
  let v = action () in
  cs_vars := saved_vars;
  cs_labels := saved_labels;
  cs_break_targets := saved_breaks;
  cs_continue_targets := saved_conts;
  v

let with_var_scope action =
  cs_vars := scope_enter !cs_vars;
  let v = action () in
  cs_vars := scope_leave !cs_vars;
  v

let with_loop_targets break_t cont_t action =
  let saved_b = !cs_break_targets in
  let saved_c = !cs_continue_targets in
  cs_break_targets := break_t :: saved_b;
  cs_continue_targets := cont_t :: saved_c;
  let v = action () in
  cs_break_targets := saved_b;
  cs_continue_targets := saved_c;
  v

let with_break_target break_t action =
  let saved_b = !cs_break_targets in
  cs_break_targets := break_t :: saved_b;
  let v = action () in
  cs_break_targets := saved_b;
  v

let current_break_target () =
  match !cs_break_targets with
  | [] -> None
  | x :: _ -> Some x

let current_continue_target () =
  match !cs_continue_targets with
  | [] -> None
  | x :: _ -> Some x

let label_block name =
  match sym_lookup name !cs_labels with
  | Some bid -> bid
  | None ->
      let bid = fresh_block () in
      cs_labels := sym_insert name bid !cs_labels;
      bid

let initial_compile_state prefix bits =
  cs_next_temp := 0;
  cs_next_block := 0;
  cs_next_label := 0;
  cs_data_prefix := prefix;
  cs_vars := scope_empty;
  cs_structs := SymE;
  cs_struct_sizes := SymE;
  cs_struct_members := SymE;
  cs_globals := SymE;
  cs_constants := SymE;
  cs_functions := SymE;
  cs_function_types := SymE;
  cs_labels := SymE;
  cs_data_items := [];
  cs_break_targets := [];
  cs_continue_targets := [];
  cs_target_bits := bits;
  cs_current_function := None;
  cc_contexts := []
