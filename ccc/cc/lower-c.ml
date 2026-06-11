(* ccc part 54 (segment c): expression typing, type layout and global
   data; port of Hcc.Lower lines 1304-2184 (exprType .. isUnsignedType).
   Continues the mutually recursive Lower group started in lower-a.ml:
   only `and` definitions here. *)

and expr_type expr =
  match expr with
  | EInt _ -> Some CInt
  | EFloat text -> Some (float_literal_type text)
  | EChar _ -> Some CInt
  | EString _ -> Some (CPtr CChar)
  | ESizeofType _ -> Some CInt
  | ESizeofExpr _ -> Some CInt
  | EVar name ->
      if is_function_name_macro name then Some (CPtr CChar)
      else
        (match lookup_var_type name with
         | Some ty -> Some ty
         | None ->
             (match lookup_function_type name with
              | Some ty -> Some ty
              | None -> lookup_global_type name))
  | ECast (ty, _) -> Some ty
  | EUnary (op, value) ->
      if bytes_eq_str op "+" then
        (let mty = expr_type value in
         promote_maybe_integer_type mty)
      else if bytes_eq_str op "-" then
        (let mty = expr_type value in
         promote_maybe_integer_type mty)
      else if bytes_eq_str op "~" then
        (let mty = expr_type value in
         promote_maybe_integer_type mty)
      else if bytes_eq_str op "!" then Some CInt
      else if bytes_eq_str op "*" then
        (let mty = expr_type value in
         match mty with
         | Some (CPtr ty) -> Some ty
         | Some (CArray (ty, _)) -> Some ty
         | _ -> None)
      else if bytes_eq_str op "&" then
        (let mty = expr_type value in
         maybe_ptr_type mty)
      else if bytes_eq_str op "++" then expr_type value
      else if bytes_eq_str op "--" then expr_type value
      else None
  | EIndex (base, _) ->
      (let mty = expr_type base in
       match mty with
       | Some (CPtr ty) -> Some ty
       | Some (CArray (ty, _)) -> Some ty
       | _ -> None)
  | EPtrMember (base, field) ->
      let base_ty = expr_type base in
      let info = member_info_maybe base_ty field in
      maybe_member_type info
  | EMember (base, field) ->
      let base_ty = expr_type base in
      let known_base_ty =
        require_maybe_type (str_to_bytes "member base has unknown type") base_ty in
      let info = member_info_maybe (Some (CPtr known_base_ty)) field in
      maybe_member_type info
  | EBinary (op, left, right) ->
      if bytes_eq_str op "+" then
        (let left_ty = expr_type left in
         let right_ty = expr_type right in
         let arithmetic_ty = usual_arithmetic_type left right in
         add_expr_result_type left_ty right_ty arithmetic_ty)
      else if bytes_eq_str op "-" then
        (let left_ty = expr_type left in
         let right_ty = expr_type right in
         let arithmetic_ty = usual_arithmetic_type left right in
         sub_expr_result_type left_ty right_ty arithmetic_ty)
      else if bytes_eq_str op "<<" then
        (let left_ty = expr_type left in
         promote_maybe_integer_type left_ty)
      else if bytes_eq_str op ">>" then
        (let left_ty = expr_type left in
         promote_maybe_integer_type left_ty)
      else if bytes_eq_str op "," then expr_type right
      else if bytes_eq_str op "&&" then Some CInt
      else if bytes_eq_str op "||" then Some CInt
      else if is_comparison_op_string op ||
              bytes_eq_str op "==" || bytes_eq_str op "!=" then Some CInt
      else
        (let left_ty = expr_type left in
         let right_ty = expr_type right in
         let arithmetic_ty = usual_arithmetic_type left right in
         if bytes_eq_str op "*" || bytes_eq_str op "/" || bytes_eq_str op "%" ||
            bytes_eq_str op "&" || bytes_eq_str op "|" || bytes_eq_str op "^"
         then Some arithmetic_ty
         else
           (match (left_ty, right_ty) with
            | (Some _, Some _) -> Some arithmetic_ty
            | _ -> None))
  | ECond (_, yes, no) ->
      (let yes_ty = expr_type yes in
       let no_ty = expr_type no in
       match (yes_ty, no_ty) with
       | (Some ty, None) -> Some ty
       | (None, Some ty) -> Some ty
       | (Some ty, Some _) -> Some ty
       | _ -> None)
  | EAssign (lhs, _) -> expr_type lhs
  | ECompoundAssign (_, lhs, _) -> expr_type lhs
  | EPostfix (_, value) -> expr_type value
  | ECall (callee, _) ->
      (match callee with
       | EVar name ->
           (match lookup_var_type name with
            | Some ty -> function_result_type ty
            | None ->
                (match lc_function_result_of (lookup_function_type name) with
                 | Some ret_ty -> Some ret_ty
                 | None ->
                     (match lc_function_result_of (lookup_global_type name) with
                      | Some ret_ty -> Some ret_ty
                      | None ->
                          (let is_function = lookup_function name in
                           if is_function then Some CLong else None))))
       | _ -> lc_function_result_of (expr_type callee))
  | _ -> None

(* Haskell's `functionResultType =<< maybeTy` *)
and lc_function_result_of mty =
  match mty with
  | Some ty -> function_result_type ty
  | None -> None

and promote_maybe_integer_type mty =
  match mty with
  | None -> None
  | Some ty ->
      let promoted = promote_integer_type ty in
      Some promoted

and maybe_ptr_type mty =
  match mty with
  | None -> None
  | Some ty -> Some (CPtr ty)

and function_result_type ty =
  match ty with
  | CFunc (ret, _) -> Some ret
  | CPtr inner -> function_result_type inner
  | _ -> None

and is_function_name_macro name =
  bytes_eq_str name "__func__" || bytes_eq_str name "__FUNCTION__" ||
  bytes_eq_str name "__PRETTY_FUNCTION__"

and maybe_member_type info =
  match info with
  | None -> None
  | Some (ty, _) -> Some ty

and add_expr_result_type left_ty right_ty arithmetic_ty =
  match pointer_element_type left_ty with
  | Some _ -> left_ty
  | None ->
      (match pointer_element_type right_ty with
       | Some _ -> right_ty
       | None -> Some arithmetic_ty)

and sub_expr_result_type left_ty right_ty arithmetic_ty =
  match pointer_element_type left_ty with
  | Some _ ->
      (match pointer_element_type right_ty with
       | Some _ -> Some CLong
       | None -> left_ty)
  | None -> Some arithmetic_ty

and member_info mty field =
  let found = member_info_maybe mty field in
  match found with
  | Some info -> info
  | None ->
      (let b = buf_new 64 in
       buf_add_str b "unknown struct member: ";
       buf_add_bytes b field;
       buf_add_str b " on aggregate";
       cc_throw (buf_take b))

and member_info_maybe mty field =
  match mty with
  | Some (CPtr ty) -> member_info_for_aggregate ty field
  | _ -> None

and member_info_for_aggregate ty field =
  match aggregate_cache_name ty with
  | Some name ->
      (match lookup_struct_member_cache name field with
       | Some info -> Some info
       | None ->
           (match member_info_for_aggregate_uncached ty field with
            | Some info ->
                (cache_struct_member name field info;
                 Some info)
            | None -> None))
  | None -> member_info_for_aggregate_uncached ty field

and member_info_for_aggregate_uncached ty field =
  match aggregate_fields ty with
  | None -> None
  | Some (is_union, fields) -> field_offset is_union field 0 fields

and aggregate_cache_name ty =
  match ty with
  | CStruct name -> Some name
  | CUnion name -> Some name
  | CStructNamed (name, _) -> Some name
  | CUnionNamed (name, _) -> Some name
  | CNamed name -> Some name
  | _ -> None

and field_offset is_union field offset fields =
  match fields with
  | [] -> None
  | Field (ty, name) :: rest ->
      let align = type_align ty in
      let aligned = align_up offset align in
      if bytes_eq name field then Some (ty, union_offset is_union aligned)
      else
        (let size = type_size ty in
         let nested = anonymous_member_info_for_name is_union aligned ty name field in
         match nested with
         | Some info -> Some info
         | None -> field_offset is_union field (aligned + size) rest)

and union_offset is_union aligned =
  if is_union then 0 else aligned

and anonymous_member_info_for_name is_union aligned ty name field =
  if bytes_length name = 0
  then anonymous_member_info (union_offset is_union aligned) ty field
  else None

and anonymous_member_info base_offset ty field =
  match aggregate_fields ty with
  | None -> None
  | Some (is_union, fields) -> nested_field_offset base_offset is_union field 0 fields

and nested_field_offset base_offset is_union field offset fields =
  match fields with
  | [] -> None
  | Field (field_ty, name) :: rest ->
      let align = type_align field_ty in
      let aligned = align_up offset align in
      let member_offset = base_offset + union_offset is_union aligned in
      if bytes_eq name field then Some (field_ty, member_offset)
      else
        (let size = type_size field_ty in
         let nested = anonymous_member_info_for_name false member_offset field_ty name field in
         match nested with
         | Some info -> Some info
         | None -> nested_field_offset base_offset is_union field (aligned + size) rest)

and load_instr out ty addr =
  let size = type_size ty in
  let signed = is_signed_integer_type ty in
  if size <= 1 then (if signed then ILoadS8 (out, addr) else ILoad8 (out, addr))
  else if size <= 2 then (if signed then ILoadS16 (out, addr) else ILoad16 (out, addr))
  else if size <= 4 then (if signed then ILoadS32 (out, addr) else ILoad32 (out, addr))
  else ILoad64 (out, addr)

and is_signed_integer_type ty =
  match ty with
  | CChar -> true
  | CShort -> true
  | CInt -> true
  | CLong -> true
  | CLongLong -> true
  | CEnum _ -> true
  | CNamed name -> is_signed_named_integer name
  | _ -> false

and is_integer_type_m ty =
  match ty with
  | CChar -> true
  | CShort -> true
  | CUnsignedChar -> true
  | CUnsignedShort -> true
  | CInt -> true
  | CUnsigned -> true
  | CLong -> true
  | CUnsignedLong -> true
  | CLongLong -> true
  | CUnsignedLongLong -> true
  | CBool -> true
  | CEnum _ -> true
  | CNamed name -> is_some (named_integer_size name)
  | _ -> false

and promote_integer_type ty =
  let integer = is_integer_type_m ty in
  if not integer then ty
  else
    (let size = type_size ty in
     if size < 4 then CInt else ty)

and usual_arithmetic_type left right =
  let left_ty0 = promoted_expr_type left in
  let right_ty0 = promoted_expr_type right in
  if is_floating_type left_ty0 || is_floating_type right_ty0
  then usual_floating_type left_ty0 right_ty0
  else
    (let left_ty = canonical_integer_type left_ty0 in
     let right_ty = canonical_integer_type right_ty0 in
     if integer_kind_id left_ty = integer_kind_id right_ty then left_ty
     else if is_unsigned_type left_ty = is_unsigned_type right_ty
     then higher_rank_type left_ty right_ty
     else
       (let (signed_ty, unsigned_ty) =
          if is_unsigned_type left_ty then (right_ty, left_ty)
          else (left_ty, right_ty) in
        if integer_rank unsigned_ty >= integer_rank signed_ty then unsigned_ty
        else
          (let signed_size = type_size signed_ty in
           let unsigned_size = type_size unsigned_ty in
           if signed_size > unsigned_size then signed_ty
           else corresponding_unsigned signed_ty)))

and is_floating_type ty =
  match ty with
  | CFloat -> true
  | CDouble -> true
  | CLongDouble -> true
  | _ -> false

and usual_floating_type left_ty right_ty =
  if is_long_double_type left_ty || is_long_double_type right_ty
  then CLongDouble
  else if is_double_type left_ty || is_double_type right_ty
  then CDouble
  else CFloat

and is_long_double_type ty =
  match ty with
  | CLongDouble -> true
  | _ -> false

and is_double_type ty =
  match ty with
  | CDouble -> true
  | _ -> false

and canonical_integer_type ty =
  let integer = is_integer_type_m ty in
  if not integer then ty
  else
    (match ty with
     | CInt -> ty
     | CUnsigned -> ty
     | CLong -> ty
     | CUnsignedLong -> ty
     | CLongLong -> ty
     | CUnsignedLongLong -> ty
     | _ ->
         (let size = type_size ty in
          let word = target_word_size () in
          canonical_integer_by_size size word (is_unsigned_type ty)))

and canonical_integer_by_size size word unsigned =
  if size <= 4 then (if unsigned then CUnsigned else CInt)
  else if size = word then (if unsigned then CUnsignedLong else CLong)
  else (if unsigned then CUnsignedLongLong else CLongLong)

and integer_rank ty =
  match ty with
  | CInt -> 1
  | CUnsigned -> 1
  | CLong -> 2
  | CUnsignedLong -> 2
  | CLongLong -> 3
  | CUnsignedLongLong -> 3
  | _ -> 1

and integer_kind_id ty =
  match ty with
  | CInt -> 0
  | CUnsigned -> 1
  | CLong -> 2
  | CUnsignedLong -> 3
  | CLongLong -> 4
  | CUnsignedLongLong -> 5
  | _ -> 0 - 1

and higher_rank_type a b =
  if integer_rank a >= integer_rank b then a else b

and corresponding_unsigned ty =
  match ty with
  | CInt -> CUnsigned
  | CLong -> CUnsignedLong
  | CLongLong -> CUnsignedLongLong
  | _ -> ty

and promoted_expr_type expr =
  match expr with
  | EInt text ->
      if int_literal_is_unsigned text then CUnsigned else CInt
  | EFloat text -> float_literal_type text
  | _ ->
      (let mty = expr_type expr in
       let b = buf_new 64 in
       buf_add_str b "expression has unknown type: ";
       buf_add_bytes b (render_expr_tag expr);
       let ty = require_maybe_type (buf_take b) mty in
       promote_integer_type ty)

and float_literal_type text =
  match float_literal_size text with
  | 4 -> CFloat
  | 16 -> CLongDouble
  | _ -> CDouble

and store_instr ty addr value =
  let size = type_size ty in
  if size <= 1 then IStore8 (addr, value)
  else if size <= 2 then IStore16 (addr, value)
  else if size <= 4 then IStore32 (addr, value)
  else IStore64 (addr, value)

and type_size ty =
  match ty with
  | CVoid -> 1
  | CBool -> 1
  | CChar -> 1
  | CUnsignedChar -> 1
  | CShort -> 2
  | CUnsignedShort -> 2
  | CInt -> 4
  | CUnsigned -> 4
  | CFloat -> 4
  | CLong -> target_word_size ()
  | CUnsignedLong -> target_word_size ()
  | CLongLong -> 8
  | CUnsignedLongLong -> 8
  | CDouble -> 8
  | CLongDouble -> 16
  | CPtr _ -> target_word_size ()
  | CFunc (_, _) -> target_word_size ()
  | CArray (inner, count) ->
      (let size = type_size inner in
       let bound = array_bound_size count in
       size * bound)
  | CStruct name -> struct_size name
  | CUnion name -> struct_size name
  | CStructNamed (name, fields) ->
      (bind_struct name false fields;
       aggregate_size false fields)
  | CUnionNamed (name, fields) ->
      (bind_struct name true fields;
       aggregate_size true fields)
  | CStructDef fields -> aggregate_size false fields
  | CUnionDef fields -> aggregate_size true fields
  | CEnum _ -> 4
  | CNamed name -> named_type_size name

and named_type_size name =
  match named_integer_size name with
  | Some size -> target_named_type_size name size
  | None ->
      (match lookup_struct name with
       | Some _ -> struct_size name
       | None ->
           (let b = buf_new 64 in
            buf_add_str b "unknown type: ";
            buf_add_bytes b name;
            cc_throw (buf_take b)))

and target_named_type_size name size =
  if lc_target_word_sized_name name then target_word_size () else size

(* Haskell's `name elem targetWordSizedNames` as chained tests *)
and lc_target_word_sized_name name =
  bytes_eq_str name "unsigned_long" ||
  bytes_eq_str name "size_t" ||
  bytes_eq_str name "ssize_t" ||
  bytes_eq_str name "time_t" ||
  bytes_eq_str name "ptrdiff_t" ||
  bytes_eq_str name "intptr_t" ||
  bytes_eq_str name "uintptr_t" ||
  bytes_eq_str name "addr_t"

and type_align ty =
  match ty with
  | CArray (inner, _) -> type_align inner
  | _ ->
      (let size = type_size ty in
       if size >= 8 then 8 else if size >= 4 then 4 else if size >= 2 then 2 else 1)

and struct_size name =
  match lookup_struct_size_cache name with
  | Some size -> size
  | None ->
      (match lookup_struct name with
       | None ->
           (let b = buf_new 64 in
            buf_add_str b "unknown struct or union: ";
            buf_add_bytes b name;
            cc_throw (buf_take b))
       | Some (is_union, fields) ->
           (let size = aggregate_size is_union fields in
            cache_struct_size name size;
            size))

and aggregate_size is_union fields =
  if is_union then aggregate_union_size fields
  else aggregate_struct_size fields

and aggregate_struct_size fields =
  let (size, max_align) = fold_aggregate_fields 0 1 fields in
  align_up size max_align

and fold_aggregate_fields offset max_align members =
  match members with
  | [] -> (offset, max_align)
  | Field (ty, _) :: rest ->
      let align = type_align ty in
      let size = type_size ty in
      let aligned = align_up offset align in
      fold_aggregate_fields (aligned + size) (imax max_align align) rest

and aggregate_union_size members =
  let (size, align) = union_fields members in
  align_up size align

and union_fields members =
  match members with
  | [] -> (0, 1)
  | Field (ty, _) :: rest ->
      let size = type_size ty in
      let align = type_align ty in
      let (rest_size, rest_align) = union_fields rest in
      (imax size rest_size, imax align rest_align)

and align_up offset align =
  let remnant = hmod offset align in
  if remnant = 0 then offset else offset + align - remnant

and global_data ty init_expr =
  let values = global_data_value ty init_expr in
  let size = initialized_size ty values init_expr in
  pad_data_target size values

and initialized_size ty values init_expr =
  match ty with
  | CArray (inner, count) ->
      (match count with
       | None -> initialized_unbounded_array_size inner values init_expr
       | Some _ -> type_size ty)
  | _ -> type_size ty

and initialized_unbounded_array_size inner values init_expr =
  match init_expr with
  | Some expr ->
      (match expr with
       | EInitList _ -> data_size_target values
       | EString _ ->
           (match inner with
            | CChar -> data_size_target values
            | _ -> type_size (CArray (inner, None)))
       | _ -> type_size (CArray (inner, None)))
  | None -> type_size (CArray (inner, None))

and global_data_value ty init_expr =
  match init_expr with
  | None -> zero_data_for_type ty
  | Some expr -> global_data_expr ty expr

and zero_data_for_type ty =
  let size = type_size ty in
  zero_data size

and global_data_expr ty expr =
  match expr with
  | EInitList exprs -> global_init_list_data ty exprs
  | EString text -> global_string_data ty text
  | EInt text -> scalar_data ty (parse_int text)
  | EFloat text -> scalar_float_data ty text
  | EChar text -> scalar_data ty (char_value text)
  | ECast (_, value) -> global_data_value ty (Some value)
  | EUnary (op, value) ->
      if bytes_eq_str op "&" then global_address_expr_data ty value
      else
        (let n = const_expr_value expr in
         scalar_data ty n)
  | EVar name -> global_var_data ty name
  | _ ->
      (let value = const_expr_value expr in
       scalar_data ty value)

and global_init_list_data ty exprs =
  if not (is_aggregate_type ty) && single_expr_list exprs
  then
    (match exprs with
     | expr :: _ -> global_data_value ty (Some expr)
     | [] -> zero_data_for_type ty)
  else
    (match ty with
     | CArray (inner, count) -> global_array_init_data inner count exprs
     | _ -> global_aggregate_init_data ty exprs)

and single_expr_list exprs =
  match exprs with
  | [_] -> true
  | _ -> false

and global_array_init_data inner count exprs =
  let items = global_array_data inner exprs in
  match count with
  | None -> items
  | Some bound ->
      let n = const_expr_value bound in
      let elem_size = type_size inner in
      pad_data_target (n * elem_size) items

and global_aggregate_init_data ty exprs =
  match aggregate_fields ty with
  | Some (is_union, fields) ->
      if is_union then global_union_data fields exprs
      else global_struct_data fields exprs
  | None -> zero_data_for_type ty

and global_string_data ty text =
  match ty with
  | CArray (CChar, count) ->
      (let size = string_data_size count text in
       pad_data_target size (bytes_data (string_bytes text)))
  | _ ->
      if is_pointer_type ty then
        (let data_label = fresh_data_label () in
         add_data_item (DataItem (data_label, bytes_data (string_bytes text)));
         [DAddress data_label])
      else
        (let value = const_expr_value (EString text) in
         scalar_data ty value)

and string_data_size count text =
  match count with
  | None -> list_length (string_bytes text)
  | Some bound -> const_expr_value bound

and global_address_expr_data ty value =
  match value with
  | EVar name -> global_address_data name
  | _ ->
      (let n = const_expr_value (EUnary (str_to_bytes "&", value)) in
       scalar_data ty n)

and global_var_data ty name =
  match lookup_constant name with
  | Some value -> scalar_data ty value
  | None ->
      (match builtin_constant name with
       | Some value -> scalar_data ty value
       | None -> global_address_data name)

and global_array_data inner exprs =
  match exprs with
  | [] -> []
  | expr :: rest ->
      let item = global_data_value inner (Some expr) in
      let elem_size = type_size inner in
      let tail_items = global_array_data inner rest in
      let padded = pad_data_target elem_size item in
      list_append padded tail_items

and global_struct_data fields exprs =
  let (values, used) = struct_fields 0 fields exprs in
  pad_data_target used values

and struct_fields offset remaining values =
  match remaining with
  | [] -> ([], offset)
  | Field (field_ty, _) :: rest ->
      let align = type_align field_ty in
      let aligned = align_up offset align in
      let field_size = type_size field_ty in
      let value_head = maybe_expr_head values in
      let value_tail = expr_tail values in
      let field_data = global_data_value field_ty value_head in
      let padded_field = pad_data_target field_size field_data in
      let (rest_data, end_offset) = struct_fields (aligned + field_size) rest value_tail in
      (list_append (zero_data (aligned - offset))
         (list_append padded_field rest_data),
       end_offset)

and maybe_expr_head values =
  match values with
  | [] -> None
  | expr :: _ -> Some expr

and expr_tail values =
  match values with
  | [] -> []
  | _ :: rest -> rest

and global_union_data fields exprs =
  match fields with
  | [] -> zero_union_data fields
  | Field (field_ty, _) :: _ ->
      (match exprs with
       | [] -> zero_union_data fields
       | expr :: _ ->
           (let item = global_data_value field_ty (Some expr) in
            let size = union_size_from_fields fields in
            pad_data_target size item))

and zero_union_data fields =
  let size = union_size_from_fields fields in
  zero_data size

and union_size_from_fields fields =
  match fields with
  | [] -> 0
  | Field (ty, _) :: rest ->
      let size = type_size ty in
      let tail_size = union_size_from_fields rest in
      imax size tail_size

and is_aggregate_type_m ty =
  match ty with
  | CArray (_, _) -> true
  | CNamed _ ->
      (let aggregate = aggregate_fields ty in
       is_some aggregate)
  | _ -> is_aggregate_type ty

and scalar_data ty value =
  let size = type_size ty in
  bytes_data (int_bytes size value)

and scalar_float_data ty text =
  let size = type_size ty in
  bytes_data (float_literal_bytes size text)

and pad_data_target size values =
  let used = data_size_target values in
  if used >= size then take_data_target size values
  else list_append values (zero_data (size - used))

and take_data_target size values =
  if size <= 0 then []
  else
    (match values with
     | [] -> []
     | DByte byte :: rest ->
         (let tail_values = take_data_target (size - 1) rest in
          DByte byte :: tail_values)
     | DAddress label :: rest ->
         (let word = target_word_size () in
          if size >= word then
            (let tail_values = take_data_target (size - word) rest in
             DAddress label :: tail_values)
          else zero_data size))

and data_size_target values =
  match values with
  | [] -> 0
  | DByte _ :: rest ->
      (let n = data_size_target rest in
       n + 1)
  | DAddress _ :: rest ->
      (let word = target_word_size () in
       let n = data_size_target rest in
       n + word)

and global_address_data name =
  let is_function = lookup_function name in
  if is_function then
    (let b = buf_new 32 in
     buf_add_str b "FUNCTION_";
     buf_add_bytes b name;
     [DAddress (buf_take b)])
  else [DAddress name]

and const_expr_value expr =
  match expr with
  | EInt text -> parse_int text
  | EFloat _ -> 0
  | EChar text -> char_value text
  | ESizeofType ty -> type_size ty
  | ESizeofExpr value ->
      (let mty = expr_type value in
       let ty = require_maybe_type (str_to_bytes "sizeof expression has unknown type") mty in
       type_size ty)
  | ECast (_, value) ->
      (* the offsetof idiom (ECast _ (EUnary "&" (EPtrMember (ECast (CPtr ty)
         (EInt "0")) field))) takes the member offset; otherwise the cast is
         transparent *)
      (match value with
       | EUnary (op, EPtrMember (ECast (CPtr ty, EInt zero), field)) ->
           if bytes_eq_str op "&" && bytes_eq_str zero "0" then
             (let (_, offset) = member_info (Some (CPtr ty)) field in
              offset)
           else const_expr_value value
       | _ -> const_expr_value value)
  | EUnary (op, value) ->
      if bytes_eq_str op "&" then
        (match value with
         | EPtrMember (ECast (CPtr ty, EInt zero), field) ->
             if bytes_eq_str zero "0" then
               (let (_, offset) = member_info (Some (CPtr ty)) field in
                offset)
             else lc_unsupported_const_expr expr
         | _ -> lc_unsupported_const_expr expr)
      else if bytes_eq_str op "-" then
        (let n = const_expr_value value in
         0 - n)
      else if bytes_eq_str op "+" then const_expr_value value
      else if bytes_eq_str op "~" then
        (let n = const_expr_value value in
         0 - n - 1)
      else if bytes_eq_str op "!" then
        (let n = const_expr_value value in
         if n = 0 then 1 else 0)
      else lc_unsupported_const_expr expr
  | EVar name ->
      (match lookup_constant name with
       | Some value -> value
       | None ->
           (match builtin_constant name with
            | Some value -> value
            | None ->
                (let b = buf_new 64 in
                 buf_add_str b "unknown constant: ";
                 buf_add_bytes b name;
                 cc_throw (buf_take b))))
  | EBinary (op, left, right) ->
      (let a = const_expr_value left in
       let b = const_expr_value right in
       const_bin_op op a b)
  | ECond (cond, yes, no) ->
      (let c = const_expr_value cond in
       const_expr_value (if c <> 0 then yes else no))
  | _ -> lc_unsupported_const_expr expr

and lc_unsupported_const_expr expr =
  let b = buf_new 64 in
  buf_add_str b "unsupported constant expression: ";
  buf_add_bytes b (render_expr_tag expr);
  cc_throw (buf_take b)

and array_bound_size bound =
  match bound with
  | None -> 1
  | Some expr -> const_expr_value expr

and shift_right_op expr =
  let ty = promoted_expr_type expr in
  if is_unsigned_type ty then irop_shr else irop_sar

and comparison_op op a b =
  let common_ty = usual_arithmetic_type a b in
  let unsigned = is_unsigned_type common_ty in
  if unsigned then
    (if bytes_eq_str op "<" then irop_ult
     else if bytes_eq_str op "<=" then irop_ule
     else if bytes_eq_str op ">" then irop_ugt
     else if bytes_eq_str op ">=" then irop_uge
     else irop_eq)
  else
    (if bytes_eq_str op "<" then irop_lt
     else if bytes_eq_str op "<=" then irop_le
     else if bytes_eq_str op ">" then irop_gt
     else if bytes_eq_str op ">=" then irop_ge
     else irop_eq)

and is_unsigned_type ty =
  match ty with
  | CUnsigned -> true
  | CUnsignedChar -> true
  | CUnsignedShort -> true
  | CUnsignedLong -> true
  | CUnsignedLongLong -> true
  | CBool -> true
  | CPtr _ -> true
  | CArray (_, _) -> true
  | CNamed name ->
      (match named_integer_size name with
       | Some _ -> not (is_signed_named_integer name)
       | None -> false)
  | _ -> false
