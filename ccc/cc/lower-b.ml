(* ccc part 52 (segment b): expression lowering; port of Hcc.Lower
   lines 588-1302 (lowerExpr .. scaledIndex). Continues the mutually
   recursive Lower group started in lower-a.ml. Operator strings
   cannot appear in match patterns, so the EUnary/EBinary/EPostfix
   dispatch becomes bytes_eq_str chains inside the arms. *)

and lower_expr expr =
  match expr with
  | EInt text -> ([], int_const_operand text)
  | EFloat text -> ([], float_const_operand text)
  | EChar text -> ([], OImm (char_value text))
  | EString text ->
      let data_label = fresh_data_label () in
      add_data_item (DataItem (data_label, bytes_data (string_bytes text)));
      ([], OGlobal data_label)
  | EVar name -> lower_var_expr name
  | EUnary (op, x) ->
      if bytes_eq_str op "+" then lower_expr x
      else if bytes_eq_str op "-" then
        (let (a, o) = lower_expr x in
         let zero = fresh_temp () in
         let out = fresh_temp () in
         (list_append a [IConst (zero, 0); IBin (out, irop_sub, OTemp zero, o)],
          OTemp out))
      else if bytes_eq_str op "!" then
        (let (a, o) = lower_expr x in
         let zero = fresh_temp () in
         let out = fresh_temp () in
         (list_append a [IConst (zero, 0); IBin (out, irop_eq, o, OTemp zero)],
          OTemp out))
      else if bytes_eq_str op "~" then
        (let (a, o) = lower_expr x in
         let zero = fresh_temp () in
         let neg = fresh_temp () in
         let out = fresh_temp () in
         (list_append a
            [IConst (zero, 0); IBin (neg, irop_sub, OTemp zero, o);
             IBin (out, irop_sub, OTemp neg, OImm 1)],
          OTemp out))
      else if bytes_eq_str op "*" then
        (* EUnary "*" (EUnary "&" value) collapses; other "*" reads *)
        (match x with
         | EUnary (op2, value) ->
             if bytes_eq_str op2 "&" then lower_expr value
             else read_l_value_expr expr
         | _ -> read_l_value_expr expr)
      else if bytes_eq_str op "&" then lower_l_value_address x
      else if bytes_eq_str op "++" then lower_inc_dec true irop_add x
      else if bytes_eq_str op "--" then lower_inc_dec true irop_sub x
      else lb_unsupported_expr expr
  | ECast (ty, x) ->
      let (a, o) = lower_expr x in
      let (coerce_instrs, coerce_op) = coerce_scalar ty o in
      (list_append a coerce_instrs, coerce_op)
  | ESizeofType ty ->
      let size = type_size ty in
      let temp = fresh_temp () in
      ([IConst (temp, size)], OTemp temp)
  | ESizeofExpr value ->
      let mty = expr_type value in
      let ty = require_maybe_type (str_to_bytes "sizeof expression has unknown type") mty in
      let size = type_size ty in
      let temp = fresh_temp () in
      ([IConst (temp, size)], OTemp temp)
  | ECond (cond, yes, no) ->
      let (ci, co) = lower_expr cond in
      let (yi, yo) = lower_expr yes in
      let (ni, no_op) = lower_expr no in
      let out = fresh_temp () in
      ([ICond (out, ci, co, yi, yo, ni, no_op)], OTemp out)
  | EBinary (op, a, b) ->
      if bytes_eq_str op "," then
        (let ai = lower_side_effect a in
         let (bi, bo) = lower_expr b in
         (list_append ai bi, bo))
      else if bytes_eq_str op "&&" then lower_logical_and a b
      else if bytes_eq_str op "||" then lower_logical_or a b
      else if bytes_eq_str op "+" then lower_add_expr a b
      else if bytes_eq_str op "-" then lower_sub_expr a b
      else if bytes_eq_str op ">>" then lower_shift_expr op a b
      else lower_binary_expr op a b
  | EIndex (_, _) -> read_l_value_expr expr
  | EPtrMember (_, _) -> read_l_value_expr expr
  | EMember (_, _) -> read_l_value_expr expr
  | ECall (callee, args) ->
      (match callee with
       | EVar name ->
           let direct = lookup_function name in
           if direct then lower_direct_call_expr name args
           else lower_indirect_call (EVar name) args
       | _ -> lower_indirect_call callee args)
  | EAssign (lhs, rhs) -> lower_assignment lhs rhs
  | ECompoundAssign (op, lhs, rhs) -> lower_compound_assignment op lhs rhs
  | EPostfix (op, target) ->
      if bytes_eq_str op "--" then lower_inc_dec false irop_sub target
      else if bytes_eq_str op "++" then lower_inc_dec false irop_add target
      else lb_unsupported_expr expr
  | _ -> lb_unsupported_expr expr

and lb_unsupported_expr expr =
  let b = buf_new 64 in
  buf_add_str b "unsupported expression in lowering: ";
  buf_add_bytes b (render_expr_tag expr);
  cc_throw (buf_take b)

(* "prefix" ++ name diagnostics *)
and lb_msg_name prefix name =
  let b = buf_new 64 in
  buf_add_str b prefix;
  buf_add_bytes b name;
  buf_take b

and lower_var_expr name =
  if is_function_name_macro name then lower_function_name_macro ()
  else
    (match builtin_constant name with
     | Some value -> ([], OImm value)
     | None -> lower_non_builtin_var_expr name)

and lower_function_name_macro () =
  let mname = current_function_name () in
  match mname with
  | Some name -> lower_expr (EString name)
  | None -> ([], OImm 0)

and lower_non_builtin_var_expr name =
  let constant = lookup_constant name in
  match constant with
  | Some value -> ([], OImm value)
  | None -> lower_non_constant_var_expr name

and lower_non_constant_var_expr name =
  let local = lookup_var_maybe name in
  match local with
  | Some temp ->
      let mty = lookup_var_type name in
      let ty = require_maybe_type (lb_msg_name "unknown local type: " name) mty in
      coerce_scalar ty (OTemp temp)
  | None -> lower_non_local_var_expr name

and lower_non_local_var_expr name =
  let func = lookup_function name in
  if func then ([], OFunction name)
  else lower_global_var_expr name

and lower_global_var_expr name =
  let global_ty = lookup_global_type name in
  match global_ty with
  | Some ty -> lower_typed_global_var_expr name ty
  | None -> cc_throw (lb_msg_name "unknown identifier: " name)

and lower_typed_global_var_expr name ty =
  match ty with
  | CArray (_, _) -> ([], OGlobal name)
  | _ ->
      let aggregate_storage = is_aggregate_type_m ty in
      if aggregate_storage then ([], OGlobal name)
      else
        (let out = fresh_temp () in
         let load = load_instr out ty (OGlobal name) in
         ([load], OTemp out))

and lower_binary_expr op a b =
  if is_comparison_op_string op then lower_comparison_expr op a b
  else if bytes_eq_str op "/" || bytes_eq_str op "%" then
    (let common_ty = usual_arithmetic_type a b in
     let iop =
       if is_unsigned_type common_ty then
         (if bytes_eq_str op "/" then irop_udiv else irop_umod)
       else
         (if bytes_eq_str op "/" then irop_div else irop_mod) in
     lower_plain_bin iop a b)
  else
    (match lower_bin_op op with
     | Some iop ->
         if bytes_eq_str op "<<" then lower_shift_expr op a b
         else lower_plain_bin iop a b
     | None -> cc_throw (lb_msg_name "unsupported binary operator in lowering: " op))

and is_comparison_op_string op =
  bytes_eq_any op ["<"; "<="; ">"; ">="]

and lower_comparison_expr op a b =
  let (instrs, ao, bo) = lower_comparison_operands a b in
  let out = fresh_temp () in
  let iop = comparison_op op a b in
  (list_append instrs [IBin (out, iop, ao, bo)], OTemp out)

and lower_comparison_operands a b =
  let (ai, ao) = lower_expr a in
  let (bi, bo) = lower_expr b in
  let common_ty = usual_arithmetic_type a b in
  let (acoerce_instrs, acoerce_op) = coerce_bin_operand common_ty a ao in
  let (bcoerce_instrs, bcoerce_op) = coerce_bin_operand common_ty b bo in
  (list_append ai (list_append bi (list_append acoerce_instrs bcoerce_instrs)),
   acoerce_op, bcoerce_op)

and lower_direct_call_expr name args =
  let lowered = lower_exprs args in
  let out = fresh_temp () in
  let instrs = lower_expr_results_instrs lowered in
  let ops = lower_expr_results_ops lowered in
  (list_append instrs [ICall (Some out, name, ops)], OTemp out)

and lower_exprs args = list_map (fun x -> lower_expr x) args

and lower_indirect_call callee args =
  let (callee_instrs, callee_op) = lower_expr callee in
  let lowered = lower_exprs args in
  let out = fresh_temp () in
  (list_append callee_instrs
     (list_append (lower_expr_results_instrs lowered)
        [ICallIndirect (Some out, callee_op, lower_expr_results_ops lowered)]),
   OTemp out)

and lower_logical_and a b = lower_short_circuit true a b

and lower_logical_or a b = lower_short_circuit false a b

and lower_short_circuit is_and left right =
  let (left_instrs, left_op) = lower_expr left in
  let (right_instrs, right_bool) = lower_truth_expr right in
  let out = fresh_temp () in
  let (true_ins, true_op, false_ins, false_op) =
    if is_and then (right_instrs, right_bool, [], OImm 0)
    else ([], OImm 1, right_instrs, right_bool) in
  ([ICond (out, left_instrs, left_op, true_ins, true_op, false_ins, false_op)],
   OTemp out)

and lower_truth_expr expr =
  let (instrs, op) = lower_expr expr in
  if expr_is_boolean expr then (instrs, op)
  else
    (let out = fresh_temp () in
     (list_append instrs [IBin (out, irop_ne, op, OImm 0)], OTemp out))

and expr_is_boolean expr =
  match expr with
  | EUnary (op, _) -> bytes_eq_str op "!"
  | EBinary (op, _, _) ->
      bytes_eq_any op ["=="; "!="; "<"; "<="; ">"; ">="; "&&"; "||"]
  | _ -> false

and expr_is_short_circuit_boolean expr =
  match expr with
  | EBinary (op, _, _) -> bytes_eq_str op "&&" || bytes_eq_str op "||"
  | _ -> false

and lower_shift_expr op left right =
  let (left_instrs, left_op) = lower_expr left in
  let (right_instrs, right_op) = lower_expr right in
  let out = fresh_temp () in
  let iop =
    if bytes_eq_str op ">>" then shift_right_op left
    else if bytes_eq_str op "<<" then irop_shl
    else irop_shl in
  let result_ty = expr_type (EBinary (op, left, right)) in
  let (coerce_instrs, coerce_op) = coerce_maybe_scalar result_ty (OTemp out) in
  (list_append left_instrs
     (list_append right_instrs
        (list_append [IBin (out, iop, left_op, right_op)] coerce_instrs)),
   coerce_op)

and lower_add_expr a b =
  let aty = expr_type a in
  let bty = expr_type b in
  match pointer_element_type aty with
  | Some elem_ty -> lower_pointer_offset irop_add a b elem_ty
  | None ->
      (match pointer_element_type bty with
       | Some elem_ty -> lower_pointer_offset irop_add b a elem_ty
       | None -> lower_plain_bin irop_add a b)

and lower_sub_expr a b =
  let aty = expr_type a in
  let bty = expr_type b in
  match pointer_element_type aty with
  | Some elem_ty ->
      (match pointer_element_type bty with
       | Some _ -> lower_pointer_diff a b elem_ty
       | None -> lower_pointer_offset irop_sub a b elem_ty)
  | None -> lower_plain_bin irop_sub a b

and lower_pointer_diff a b elem_ty =
  let (ai, ao) = lower_expr a in
  let (bi, bo) = lower_expr b in
  let diff = fresh_temp () in
  let out = fresh_temp () in
  let size = type_size elem_ty in
  (list_append ai
     (list_append bi
        [IBin (diff, irop_sub, ao, bo); IBin (out, irop_div, OTemp diff, OImm size)]),
   OTemp out)

and lower_pointer_offset op ptr offset elem_ty =
  let (ptr_instrs, po) = lower_expr ptr in
  let (oi, oo) = lower_expr offset in
  let size = type_size elem_ty in
  let (scaled_instrs, scaled_op) = scaled_offset oo size in
  let out = fresh_temp () in
  (list_append ptr_instrs
     (list_append oi
        (list_append scaled_instrs [IBin (out, op, po, scaled_op)])),
   OTemp out)

and scaled_offset offset size =
  if size = 1 then ([], offset)
  else
    (match offset with
     | OImm value -> ([], OImm (value * size))
     | _ ->
         let scaled = fresh_temp () in
         ([IBin (scaled, irop_mul, offset, OImm size)], OTemp scaled))

and lower_plain_bin op a b =
  let (ai, ao) = lower_expr a in
  let (bi, bo) = lower_expr b in
  let common_ty = usual_arithmetic_type a b in
  let (acoerce_instrs, acoerce_op) = coerce_bin_operand common_ty a ao in
  let (bcoerce_instrs, bcoerce_op) = coerce_bin_operand common_ty b bo in
  let out = fresh_temp () in
  let (coerce_instrs, coerce_op) =
    if is_comparison_bin_op op then ([], OTemp out)
    else coerce_scalar common_ty (OTemp out) in
  (list_append ai
     (list_append bi
        (list_append acoerce_instrs
           (list_append bcoerce_instrs
              (list_append [IBin (out, op, acoerce_op, bcoerce_op)] coerce_instrs)))),
   coerce_op)

and coerce_bin_operand common_ty expr op =
  match expr with
  | EVar name ->
      let constant = lookup_constant name in
      (match (constant, builtin_constant name) with
       | (None, None) -> ([], op)
       | _ -> coerce_scalar common_ty op)
  | _ -> coerce_scalar common_ty op

and is_comparison_bin_op op =
  op = irop_eq || op = irop_ne || op = irop_lt || op = irop_le ||
  op = irop_gt || op = irop_ge || op = irop_ult || op = irop_ule ||
  op = irop_ugt || op = irop_uge

and pointer_element_type mty =
  match mty with
  | Some (CPtr ty) -> Some ty
  | Some (CArray (ty, _)) -> Some ty
  | _ -> None

and lower_assignment lhs rhs =
  let (lhs_instrs, lvalue) = lower_l_value lhs in
  let (rhs_instrs, rhs_op) = lower_expr rhs in
  let target_ty = l_value_type lvalue in
  let (coerce_instrs, coerce_op) = coerce_scalar target_ty rhs_op in
  let write_instrs = write_l_value lvalue coerce_op in
  (list_append lhs_instrs
     (list_append rhs_instrs (list_append coerce_instrs write_instrs)),
   coerce_op)

and lower_compound_assignment op lhs rhs =
  let (lhs_instrs, lvalue) = lower_l_value lhs in
  let (read_instrs, current_op) = read_l_value lvalue in
  let target_ty = l_value_type lvalue in
  let (rhs_instrs, rhs_op) = lower_expr rhs in
  let (op_instrs, result_op) = compound_bin_op op target_ty current_op rhs rhs_op in
  let (coerce_instrs, coerce_op) = coerce_scalar target_ty result_op in
  let write_instrs = write_l_value lvalue coerce_op in
  (list_append lhs_instrs
     (list_append read_instrs
        (list_append rhs_instrs
           (list_append op_instrs (list_append coerce_instrs write_instrs)))),
   coerce_op)

and compound_bin_op op target_ty lhs_op rhs_expr rhs_op =
  match target_ty with
  | CPtr elem_ty ->
      (* the reference guards on op == "+" || op == "-" here *)
      if bytes_eq_str op "+" || bytes_eq_str op "-" then
        pointer_compound_offset (if bytes_eq_str op "+" then irop_add else irop_sub)
          lhs_op rhs_op elem_ty
      else lb_compound_bin_op_general op target_ty lhs_op rhs_expr rhs_op
  | _ -> lb_compound_bin_op_general op target_ty lhs_op rhs_expr rhs_op

and lb_compound_bin_op_general op target_ty lhs_op rhs_expr rhs_op =
  let iop =
    if bytes_eq_str op "/" then
      (if is_unsigned_type target_ty then irop_udiv else irop_div)
    else if bytes_eq_str op "%" then
      (if is_unsigned_type target_ty then irop_umod else irop_mod)
    else if bytes_eq_str op ">>" then shift_right_op rhs_expr
    else
      (match lower_bin_op op with
       | Some o -> o
       | None -> cc_throw (lb_msg_name "unsupported compound assignment operator: " op)) in
  let out = fresh_temp () in
  ([IBin (out, iop, lhs_op, rhs_op)], OTemp out)

and pointer_compound_offset op base offset elem_ty =
  let size = type_size elem_ty in
  if size = 1 then
    (let out = fresh_temp () in
     ([IBin (out, op, base, offset)], OTemp out))
  else
    (let scaled = fresh_temp () in
     let out = fresh_temp () in
     ([IBin (scaled, irop_mul, offset, OImm size); IBin (out, op, base, OTemp scaled)],
      OTemp out))

and lower_inc_dec prefix op target =
  let (lv_instrs, lvalue) = lower_l_value target in
  let (read_instrs, current) = read_l_value lvalue in
  let out = fresh_temp () in
  let step = inc_dec_step target in
  if prefix then
    (let write_instrs = write_l_value lvalue (OTemp out) in
     (list_append lv_instrs
        (list_append read_instrs
           (list_append [IBin (out, op, current, OImm step)] write_instrs)),
      OTemp out))
  else
    (let old = fresh_temp () in
     let write_instrs = write_l_value lvalue (OTemp out) in
     let op_instrs =
       [IBin (old, irop_add, current, OImm 0); IBin (out, op, OTemp old, OImm step)] in
     (list_append lv_instrs
        (list_append read_instrs (list_append op_instrs write_instrs)),
      OTemp old))

and inc_dec_step target =
  let mty = expr_type target in
  match mty with
  | Some (CPtr ty) -> type_size ty
  | _ -> 1

and read_l_value_expr target =
  let (instrs, lvalue) = lower_l_value target in
  let (read_instrs, op) = read_l_value lvalue in
  (list_append instrs read_instrs, op)

and read_l_value lvalue =
  match lvalue with
  | LLocal (temp, ty) -> coerce_scalar ty (OTemp temp)
  | LAddress (addr, ty) ->
      (match ty with
       | CArray (_, _) -> ([], addr)
       | _ ->
           let aggregate_storage = is_aggregate_type_m ty in
           if aggregate_storage then ([], addr)
           else
             (let out = fresh_temp () in
              let load = load_instr out ty addr in
              ([load], OTemp out)))

and write_l_value lvalue value =
  match lvalue with
  | LLocal (temp, ty) ->
      let aggregate_storage = is_aggregate_type_m ty in
      if aggregate_storage then copy_object (OTemp temp) value ty
      else [ICopy (temp, value)]
  | LAddress (addr, ty) ->
      let aggregate_storage = is_aggregate_type_m ty in
      if aggregate_storage then copy_object addr value ty
      else
        (let store = store_instr ty addr value in
         [store])

and l_value_type lvalue =
  match lvalue with
  | LLocal (_, ty) -> ty
  | LAddress (_, ty) -> ty

and coerce_maybe_scalar mty op =
  match mty with
  | Some ty -> coerce_scalar ty op
  | None -> ([], op)

and coerce_scalar ty op =
  match ty with
  | CBool -> coerce_bool op
  | _ ->
      let integer = is_integer_type_m ty in
      if not integer then ([], op)
      else
        (let size = type_size ty in
         if size >= 8 then ([], op)
         else
           (match coerce_immediate_scalar (is_signed_integer_type ty) size op with
            | Some coerced -> ([], coerced)
            | None ->
                if is_signed_integer_type ty then sign_extend_scalar size op
                else mask_scalar size op))

and coerce_bool op =
  match immediate_scalar_value op with
  | Some value -> ([], OImm (if value = 0 then 0 else 1))
  | None ->
      let out = fresh_temp () in
      ([IBin (out, irop_ne, op, OImm 0)], OTemp out)

and coerce_immediate_scalar signed size op =
  if size >= 4 then coerce_word_immediate_scalar signed op
  else
    (match immediate_scalar_value op with
     | None -> None
     | Some value ->
         let modulus = pow2 (size * 8) in
         let masked = positive_mod value modulus in
         let sign_bit = pow2 (size * 8 - 1) in
         let coerced =
           if signed && masked >= sign_bit then masked - modulus
           else masked in
         Some (OImm coerced))

and coerce_word_immediate_scalar signed op =
  match op with
  | OImm value ->
      if signed || value >= 0 then Some (OImm value) else None
  | _ -> None

and immediate_scalar_value op =
  match op with
  | OImm value -> Some value
  | OImmBytes bs -> Some (little_endian_value bs 0)
  | _ -> None

and little_endian_value bs shift =
  match bs with
  | [] -> 0
  | byte :: rest -> byte * pow2 shift + little_endian_value rest (shift + 8)

and positive_mod value modulus =
  let result = hmod value modulus in
  if result < 0 then result + modulus else result

and mask_scalar size op =
  let out = fresh_temp () in
  ([IZExt (out, size, op)], OTemp out)

and sign_extend_scalar size op =
  let out = fresh_temp () in
  ([ISExt (out, size, op)], OTemp out)

and copy_object dst src ty =
  let size = type_size ty in
  copy_object_bytes dst src 0 size

and zero_object dst ty =
  let size = type_size ty in
  zero_object_bytes dst 0 size

and zero_object_bytes dst offset remaining =
  if remaining <= 0 then []
  else
    (let word = target_word_size () in
     let width = if remaining >= word then word else if remaining >= 4 then 4 else 1 in
     let (dst_instrs, dst_addr) = offset_address dst offset in
     let store =
       if width = 8 then IStore64 (dst_addr, OImm 0)
       else if width = 4 then IStore32 (dst_addr, OImm 0)
       else IStore8 (dst_addr, OImm 0) in
     let rest = zero_object_bytes dst (offset + width) (remaining - width) in
     list_append dst_instrs (list_append [store] rest))

and copy_object_bytes dst src offset remaining =
  if remaining <= 0 then []
  else
    (let word = target_word_size () in
     let width = if remaining >= word then word else if remaining >= 4 then 4 else 1 in
     let (dst_instrs, dst_addr) = offset_address dst offset in
     let (src_instrs, src_addr) = offset_address src offset in
     let v = fresh_temp () in
     let load = unsigned_load_at width v src_addr in
     let store = unsigned_store_at width dst_addr (OTemp v) in
     let rest = copy_object_bytes dst src (offset + width) (remaining - width) in
     list_append dst_instrs (list_append src_instrs (list_append [load; store] rest)))

and unsigned_load_at width dst addr =
  if width = 8 then ILoad64 (dst, addr)
  else if width = 4 then ILoad32 (dst, addr)
  else ILoad8 (dst, addr)

and unsigned_store_at width addr value =
  if width = 8 then IStore64 (addr, value)
  else if width = 4 then IStore32 (addr, value)
  else IStore8 (addr, value)

and offset_address base offset =
  if offset = 0 then ([], base)
  else
    (let out = fresh_temp () in
     ([IBin (out, irop_add, base, OImm offset)], OTemp out))

and lower_l_value_address target =
  match target with
  | EVar name -> lower_var_address name
  | _ -> lower_non_function_address target

and lower_var_address name =
  let local = lookup_var_maybe name in
  match local with
  | None ->
      let func = lookup_function name in
      if func then ([], OFunction name)
      else lower_non_function_address (EVar name)
  | Some _ ->
      lower_non_function_address (EVar name)

and lower_non_function_address target =
  let (instrs, lvalue) = lower_l_value target in
  match lvalue with
  | LAddress (addr, _) -> (instrs, addr)
  | LLocal (temp, ty) ->
      let aggregate_storage = is_aggregate_type_m ty in
      if aggregate_storage then (instrs, OTemp temp)
      else
        (let out = fresh_temp () in
         (list_append instrs [IAddrOf (out, temp)], OTemp out))

and lower_l_value target =
  match target with
  | EVar name ->
      let local = lookup_var_maybe name in
      (match local with
       | Some temp ->
           let ty = lookup_var_type name in
           let known_ty = require_maybe_type (lb_msg_name "unknown local type: " name) ty in
           ([], LLocal (temp, known_ty))
       | None ->
           let ty = lookup_global_type name in
           let known_ty = require_maybe_type (lb_msg_name "unknown global type: " name) ty in
           ([], LAddress (OGlobal name, known_ty)))
  | EUnary (op, ptr) ->
      if bytes_eq_str op "*" then
        (let (instrs, o) = lower_expr ptr in
         let ty = expr_type target in
         let known_ty =
           require_maybe_type (str_to_bytes "dereference has unknown pointed-to type") ty in
         (instrs, LAddress (o, known_ty)))
      else cc_throw (lb_msg_name "unsupported lvalue: " (render_expr_tag target))
  | EIndex (base, ix) ->
      let (base_instrs, base_op) = lower_expr base in
      let (ix_instrs, ix_op) = lower_expr ix in
      let elem_ty = indexed_element_type base in
      let elem_size = type_size elem_ty in
      let (scale_instrs, offset_op) = scaled_index ix_op elem_size in
      let addr = fresh_temp () in
      (list_append base_instrs
         (list_append ix_instrs
            (list_append scale_instrs [IBin (addr, irop_add, base_op, offset_op)])),
       LAddress (OTemp addr, elem_ty))
  | EPtrMember (base, field) ->
      let (base_instrs, base_op) = lower_expr base in
      let base_ty = expr_type base in
      let (field_ty, offset) = member_info base_ty field in
      let (addr_instrs, addr_op) = offset_address base_op offset in
      (list_append base_instrs addr_instrs, LAddress (addr_op, field_ty))
  | EMember (base, field) ->
      let (base_instrs, base_addr) = lower_l_value_address base in
      let base_ty = expr_type base in
      let known_base_ty =
        require_maybe_type (str_to_bytes "member base has unknown type") base_ty in
      let (field_ty, offset) = member_info (Some (CPtr known_base_ty)) field in
      let (addr_instrs, addr_op) = offset_address base_addr offset in
      (list_append base_instrs addr_instrs, LAddress (addr_op, field_ty))
  | _ -> cc_throw (lb_msg_name "unsupported lvalue: " (render_expr_tag target))

and require_maybe_type msg mty =
  match mty with
  | Some ty -> ty
  | None -> cc_throw msg

and indexed_element_type base =
  let mty = expr_type base in
  match mty with
  | Some (CPtr ty) -> ty
  | Some (CArray (ty, _)) -> ty
  | _ -> cc_throw_str "subscripted value has unknown element type"

and scaled_index index size =
  if size = 1 then ([], index)
  else
    (let scaled = fresh_temp () in
     ([IBin (scaled, irop_mul, index, OImm size)], OTemp scaled))
