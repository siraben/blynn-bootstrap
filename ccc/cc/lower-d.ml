(* ccc part 56: module construction; port of Hcc.M1Ir (the build/register
   half). Continues the mutually recursive lowering group started in
   lower-a.ml. The Either CodegenError plumbing of the reference is
   gone: errors are fatal via cc_throw. The processing order is the
   reference's exactly: register all top decls first (collecting the
   registered data items), then lower the functions, draining pending
   data items after each one. *)

and build_m1ir_module prefix target decls =
  initial_compile_state prefix target;
  register_builtin_structs ();
  let registered_items = register_top_decls_ir decls in
  let function_items = lower_top_decls_ir decls in
  list_append registered_items function_items

and lower_top_decls_ir decls =
  match decls with
  | [] -> []
  | DFunction (_, name, params, body) :: rest ->
      (register_implicit_calls (param_decl_names_ir params) body;
       let fn = lower_function name params body in
       let pending = pending_data_items_ir () in
       let rest_items = lower_top_decls_ir rest in
       TopFunction fn :: list_append pending rest_items)
  | _ :: rest -> lower_top_decls_ir rest

and register_top_decls_ir decls =
  match decls with
  | [] -> []
  | decl :: rest ->
      let items = register_top_decl_ir decl in
      let rest_items = register_top_decls_ir rest in
      list_append items rest_items

and register_top_decl_ir decl =
  match decl with
  | DGlobal (ty, name, init_expr) ->
      (register_type_aggregates ty;
       bind_global name ty;
       let values = global_data ty init_expr in
       let pending = pending_data_items_ir () in
       TopData (DataItem (name, values)) :: pending)
  | DGlobals globals ->
      register_globals_ir globals
  | _ ->
      (register_top_decl_shallow_state decl; [])

and register_top_decl_shallow_state decl =
  match decl with
  | DFunction (ty, name, params, _) ->
      register_function_decl ty name params
  | DPrototype (ty, name, params) ->
      register_function_decl ty name params
  | DStructDecl (is_union, name, fields) ->
      (register_field_aggregates fields;
       bind_struct name is_union fields)
  | DExternGlobals globals ->
      register_extern_globals globals
  | DEnumConstants constants ->
      register_constants constants
  | DTypeDecl types ->
      register_types_aggregates types
  | _ -> ()

and register_function_decl ty name params =
  register_type_aggregates ty;
  register_types_aggregates (param_types params);
  bind_global name ty;
  bind_function_type name ty params

and register_globals_ir globals =
  match globals with
  | [] -> []
  | (ty, name, init_expr) :: rest ->
      (register_type_aggregates ty;
       bind_global name ty;
       let values = global_data ty init_expr in
       let pending = pending_data_items_ir () in
       let rest_items = register_globals_ir rest in
       TopData (DataItem (name, values)) :: list_append pending rest_items)

(* drain cs_data_items (newest first) into TopData items, oldest first *)
and pending_data_items_ir () =
  match !cs_data_items with
  | [] -> []
  | items ->
      (cs_data_items := [];
       let rec to_top l =
         match l with
         | [] -> []
         | item :: rest -> TopData item :: to_top rest in
       to_top (list_rev items))

and param_decl_names_ir params =
  match params with
  | [] -> []
  | Param (_, name) :: rest -> name :: param_decl_names_ir rest
