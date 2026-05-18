let rec byte n =
  n - (n / 256) * 256
in
let rec byte_u n =
  if n < 0 then byte (n + 256) else byte n
in
let rec div256 n =
  if n < 0 then (n - 255) / 256 else n / 256
in
let rec write_u32 n =
  let n1 = div256 n in
  let n2 = div256 n1 in
  let n3 = div256 n2 in
  let _ = write_byte (byte_u n) in
  let _ = write_byte (byte_u n1) in
  let _ = write_byte (byte_u n2) in
  write_byte (byte_u n3)
in
let rec emit0 op =
  fun dummy -> write_byte op
in
let rec emit1 op =
  fun n ->
  fun dummy ->
  let _ = write_byte op in
  write_u32 n
in
let rec emit2 a =
  fun b ->
  fun dummy ->
  let _ = a 0 in
  b 0
in
let rec emit3 a =
  fun b ->
  fun c ->
  emit2 (emit2 a b) c
in
let rec emit_const n = emit1 1 n in
let rec emit_push dummy = write_byte 2 in
let rec emit_pop1 dummy =
  let _ = write_byte 3 in
  write_u32 1
in
let rec emit_acc n = emit1 4 n in
let rec emit_call target = emit1 23 target in
let rec emit_return dummy = write_byte 24 in
let rec emit_closure target = emit1 29 target in
let rec emit_apply dummy = write_byte 30 in
let rec emit_return_frame dummy = write_byte 31 in
let rec emit_function target = emit1 32 target in
let rec emit_closure_n target =
  fun count ->
  fun dummy ->
  let _ = write_byte 33 in
  let _ = write_u32 target in
  write_u32 count
in
let rec emit_closure_skip target =
  fun count ->
  fun skip ->
  fun dummy ->
  let _ = write_byte 34 in
  let _ = write_u32 target in
  let _ = write_u32 count in
  write_u32 skip
in
let rec emit_call_prim prim =
  fun dummy ->
  let _ = write_byte 14 in
  let _ = write_u32 1 in
  write_u32 prim
in
let rec emit_call_write_byte dummy = emit_call_prim 1 dummy in
let rec emit_call_exit dummy = emit_call_prim 2 dummy in
let rec emit_makeblock size =
  fun dummy ->
  let _ = write_byte 15 in
  let _ = write_u32 0 in
  write_u32 size
in
let rec emit_makeblock_dyn dummy =
  let _ = write_byte 28 in
  write_u32 0
in
let rec emit_getfield n = emit1 16 n in
let rec emit_getfield_dyn dummy = write_byte 25 in
let rec emit_setfield_dyn dummy = write_byte 26 in
let rec is_space ch =
  if ch = 32 then 1 else
  if ch = 9 then 1 else
  if ch = 10 then 1 else
  if ch = 13 then 1 else 0
in
let rec is_digit ch =
  if ch < 48 then 0 else if ch > 57 then 0 else 1
in
let rec is_ident ch =
  if 48 <= ch then
    if ch <= 57 then 1 else
    if 65 <= ch then
      if ch <= 90 then 1 else
      if ch = 95 then 1 else
      if 97 <= ch then if ch <= 122 then 1 else 0 else 0
    else
      if ch = 95 then 1 else 0
  else
    0
in
let rec skip_space ch =
  if is_space ch then skip_space read_byte else ch
in
let rec expect want =
  fun ch ->
  if ch = want then read_byte else exit 1
in
let rec pack_token kind =
  fun ch ->
  0 - (kind * 1000 + ch + 2)
in
let rec is_token kind =
  fun ch ->
  let code = 0 - ch in
  if code < kind * 1000 then 0 else
  if code < kind * 1000 + 1000 then 1 else 0
in
let rec token_char kind =
  fun ch ->
  (0 - ch) - kind * 1000 - 2
in
let rec expect_in ch =
  let ch = skip_space ch in
  if is_token 1 ch then token_char 1 ch else
  let ch = expect 105 ch in
  expect 110 ch
in
let rec expect_then ch =
  let ch = skip_space ch in
  if is_token 2 ch then token_char 2 ch else
  let ch = expect 116 ch in
  let ch = expect 104 ch in
  let ch = expect 101 ch in
  expect 110 ch
in
let rec expect_else ch =
  let ch = skip_space ch in
  if is_token 3 ch then token_char 3 ch else
  let ch = expect 101 ch in
  let ch = expect 108 ch in
  let ch = expect 115 ch in
  expect 101 ch
in
let rec number_loop acc =
  fun ch ->
  fun kon ->
  if is_digit ch then
    number_loop (acc * 10 + ch - 48) read_byte kon
  else
    kon acc ch
in
let rec number ch =
  fun kon ->
  let ch = skip_space ch in
  if is_digit ch then
    number_loop (ch - 48) read_byte kon
  else
    exit 1
in
let rec ident_loop acc =
  fun ch ->
  fun kon ->
  if is_ident ch then
    ident_loop ((acc * 131 + ch) - ((acc * 131 + ch) / 1073741824) * 1073741824) read_byte kon
  else
    kon acc ch
in
let rec ident ch =
  fun kon ->
  let ch = skip_space ch in
  if is_ident ch then
    ident_loop ch read_byte kon
  else
    exit 1
in
let rec empty_env key =
  if key = (0 - 3) then 0 else
  if key = (0 - 4) then 0 else -1
in
let rec extend_env key =
  fun old ->
  fun query ->
  if query = (0 - 3) then old query + 1 else
  if query = (0 - 4) then old query else
  if query = key then 0 else
  let found = old query in
  if found < 0 then -1 else found + 1
in
let rec shift_env env =
  fun query ->
  if query = (0 - 3) then env query else
  if query = (0 - 4) then env query + 1 else
  let found = env query in
  if found < 0 then -1 else found + 1
in
let rec unshift_env env =
  let shifts = env (0 - 4) in
  fun query ->
  if query = (0 - 3) then env query else
  if query = (0 - 4) then 0 else
  let found = env query in
  if found < 0 then -1 else found - shifts
in
let rec empty_funcs key = -1 in
let rec pack_func target =
  fun captures ->
  target * 1000 + captures
in
let rec func_target packed = packed / 1000 in
let rec func_captures packed = packed - (packed / 1000) * 1000 in
let rec extend_func key =
  fun target ->
  fun captures ->
  fun old ->
  fun query ->
  if query = key then pack_func target captures else old query
in
let rec atom_start ch =
  let ch = skip_space ch in
  if ch = 40 then 1 else
  if ch = 39 then 1 else
  if ch = 34 then 1 else
  if is_digit ch then 1 else
  if is_ident ch then 1 else 0
in
let rec parse_escape ch =
  fun kon ->
  if ch = 110 then kon 10 read_byte else
  if ch = 116 then kon 9 read_byte else
  if is_digit ch then
    let d1 = ch - 48 in
    let c2 = read_byte in
    let c3 = read_byte in
    if is_digit c2 then
      if is_digit c3 then
        kon (d1 * 100 + (c2 - 48) * 10 + c3 - 48) read_byte
      else
        exit 1
    else
      exit 1
  else
    kon ch read_byte
in
let rec parse_char ch =
  fun kon ->
  if ch = 92 then
    parse_escape read_byte kon
  else
    kon ch read_byte
in
let rec compile_string_loop count =
  fun len ->
  fun emit ->
  fun ch ->
  fun kon ->
  if ch = 34 then
    if count = 0 then
      kon 14 (emit2 (emit_const 0) (emit_makeblock 0)) read_byte
    else
      kon (len + 9) (emit2 emit (emit_makeblock count)) read_byte
  else
    parse_char ch (fun value -> fun ch ->
    if count = 0 then
      compile_string_loop 1 5 (emit_const value) ch kon
    else
      compile_string_loop (count + 1) (len + 6) (emit3 emit emit_push (emit_const value)) ch kon)
in
let rec compile_string ch =
  fun kon ->
  compile_string_loop 0 0 (fun dummy -> 0) ch kon
in
let rec compile mode =
  fun ch ->
  fun env ->
  fun funcs ->
  fun base ->
  fun kon ->
  let rec compile_known_ident word =
    fun ch ->
    fun parse_env ->
    fun arg_base ->
    fun ident_kon ->
    let ch = skip_space ch in
    let packed = funcs word in
    if word = 218666133 then
      ident_kon 14 (emit2 (emit_const 0) (emit_call_prim 0)) ch
    else if packed < 0 then
      let depth = parse_env word in
      if depth < 0 then exit 1 else
      ident_kon 5 (emit_acc depth) ch
    else
      let target = func_target packed in
      let captures = func_captures packed in
      if captures = 0 then
        ident_kon 5 (emit_function target) ch
      else
        let shifts = parse_env (0 - 4) in
        let size = parse_env (0 - 3) in
        ident_kon 13 (emit_closure_skip target captures (shifts + size - captures)) ch
  in
  let rec compile_arg_or_stop ch =
    fun parse_env ->
    fun arg_base ->
    fun arg_kon ->
    fun stop_kon ->
    let ch = skip_space ch in
    if ch = 101 then
      ident ch (fun word -> fun ch ->
      if word = 228925745 then stop_kon (pack_token 3 ch)
      else compile_known_ident word ch parse_env arg_base arg_kon)
    else if ch = 105 then
      ident ch (fun word -> fun ch ->
      if word = 13865 then stop_kon (pack_token 1 ch)
      else compile_known_ident word ch parse_env arg_base arg_kon)
    else if ch = 116 then
      ident ch (fun word -> fun ch ->
      if word = 262576641 then stop_kon (pack_token 2 ch)
      else compile_known_ident word ch parse_env arg_base arg_kon)
    else if atom_start ch then
      compile 6 ch parse_env funcs arg_base arg_kon
    else
      stop_kon ch
  in
  let rec finish_ident word =
    fun ch ->
    let ch = skip_space ch in
    let packed = funcs word in
    let rec tail left_len =
      fun left_emit ->
      fun ch ->
      let ch = skip_space ch in
      if ch = 46 then
        let next = read_byte in
        if next = 91 then
          compile 2 read_byte (shift_env env) funcs (base + left_len + 1) (fun index_len -> fun index_emit -> fun ch ->
          let ch = expect 93 (skip_space ch) in
          let ch = skip_space ch in
          if ch = 60 then
            let ch = expect 45 read_byte in
            compile 1 ch (shift_env (shift_env env)) funcs (base + left_len + 1 + index_len + 1) (fun value_len -> fun value_emit -> fun ch ->
            kon
              (left_len + 1 + index_len + 1 + value_len + 1)
              (emit3 left_emit emit_push (emit3 index_emit emit_push (emit2 value_emit emit_setfield_dyn)))
              ch)
          else
            tail
              (left_len + 1 + index_len + 1)
              (emit3 left_emit emit_push (emit2 index_emit emit_getfield_dyn))
              ch)
        else if next = 40 then
          compile 2 read_byte (shift_env env) funcs (base + left_len + 1) (fun index_len -> fun index_emit -> fun ch ->
          let ch = expect 41 (skip_space ch) in
          let ch = skip_space ch in
          if ch = 60 then
            let ch = expect 45 read_byte in
            compile 1 ch (shift_env (shift_env env)) funcs (base + left_len + 1 + index_len + 1) (fun value_len -> fun value_emit -> fun ch ->
            kon
              (left_len + 1 + index_len + 1 + value_len + 1)
              (emit3 left_emit emit_push (emit3 index_emit emit_push (emit2 value_emit emit_setfield_dyn)))
              ch)
          else
            tail
              (left_len + 1 + index_len + 1)
              (emit3 left_emit emit_push (emit2 index_emit emit_getfield_dyn))
              ch)
        else
          exit 1
      else
      compile_arg_or_stop ch (shift_env env) (base + left_len + 1)
        (fun arg_len -> fun arg_emit -> fun ch ->
        tail (left_len + 1 + arg_len + 1) (emit3 left_emit emit_push (emit2 arg_emit emit_apply)) ch)
        (fun ch ->
      if ch = 43 then
        compile 4 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        tail (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 5))) ch)
      else if ch = 45 then
        compile 4 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        tail (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 6))) ch)
      else if ch = 42 then
        compile 5 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        tail (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 7))) ch)
      else if ch = 47 then
        compile 5 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        tail (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 8))) ch)
      else if ch = 61 then
        let next = read_byte in
        let ch = if next = 61 then read_byte else next in
        compile 3 ch (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 9))) ch)
      else if ch = 33 then
        let ch = expect 61 read_byte in
        compile 3 ch (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 19))) ch)
      else if ch = 60 then
        let next = read_byte in
        if next = 61 then
          compile 3 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
          kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 20))) ch)
        else
          compile 3 next (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
          kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 10))) ch)
      else if ch = 62 then
        let next = read_byte in
        if next = 61 then
          compile 3 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
          kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 22))) ch)
        else
          compile 3 next (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
          kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 21))) ch)
      else
        kon left_len left_emit ch)
    in
    if word = 218666133 then
      tail 14 (emit2 (emit_const 0) (emit_call_prim 0)) ch
    else if packed < 0 then
      let depth = env word in
      if depth < 0 then exit 1 else
      tail 5 (emit_acc depth) ch
    else
      let target = func_target packed in
      let captures = func_captures packed in
      if captures = 0 then
        compile_arg_or_stop ch env base
          (fun arg_len -> fun arg_emit -> fun ch ->
          tail (arg_len + 5) (emit2 arg_emit (emit_call target)) ch)
          (fun ch ->
          tail 5 (emit_function target) ch)
      else
        let shifts = env (0 - 4) in
        let size = env (0 - 3) in
        tail 13 (emit_closure_skip target captures (shifts + size - captures)) ch
  in
  if mode = 0 then
    compile 1 ch env funcs base (fun len -> fun emit -> fun ch ->
    let ch = skip_space ch in
    if ch = 59 then
      compile 0 read_byte env funcs (base + len) (fun rlen -> fun remit -> fun ch ->
      kon (len + rlen) (emit2 emit remit) ch)
    else
      kon len emit ch)
  else if mode = 1 then
    let ch = skip_space ch in
    if ch = 108 then
      ident ch (fun word -> fun ch ->
      if word = 1866735 then
      let ch = skip_space ch in
      if ch = 40 then
        ident read_byte (fun name1 -> fun ch ->
        let ch = expect 44 (skip_space ch) in
        ident ch (fun name2 -> fun ch ->
        let ch = expect 41 (skip_space ch) in
        let ch = expect 61 (skip_space ch) in
        compile 0 ch env funcs base (fun rhs_len -> fun rhs_emit -> fun ch ->
        let ch = expect_in ch in
        let body_base = base + rhs_len + 1 + 5 + 5 + 1 + 5 + 5 + 1 in
        let body_env = extend_env name2 (extend_env name1 (shift_env env)) in
        compile 0 ch body_env funcs body_base (fun body_len -> fun body_emit -> fun ch ->
        kon
          (rhs_len + 1 + 5 + 5 + 1 + 5 + 5 + 1 + body_len + 5)
          (emit3
            rhs_emit
            (emit3 emit_push (emit3 (emit_acc 0) (emit_getfield 0) emit_push) (emit3 (emit_acc 1) (emit_getfield 1) emit_push))
            (emit2 body_emit (emit1 3 3)))
          ch))))
      else
      ident ch (fun name -> fun ch ->
      if name = 1969684 then
        ident ch (fun fname -> fun ch ->
        ident ch (fun param -> fun ch ->
        let ch = expect 61 (skip_space ch) in
        let target = base + 5 in
        let close_env = unshift_env env in
        let captures = close_env (0 - 3) in
        let rec_funcs = extend_func fname target captures funcs in
        let body_base = if captures = 0 then target + 1 else target in
        compile 0 ch (extend_env param close_env) rec_funcs body_base (fun fn_body_len -> fun fn_body_emit -> fun ch ->
        let fn_len = if captures = 0 then fn_body_len + 7 else fn_body_len + 1 in
        let ch = expect_in ch in
        compile 0 ch env rec_funcs (base + 5 + fn_len) (fun body_len -> fun body_emit -> fun ch ->
        if captures = 0 then
          kon
            (5 + fn_len + body_len)
            (emit3 (emit1 11 fn_len) (emit3 emit_push fn_body_emit (emit2 emit_pop1 emit_return)) body_emit)
            ch
        else
          kon
            (5 + fn_len + body_len)
            (emit3 (emit1 11 fn_len) (emit2 fn_body_emit emit_return_frame) body_emit)
            ch))))
      else
        let ch = expect 61 (skip_space ch) in
        compile 0 ch env funcs base (fun rhs_len -> fun rhs_emit -> fun ch ->
        let ch = expect_in ch in
        compile 0 ch (extend_env name env) funcs (base + rhs_len + 1) (fun body_len -> fun body_emit -> fun ch ->
        kon (rhs_len + 1 + body_len + 5) (emit3 rhs_emit emit_push (emit2 body_emit emit_pop1)) ch)))
      else
        finish_ident word ch)
    else if ch = 105 then
      ident ch (fun word -> fun ch ->
      if word = 13857 then
      compile 0 ch env funcs base (fun cond_len -> fun cond_emit -> fun ch ->
      let ch = expect_then ch in
      compile 0 ch env funcs (base + cond_len + 5) (fun then_len -> fun then_emit -> fun ch ->
      let ch = expect_else ch in
      compile 0 ch env funcs (base + cond_len + 5 + then_len + 5) (fun else_len -> fun else_emit -> fun ch ->
      kon
        (cond_len + 5 + then_len + 5 + else_len)
        (emit3 cond_emit (emit1 13 (then_len + 5)) (emit3 then_emit (emit1 11 else_len) else_emit))
        ch)))
      else
        finish_ident word ch)
    else if ch = 102 then
      ident ch (fun word -> fun ch ->
      if word = 1765859 then
      ident ch (fun param -> fun ch ->
      let ch = expect 45 (skip_space ch) in
      let ch = expect 62 ch in
      let target = base + 5 in
      let close_env = unshift_env env in
      let captures = close_env (0 - 3) in
      let shifts = env (0 - 4) in
      compile 0 ch (extend_env param close_env) funcs target (fun body_len -> fun body_emit -> fun ch ->
      kon
        (5 + body_len + 1 + 13)
        (emit3 (emit1 11 (body_len + 1)) (emit2 body_emit emit_return_frame) (emit_closure_skip target captures shifts))
        ch))
      else
        finish_ident word ch)
    else if ch = 119 then
      ident ch (fun word -> fun ch ->
      if word = 137000532 then
        compile 2 ch env funcs base (fun expr_len -> fun expr_emit -> fun ch ->
        kon (expr_len + 9) (emit2 expr_emit emit_call_write_byte) ch)
      else if word = 37175713 then
        let ch = expect 34 (skip_space ch) in
        let rec string_out total_len =
          fun total_emit ->
          fun ch ->
          if ch = 34 then
            kon total_len total_emit read_byte
          else
            parse_char ch (fun value -> fun ch ->
            string_out (total_len + 14) (emit2 total_emit (emit2 (emit_const value) emit_call_write_byte)) ch)
        in
        string_out 0 (fun dummy -> 0) ch
      else
        finish_ident word ch)
    else if ch = 101 then
      ident ch (fun word -> fun ch ->
      if word = 229130382 then
        compile 2 ch env funcs base (fun expr_len -> fun expr_emit -> fun ch ->
        kon (expr_len + 9) (emit2 expr_emit emit_call_exit) ch)
      else
        finish_ident word ch)
    else if 97 <= ch then
      if ch <= 122 then
        ident ch (fun word -> fun ch ->
        finish_ident word ch)
      else
        compile 2 ch env funcs base kon
    else if ch = 95 then
      ident ch (fun word -> fun ch ->
      finish_ident word ch)
    else
      compile 2 ch env funcs base kon
  else if mode = 2 then
    compile 3 ch env funcs base (fun left_len -> fun left_emit -> fun ch ->
    let ch = skip_space ch in
    if ch = 61 then
      let next = read_byte in
      let ch = if next = 61 then read_byte else next in
      compile 3 ch (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
      kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 9))) ch)
    else if ch = 33 then
      let ch = expect 61 read_byte in
      compile 3 ch (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
      kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 19))) ch)
    else if ch = 60 then
      let next = read_byte in
      if next = 61 then
        compile 3 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 20))) ch)
      else
        compile 3 next (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 10))) ch)
    else if ch = 62 then
      let next = read_byte in
      if next = 61 then
        compile 3 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 22))) ch)
      else
        compile 3 next (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 21))) ch)
    else
      kon left_len left_emit ch)
  else if mode = 3 then
    compile 4 ch env funcs base (fun left_len -> fun left_emit -> fun ch ->
    let rec tail left_len =
      fun left_emit ->
      fun ch ->
      let ch = skip_space ch in
      if ch = 43 then
        compile 4 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        tail (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 5))) ch)
      else if ch = 45 then
        compile 4 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        tail (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 6))) ch)
      else
        kon left_len left_emit ch
    in
    tail left_len left_emit ch)
  else if mode = 4 then
    compile 5 ch env funcs base (fun left_len -> fun left_emit -> fun ch ->
    let rec tail left_len =
      fun left_emit ->
      fun ch ->
      let ch = skip_space ch in
      if ch = 42 then
        compile 5 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        tail (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 7))) ch)
      else if ch = 47 then
        compile 5 read_byte (shift_env env) funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        tail (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 8))) ch)
      else
        kon left_len left_emit ch
    in
    tail left_len left_emit ch)
  else if mode = 5 then
    compile 6 ch env funcs base (fun left_len -> fun left_emit -> fun ch ->
    let rec tail left_len =
      fun left_emit ->
      fun ch ->
      let ch = skip_space ch in
      if ch = 46 then
        let next = read_byte in
        if next = 91 then
          compile 2 read_byte (shift_env env) funcs (base + left_len + 1) (fun index_len -> fun index_emit -> fun ch ->
          let ch = expect 93 (skip_space ch) in
          let ch = skip_space ch in
          if ch = 60 then
            let ch = expect 45 read_byte in
            compile 1 ch (shift_env (shift_env env)) funcs (base + left_len + 1 + index_len + 1) (fun value_len -> fun value_emit -> fun ch ->
            kon
              (left_len + 1 + index_len + 1 + value_len + 1)
              (emit3 left_emit emit_push (emit3 index_emit emit_push (emit2 value_emit emit_setfield_dyn)))
              ch)
          else
            tail
              (left_len + 1 + index_len + 1)
              (emit3 left_emit emit_push (emit2 index_emit emit_getfield_dyn))
              ch)
        else if next = 40 then
          compile 2 read_byte (shift_env env) funcs (base + left_len + 1) (fun index_len -> fun index_emit -> fun ch ->
          let ch = expect 41 (skip_space ch) in
          let ch = skip_space ch in
          if ch = 60 then
            let ch = expect 45 read_byte in
            compile 1 ch (shift_env (shift_env env)) funcs (base + left_len + 1 + index_len + 1) (fun value_len -> fun value_emit -> fun ch ->
            kon
              (left_len + 1 + index_len + 1 + value_len + 1)
              (emit3 left_emit emit_push (emit3 index_emit emit_push (emit2 value_emit emit_setfield_dyn)))
              ch)
          else
            tail
              (left_len + 1 + index_len + 1)
              (emit3 left_emit emit_push (emit2 index_emit emit_getfield_dyn))
              ch)
        else
          exit 1
      else
        kon left_len left_emit ch
    in
    tail left_len left_emit ch)
  else if mode = 6 then
    let ch = skip_space ch in
    if ch = 40 then
      let ch = skip_space read_byte in
      compile 0 ch env funcs base (fun len -> fun emit -> fun ch ->
      let ch = skip_space ch in
      if ch = 44 then
        compile 0 read_byte (shift_env env) funcs (base + len + 1) (fun right_len -> fun right_emit -> fun ch ->
        let ch = expect 41 (skip_space ch) in
        kon
          (len + 1 + right_len + 9)
          (emit3 emit emit_push (emit2 right_emit (emit_makeblock 2)))
          ch)
      else
        let ch = expect 41 ch in
        kon len emit ch)
    else if ch = 39 then
      parse_char read_byte (fun value -> fun ch ->
      let ch = expect 39 ch in
      kon 5 (emit_const value) ch)
    else if ch = 34 then
      compile_string read_byte (fun len -> fun emit -> fun ch ->
      kon len emit ch)
    else if ch = 45 then
      number read_byte (fun n -> fun ch ->
      kon 5 (emit_const (0 - n)) ch)
    else if is_digit ch then
      number ch (fun n -> fun ch ->
      kon 5 (emit_const n) ch)
    else if ch = 65 then
      let ch = expect 114 read_byte in
      let ch = expect 114 ch in
      let ch = expect 97 ch in
      let ch = expect 121 ch in
      let ch = expect 46 ch in
      let ch = expect 99 ch in
      let ch = expect 114 ch in
      let ch = expect 101 ch in
      let ch = expect 97 ch in
      let ch = expect 116 ch in
      let ch = expect 101 ch in
      compile 5 ch env funcs base (fun size_len -> fun size_emit -> fun ch ->
      compile 5 ch env funcs (base + size_len + 1) (fun init_len -> fun init_emit -> fun ch ->
      kon
        (size_len + 1 + init_len + 5)
        (emit3 size_emit emit_push (emit2 init_emit emit_makeblock_dyn))
        ch))
    else if ch = 114 then
      ident ch (fun word -> fun ch ->
      compile_known_ident word ch env base kon)
    else if ch = 66 then
      let ch = expect 121 read_byte in
      let ch = expect 116 ch in
      let ch = expect 101 ch in
      let ch = expect 115 ch in
      let ch = expect 46 ch in
      let next = ch in
      if next = 108 then
        let ch = expect 101 read_byte in
        let ch = expect 110 ch in
        let ch = expect 103 ch in
        let ch = expect 116 ch in
        let ch = expect 104 ch in
        compile 5 ch env funcs base (fun len -> fun emit -> fun ch ->
        kon (len + 1) (emit2 emit (emit0 27)) ch)
      else if next = 99 then
        let ch = expect 114 read_byte in
        let ch = expect 101 ch in
        let ch = expect 97 ch in
        let ch = expect 116 ch in
        let ch = expect 101 ch in
        compile 5 ch env funcs base (fun len -> fun emit -> fun ch ->
        kon (len + 1 + 5 + 5) (emit3 emit emit_push (emit2 (emit_const 0) emit_makeblock_dyn)) ch)
      else
        exit 1
    else if ch = 83 then
      let ch = expect 116 read_byte in
      let ch = expect 114 ch in
      let ch = expect 105 ch in
      let ch = expect 110 ch in
      let ch = expect 103 ch in
      let ch = expect 46 ch in
      let ch = expect 108 ch in
      let ch = expect 101 ch in
      let ch = expect 110 ch in
      let ch = expect 103 ch in
      let ch = expect 116 ch in
      let ch = expect 104 ch in
      compile 5 ch env funcs base (fun len -> fun emit -> fun ch ->
      kon (len + 1) (emit2 emit (emit0 27)) ch)
    else
      ident ch (fun name -> fun ch ->
      compile_known_ident name ch env base kon)
  else
    exit 1
in
compile 0 read_byte empty_env empty_funcs 0 (fun code_len0 -> fun code_emit0 -> fun ch ->
let ch = skip_space ch in
if ch < 0 then
  let code_len = code_len0 + 1 in
  let code_emit = emit2 code_emit0 (emit0 0) in
  let _ = write_byte 77 in
  let _ = write_byte 90 in
  let _ = write_byte 66 in
  let _ = write_byte 67 in
  let _ = write_u32 1 in
  let _ = write_u32 code_len in
  let _ = write_u32 3 in
  let _ = write_u32 0 in
  code_emit 0
else
  exit 1)
