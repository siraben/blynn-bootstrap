(* ccc part 50 (segment a): statement and declaration lowering; port of
   Hcc.Lower lines 25-586 (lowerFunction .. registerTypesAggregates).
   This file OPENS the big mutually recursive Lower group: the first
   definition uses `let rec`, everything else here and in parts 52/54/56
   uses `and`. *)

let rec lower_function name params body =
  let ctx = buf_new 32 in
  buf_add_str ctx "function ";
  buf_add_bytes ctx name;
  with_error_context (buf_take ctx)
    (fun () ->
       with_function_scope
         (fun () ->
            with_current_function name
              (fun () -> lower_function_body name params body)))

and lower_function_body name params body =
  let bid = fresh_block () in
  let param_instrs = lower_params 0 params in
  let default_term = default_return_term () in
  let blocks = lower_statements_from bid param_instrs body default_term in
  FunctionIr (name, blocks)

and default_return_term () =
  let mty = current_return_type () in
  match mty with
  | Some CVoid -> TRet None
  | _ -> TRet (Some (OImm 0))

and coerce_return_operand op =
  let mty = current_return_type () in
  match mty with
  | Some CVoid -> ([], op)
  | Some ty -> coerce_scalar ty op
  | None -> ([], op)

and lower_statements_from bid instrs stmts default_term =
  match stmts with
  | [] -> [BasicBlock (bid, instrs, default_term)]
  | SReturn value :: rest ->
      (match value with
       | None ->
           let tail_blocks = lower_unreachable_labels rest default_term in
           BasicBlock (bid, instrs, TRet None) :: tail_blocks
       | Some expr ->
           if expr_is_short_circuit_boolean expr then
             (let yes_id = fresh_block () in
              let no_id = fresh_block () in
              let cond_blocks = lower_condition_block bid instrs expr yes_id no_id in
              let (yes_instrs, yes_op) = coerce_return_operand (OImm 1) in
              let (no_instrs, no_op) = coerce_return_operand (OImm 0) in
              let tail_blocks = lower_unreachable_labels rest default_term in
              list_append cond_blocks
                (list_append
                   [BasicBlock (yes_id, yes_instrs, TRet (Some yes_op));
                    BasicBlock (no_id, no_instrs, TRet (Some no_op))]
                   tail_blocks))
           else
             (let (ret_instrs, op) = lower_expr expr in
              let (coerce_instrs, ret_op) = coerce_return_operand op in
              let tail_blocks = lower_unreachable_labels rest default_term in
              BasicBlock (bid, list_append instrs (list_append ret_instrs coerce_instrs),
                          TRet (Some ret_op)) :: tail_blocks))
  | SBlock body :: rest ->
      (match rest with
       | [] -> with_var_scope (fun () -> lower_statements_from bid instrs body default_term)
       | _ ->
           let rest_id = fresh_block () in
           let body_blocks =
             with_var_scope (fun () -> lower_statements_from bid instrs body (TJump rest_id)) in
           let rest_blocks = lower_statements_from rest_id [] rest default_term in
           list_append body_blocks rest_blocks)
  | SDecl (ty, name, init_expr) :: rest ->
      let decl_instrs = lower_decl ty name init_expr in
      lower_statements_from bid (list_append instrs decl_instrs) rest default_term
  | SDecls decls :: rest ->
      let decl_instrs = lower_decls decls in
      lower_statements_from bid (list_append instrs decl_instrs) rest default_term
  | STypedef :: rest ->
      lower_statements_from bid instrs rest default_term
  | SExpr expr :: rest ->
      let expr_instrs = lower_side_effect expr in
      lower_statements_from bid (list_append instrs expr_instrs) rest default_term
  | SWhile (cond, body) :: rest ->
      let cond_id = fresh_block () in
      let body_id = fresh_block () in
      let rest_id = fresh_block () in
      let cond_blocks = lower_condition_block cond_id [] cond body_id rest_id in
      let body_blocks =
        with_loop_targets rest_id cond_id
          (fun () -> lower_statements_from body_id [] body (TJump cond_id)) in
      let rest_blocks = lower_statements_from rest_id [] rest default_term in
      BasicBlock (bid, instrs, TJump cond_id)
        :: list_append cond_blocks (list_append body_blocks rest_blocks)
  | SDoWhile (body, cond) :: rest ->
      let body_id = fresh_block () in
      let cond_id = fresh_block () in
      let rest_id = fresh_block () in
      let cond_blocks = lower_condition_block cond_id [] cond body_id rest_id in
      let body_blocks =
        with_loop_targets rest_id cond_id
          (fun () -> lower_statements_from body_id [] body (TJump cond_id)) in
      let rest_blocks = lower_statements_from rest_id [] rest default_term in
      BasicBlock (bid, instrs, TJump body_id)
        :: list_append body_blocks (list_append cond_blocks rest_blocks)
  | SFor (init_expr, cond_expr, step_expr, body) :: rest ->
      let init_instrs = maybe_lower_side_effect init_expr in
      let cond_id = fresh_block () in
      let body_id = fresh_block () in
      let step_id = fresh_block () in
      let rest_id = fresh_block () in
      let cond_blocks = lower_loop_condition_blocks cond_expr cond_id body_id rest_id in
      let step_instrs = maybe_lower_side_effect step_expr in
      let body_blocks =
        with_loop_targets rest_id step_id
          (fun () -> lower_statements_from body_id [] body (TJump step_id)) in
      let rest_blocks = lower_statements_from rest_id [] rest default_term in
      BasicBlock (bid, list_append instrs init_instrs, TJump cond_id)
        :: list_append cond_blocks
             (list_append body_blocks
                (list_append [BasicBlock (step_id, step_instrs, TJump cond_id)] rest_blocks))
  | SSwitch (value, body) :: rest ->
      let (value_instrs, value_op) = lower_expr value in
      let dispatch_id = fresh_block () in
      let rest_id = fresh_block () in
      let switch_blocks = lower_switch dispatch_id rest_id value_op body in
      let rest_blocks = lower_statements_from rest_id [] rest default_term in
      BasicBlock (bid, list_append instrs value_instrs, TJump dispatch_id)
        :: list_append switch_blocks rest_blocks
  | SGoto name :: rest ->
      let target = label_block name in
      let tail_blocks = lower_unreachable_labels rest default_term in
      BasicBlock (bid, instrs, TJump target) :: tail_blocks
  | SLabel name :: rest ->
      let target = label_block name in
      let blocks = lower_statements_from target [] rest default_term in
      BasicBlock (bid, instrs, TJump target) :: blocks
  | SIf (cond, yes, no) :: rest ->
      let yes_id = fresh_block () in
      let no_id = fresh_block () in
      let (rest_id, rest_blocks) = lower_if_rest_target rest default_term in
      let no_target = lower_if_no_target no rest_id no_id in
      let yes_blocks = lower_statements_from yes_id [] yes (TJump rest_id) in
      let no_blocks = lower_if_no_blocks no no_id rest_id in
      let cond_blocks = lower_condition_block bid instrs cond yes_id no_target in
      list_append cond_blocks (list_append yes_blocks (list_append no_blocks rest_blocks))
  | SBreak :: rest ->
      let target = require_break_target () in
      let tail_blocks = lower_unreachable_labels rest default_term in
      BasicBlock (bid, instrs, TJump target) :: tail_blocks
  | SContinue :: rest ->
      let target = require_continue_target () in
      let tail_blocks = lower_unreachable_labels rest default_term in
      BasicBlock (bid, instrs, TJump target) :: tail_blocks
  | stmt :: _ ->
      let b = buf_new 64 in
      buf_add_str b "unsupported statement in lowering: ";
      buf_add_bytes b (render_stmt_tag stmt);
      cc_throw (buf_take b)

and lower_if_rest_target rest default_term =
  match rest with
  | [] ->
      (match default_term with
       | TJump target -> (target, [])
       | _ -> lower_if_join_target rest default_term)
  | _ -> lower_if_join_target rest default_term

and lower_if_join_target rest default_term =
  let join_id = fresh_block () in
  let blocks = lower_statements_from join_id [] rest default_term in
  (join_id, blocks)

and lower_if_no_target no rest_id no_id =
  match no with
  | [] -> rest_id
  | _ -> no_id

and lower_if_no_blocks no no_id rest_id =
  match no with
  | [] -> []
  | _ -> lower_statements_from no_id [] no (TJump rest_id)

and lower_unreachable_labels stmts default_term =
  match stmts with
  | [] -> []
  | SLabel name :: rest ->
      let target = label_block name in
      lower_statements_from target [] rest default_term
  | _ :: rest ->
      lower_unreachable_labels rest default_term

and maybe_lower_side_effect value =
  match value with
  | None -> []
  | Some expr -> lower_side_effect expr

and lower_loop_condition_blocks cond_expr cond_id body_id rest_id =
  match cond_expr with
  | None -> [BasicBlock (cond_id, [], TJump body_id)]
  | Some cond -> lower_condition_block cond_id [] cond body_id rest_id

and lower_condition_block bid instrs cond true_id false_id =
  match cond with
  | EBinary (op, left, right) ->
      if bytes_eq_str op "&&" then
        (let right_id = fresh_block () in
         let left_blocks = lower_condition_block bid instrs left right_id false_id in
         let right_blocks = lower_condition_block right_id [] right true_id false_id in
         list_append left_blocks right_blocks)
      else if bytes_eq_str op "||" then
        (let right_id = fresh_block () in
         let left_blocks = lower_condition_block bid instrs left true_id right_id in
         let right_blocks = lower_condition_block right_id [] right true_id false_id in
         list_append left_blocks right_blocks)
      else if is_branch_comparison_op_string op then
        (let (cond_instrs, iop, left_op, right_op) = lower_branch_comparison op left right in
         [BasicBlock (bid, list_append instrs cond_instrs,
                      TBranchCmp (iop, left_op, right_op, true_id, false_id))])
      else lower_value_condition_block bid instrs cond true_id false_id
  | EUnary (op, value) ->
      if bytes_eq_str op "!" then
        lower_condition_block bid instrs value false_id true_id
      else lower_value_condition_block bid instrs cond true_id false_id
  | _ ->
      lower_value_condition_block bid instrs cond true_id false_id

and lower_value_condition_block bid instrs cond true_id false_id =
  let (cond_instrs, cond_op) = lower_expr cond in
  [BasicBlock (bid, list_append instrs cond_instrs, TBranch (cond_op, true_id, false_id))]

and is_branch_comparison_op_string op =
  bytes_eq_any op ["=="; "!="; "<"; "<="; ">"; ">="]

and lower_branch_comparison op a b =
  let (instrs, ao, bo) = lower_comparison_operands a b in
  let iop =
    if bytes_eq_str op "==" then irop_eq
    else if bytes_eq_str op "!=" then irop_ne
    else comparison_op op a b in
  (instrs, iop, ao, bo)

and require_break_target () =
  let target = current_break_target () in
  match target with
  | Some bid -> bid
  | None -> cc_throw_str "break outside loop or switch"

and require_continue_target () =
  let target = current_continue_target () in
  match target with
  | Some bid -> bid
  | None -> cc_throw_str "continue outside loop"

and lower_switch dispatch_id rest_id value_op body =
  let rec la_zip clauses ids =
    match clauses with
    | [] -> []
    | c :: crest ->
        (match ids with
         | [] -> []
         | i :: irest -> (c, i) :: la_zip crest irest) in
  let body_stmts = switch_body_statements body in
  let clauses = collect_switch_clauses body_stmts in
  let clause_ids = fresh_blocks (list_length clauses) in
  let clause_pairs = la_zip clauses clause_ids in
  let default_target = switch_default_target rest_id clause_pairs in
  let switch_case_pairs = switch_cases clause_pairs in
  let dispatch_blocks = lower_switch_dispatch dispatch_id value_op default_target switch_case_pairs in
  let body_blocks =
    with_break_target rest_id (fun () -> lower_switch_clauses rest_id clause_pairs) in
  list_append dispatch_blocks body_blocks

and lower_switch_dispatch bid value_op default_target switch_case_pairs =
  match switch_case_pairs with
  | [] -> [BasicBlock (bid, [], TJump default_target)]
  | (case_expr, target) :: tail_cases ->
      let next_id = switch_next_dispatch_target default_target tail_cases in
      let (case_instrs, case_op) = lower_expr case_expr in
      let block =
        BasicBlock (bid, case_instrs,
                    TBranchCmp (irop_eq, value_op, case_op, target, next_id)) in
      (match tail_cases with
       | [] -> [block]
       | _ ->
           let rest_blocks = lower_switch_dispatch next_id value_op default_target tail_cases in
           block :: rest_blocks)

and lower_switch_clauses rest_id clauses =
  match clauses with
  | [] -> []
  | pair :: rest ->
      (match pair with
       | (SwitchClause (_, body), bid) ->
           let fallthrough = switch_fallthrough_target rest_id rest in
           let body_blocks = lower_statements_from bid [] body (TJump fallthrough) in
           let rest_blocks = lower_switch_clauses rest_id rest in
           list_append body_blocks rest_blocks)

and lower_side_effect expr =
  match expr with
  | ECall (callee, args) ->
      (match callee with
       | EVar name ->
           if is_ignored_side_effect_call name then []
           else
             (let direct = lookup_function name in
              if direct then lower_direct_side_effect name args
              else lower_indirect_side_effect (EVar name) args)
       | _ -> lower_indirect_side_effect callee args)
  | EAssign (lhs, rhs) ->
      lower_assignment_instrs lhs rhs
  | ECompoundAssign (op, lhs, rhs) ->
      let result = lower_compound_assignment op lhs rhs in
      (match result with
       | (instrs, _) -> instrs)
  | EPostfix (op, target) ->
      if bytes_eq_str op "--" then lower_inc_dec_side_effect irop_sub target
      else if bytes_eq_str op "++" then lower_inc_dec_side_effect irop_add target
      else
        (let (instrs, _) = lower_expr expr in
         instrs)
  | _ ->
      let (instrs, _) = lower_expr expr in
      instrs

and lower_assignment_instrs lhs rhs =
  let (instrs, _) = lower_assignment lhs rhs in
  instrs

and lower_inc_dec_side_effect op target =
  let (lv_instrs, lv) = lower_l_value target in
  let (read_instrs, current) = read_l_value lv in
  let out = fresh_temp () in
  let step = inc_dec_step target in
  let write_instrs = write_l_value lv (OTemp out) in
  list_append lv_instrs
    (list_append read_instrs
       (list_append [IBin (out, op, current, OImm step)] write_instrs))

and lower_direct_side_effect name args =
  let lowered = lower_exprs args in
  list_append (lower_expr_results_instrs lowered)
    [ICall (None, name, lower_expr_results_ops lowered)]

and lower_indirect_side_effect callee args =
  let (callee_instrs, callee_op) = lower_expr callee in
  let lowered = lower_exprs args in
  list_append callee_instrs
    (list_append (lower_expr_results_instrs lowered)
       [ICallIndirect (None, callee_op, lower_expr_results_ops lowered)])

and lower_expr_results_instrs lowered =
  list_concat_map (fun r -> (let (instrs, _) = r in instrs)) lowered

and lower_expr_results_ops lowered =
  list_map (fun r -> (let (_, op) = r in op)) lowered

and lower_decls decls =
  list_concat_map
    (fun decl -> (let (ty, name, init_expr) = decl in lower_decl ty name init_expr))
    decls

and lower_decl ty name init_expr =
  let aggregate_storage = is_aggregate_type_m ty in
  let temp = fresh_temp () in
  bind_var name temp ty;
  if aggregate_storage
  then lower_aggregate_decl ty temp init_expr
  else lower_scalar_decl ty temp init_expr

and lower_aggregate_decl ty temp init_expr =
  let size = type_size ty in
  let init_instrs = lower_aggregate_decl_init ty temp init_expr in
  IAlloca (temp, size) :: init_instrs

and lower_aggregate_decl_init ty temp init_expr =
  let template = local_aggregate_template_data ty init_expr in
  match template with
  | Some label ->
      lower_aggregate_decl_template ty temp init_expr label
  | None ->
      lower_aggregate_decl_runtime ty temp init_expr

and lower_aggregate_decl_template ty temp init_expr label =
  let copy_instrs = copy_object (OTemp temp) (OGlobal label) ty in
  let runtime_instrs = lower_aggregate_init_writes (OTemp temp) ty init_expr in
  list_append copy_instrs runtime_instrs

and lower_aggregate_decl_runtime ty temp init_expr =
  match init_expr with
  | Some (EInitList _) ->
      let zero_instrs = zero_object (OTemp temp) ty in
      let write_instrs = lower_aggregate_init_writes (OTemp temp) ty init_expr in
      list_append zero_instrs write_instrs
  | Some expr ->
      let (expr_instrs, op) = lower_expr expr in
      let copy_instrs = copy_object (OTemp temp) op ty in
      list_append expr_instrs copy_instrs
  | None -> []

and lower_scalar_decl ty temp init_expr =
  match init_expr with
  | None -> [IConst (temp, 0)]
  | Some expr ->
      let (expr_instrs, op) = lower_expr expr in
      let (coerce_instrs, coerce_op) = coerce_scalar ty op in
      list_append expr_instrs (list_append coerce_instrs [ICopy (temp, coerce_op)])

and local_aggregate_template_data ty init_expr =
  match ty with
  | CArray (_, _) -> local_array_template_data ty init_expr
  | _ -> local_non_array_template_data ty init_expr

and local_array_template_data ty init_expr =
  match init_expr with
  | Some expr ->
      if static_initializer_expr expr
      then
        (match expr with
         | EInitList _ -> local_data_item ty init_expr
         | EString _ -> local_data_item ty init_expr
         | _ -> None)
      else None
  | None -> None

and local_non_array_template_data ty init_expr =
  match init_expr with
  | Some expr ->
      (match expr with
       | EInitList _ ->
           let aggregate_storage = is_aggregate_type_m ty in
           if aggregate_storage && static_initializer_expr expr
           then local_data_item ty init_expr
           else None
       | _ -> None)
  | None -> None

and static_initializer_expr expr =
  match expr with
  | EInitList exprs -> all_static_initializer_exprs exprs
  | EString _ -> true
  | EInt _ -> true
  | EChar _ -> true
  | ECast (_, value) -> static_initializer_expr value
  | EUnary (op, value) ->
      if bytes_eq_str op "-" then static_initializer_expr value
      else if bytes_eq_str op "+" then static_initializer_expr value
      else if bytes_eq_str op "~" then static_initializer_expr value
      else if bytes_eq_str op "!" then static_initializer_expr value
      else if bytes_eq_str op "&" then true
      else false
  | EVar _ -> true
  | EBinary (op, left, right) ->
      not (bytes_eq_str op ",") &&
      static_initializer_expr left && static_initializer_expr right
  | ECond (cond, yes, no) ->
      static_initializer_expr cond && static_initializer_expr yes &&
      static_initializer_expr no
  | _ -> false

and all_static_initializer_exprs exprs =
  match exprs with
  | [] -> true
  | expr :: rest -> static_initializer_expr expr && all_static_initializer_exprs rest

and local_data_item ty init_expr =
  let data_label = fresh_data_label () in
  let values = global_data ty init_expr in
  add_data_item (DataItem (data_label, values));
  Some data_label

and lower_aggregate_init_writes dst ty init_expr =
  match init_expr with
  | Some (EInitList exprs) -> lower_aggregate_init_list dst ty exprs
  | _ -> []

and lower_aggregate_init_list dst ty exprs =
  match ty with
  | CArray (inner, _) -> lower_array_init_writes dst inner 0 exprs
  | _ ->
      let aggregate = aggregate_fields ty in
      (match aggregate with
       | Some aggregate_info ->
           (match aggregate_info with
            | (is_union, fields) ->
                if is_union then lower_union_init_writes dst fields exprs
                else lower_struct_init_writes dst 0 fields exprs)
       | _ -> [])

and lower_union_init_writes dst fields exprs =
  match fields with
  | [] -> []
  | field :: _ ->
      (match field with
       | Field (field_ty, _) ->
           (match exprs with
            | expr :: _ -> lower_aggregate_element_write dst 0 field_ty expr
            | [] -> []))

and lower_array_init_writes dst inner index exprs =
  match exprs with
  | [] -> []
  | expr :: rest ->
      let elem_size = type_size inner in
      let current = lower_aggregate_element_write dst (index * elem_size) inner expr in
      let tail_instrs = lower_array_init_writes dst inner (index + 1) rest in
      list_append current tail_instrs

and lower_struct_init_writes dst offset fields exprs =
  match fields with
  | [] -> []
  | field :: field_rest ->
      (match exprs with
       | [] -> []
       | expr :: expr_rest ->
           (match field with
            | Field (field_ty, _) ->
                let align = type_align field_ty in
                let field_size = type_size field_ty in
                let aligned = align_up offset align in
                let current = lower_aggregate_element_write dst aligned field_ty expr in
                let tail_instrs =
                  lower_struct_init_writes dst (aligned + field_size) field_rest expr_rest in
                list_append current tail_instrs))

and lower_aggregate_element_write dst offset field_ty expr =
  let (addr_instrs, addr) = offset_address dst offset in
  let aggregate_storage = is_aggregate_type_m field_ty in
  let value_instrs = lower_aggregate_element_value_write aggregate_storage addr field_ty expr in
  list_append addr_instrs value_instrs

and lower_aggregate_element_value_write aggregate_storage addr field_ty expr =
  if aggregate_storage
  then lower_aggregate_element_aggregate_write addr field_ty expr
  else lower_aggregate_element_scalar_write addr field_ty expr

and lower_aggregate_element_aggregate_write addr field_ty expr =
  match expr with
  | EInitList exprs -> lower_aggregate_init_list addr field_ty exprs
  | _ ->
      let (expr_instrs, op) = lower_expr expr in
      let copy_instrs = copy_object addr op field_ty in
      list_append expr_instrs copy_instrs

and lower_aggregate_element_scalar_write addr field_ty expr =
  let (expr_instrs, op) = lower_expr expr in
  let (coerce_instrs, coerce_op) = coerce_scalar field_ty op in
  let store = store_instr field_ty addr coerce_op in
  list_append expr_instrs (list_append coerce_instrs [store])

and register_extern_globals globals =
  list_iter
    (fun global ->
      (let (ty, name) = global in
       (register_type_aggregates ty; bind_global name ty)))
    globals

and register_constants constants =
  list_iter
    (fun constant -> (let (name, value) = constant in bind_constant name value))
    constants

and register_field_aggregates fields =
  list_iter
    (fun f -> (match f with Field (ty, _) -> register_type_aggregates ty))
    fields

and register_type_aggregates ty =
  match ty with
  | CPtr inner -> register_type_aggregates inner
  | CArray (inner, _) -> register_type_aggregates inner
  | CFunc (ret, params) ->
      register_type_aggregates ret;
      register_types_aggregates params
  | CStructNamed (name, fields) ->
      register_field_aggregates fields;
      bind_struct name false fields
  | CUnionNamed (name, fields) ->
      register_field_aggregates fields;
      bind_struct name true fields
  | CStructDef fields ->
      register_field_aggregates fields
  | CUnionDef fields ->
      register_field_aggregates fields
  | _ -> ()

and register_types_aggregates types =
  list_iter (fun ty -> register_type_aggregates ty) types
