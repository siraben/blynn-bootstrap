let rec byte n =
  n - (n / 256) * 256
in
let rec write_u32 n =
  let _ = write_byte (byte n) in
  let _ = write_byte (byte (n / 256)) in
  let _ = write_byte (byte (n / 65536)) in
  write_byte (byte (n / 16777216))
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
let rec emit_getfield_dyn dummy = write_byte 25 in
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
    ident_loop (acc * 131 + ch) read_byte kon
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
let rec empty_env key = -1 in
let rec extend_env key =
  fun old ->
  fun query ->
  if query = key then 0 else
  let found = old query in
  if found < 0 then -1 else found + 1
in
let rec empty_funcs key = -1 in
let rec extend_func key =
  fun target ->
  fun old ->
  fun query ->
  if query = key then target else old query
in
let rec atom_start ch =
  let ch = skip_space ch in
  if ch = 40 then 1 else
  if ch = 39 then 1 else
  if ch = 34 then 1 else
  if ch = 45 then 1 else
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
      let ch = expect 101 read_byte in
      let ch = expect 116 ch in
      ident ch (fun name -> fun ch ->
      if name = 1969684 then
        ident ch (fun fname -> fun ch ->
        ident ch (fun param -> fun ch ->
        let ch = expect 61 (skip_space ch) in
        let target = base + 5 in
        let rec_funcs = extend_func fname target funcs in
        compile 0 ch (extend_env param empty_env) rec_funcs (target + 1) (fun fn_body_len -> fun fn_body_emit -> fun ch ->
        let fn_len = fn_body_len + 7 in
        let ch = expect 105 (skip_space ch) in
        let ch = expect 110 ch in
        compile 0 ch env rec_funcs (base + 5 + fn_len) (fun body_len -> fun body_emit -> fun ch ->
        kon
          (5 + fn_len + body_len)
          (emit3 (emit1 11 fn_len) (emit3 emit_push fn_body_emit (emit2 emit_pop1 emit_return)) body_emit)
          ch))))
      else
        let ch = expect 61 (skip_space ch) in
        compile 0 ch env funcs base (fun rhs_len -> fun rhs_emit -> fun ch ->
        let ch = expect 105 (skip_space ch) in
        let ch = expect 110 ch in
        compile 0 ch (extend_env name env) funcs (base + rhs_len + 1) (fun body_len -> fun body_emit -> fun ch ->
        kon (rhs_len + 1 + body_len + 5) (emit3 rhs_emit emit_push (emit2 body_emit emit_pop1)) ch)))
    else if ch = 105 then
      let ch = expect 102 read_byte in
      compile 0 ch env funcs base (fun cond_len -> fun cond_emit -> fun ch ->
      let ch = expect 116 (skip_space ch) in
      let ch = expect 104 ch in
      let ch = expect 101 ch in
      let ch = expect 110 ch in
      compile 0 ch env funcs (base + cond_len + 5) (fun then_len -> fun then_emit -> fun ch ->
      let ch = expect 101 (skip_space ch) in
      let ch = expect 108 ch in
      let ch = expect 115 ch in
      let ch = expect 101 ch in
      compile 0 ch env funcs (base + cond_len + 5 + then_len + 5) (fun else_len -> fun else_emit -> fun ch ->
      kon
        (cond_len + 5 + then_len + 5 + else_len)
        (emit3 cond_emit (emit1 13 (then_len + 5)) (emit3 then_emit (emit1 11 else_len) else_emit))
        ch)))
    else if ch = 119 then
      let ch = expect 114 read_byte in
      let ch = expect 105 ch in
      let ch = expect 116 ch in
      let ch = expect 101 ch in
      let ch = expect 95 ch in
      let next = ch in
      if next = 98 then
        let ch = expect 121 read_byte in
        let ch = expect 116 ch in
        let ch = expect 101 ch in
        compile 2 ch env funcs base (fun expr_len -> fun expr_emit -> fun ch ->
        kon (expr_len + 9) (emit2 expr_emit emit_call_write_byte) ch)
      else if next = 115 then
        let ch = expect 116 read_byte in
        let ch = expect 114 ch in
        let ch = expect 105 ch in
        let ch = expect 110 ch in
        let ch = expect 103 ch in
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
        exit 1
    else if ch = 101 then
      let ch = expect 120 read_byte in
      let ch = expect 105 ch in
      let ch = expect 116 ch in
      compile 2 ch env funcs base (fun expr_len -> fun expr_emit -> fun ch ->
      kon (expr_len + 9) (emit2 expr_emit emit_call_exit) ch)
    else
      compile 2 ch env funcs base kon
  else if mode = 2 then
    compile 3 ch env funcs base (fun left_len -> fun left_emit -> fun ch ->
    let ch = skip_space ch in
    if ch = 61 then
      let ch = expect 61 read_byte in
      compile 3 ch env funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
      kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 9))) ch)
    else if ch = 33 then
      let ch = expect 61 read_byte in
      compile 3 ch env funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
      kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 19))) ch)
    else if ch = 60 then
      let next = read_byte in
      if next = 61 then
        compile 3 read_byte env funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 20))) ch)
      else
        compile 3 next env funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 10))) ch)
    else if ch = 62 then
      let next = read_byte in
      if next = 61 then
        compile 3 read_byte env funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        kon (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 22))) ch)
      else
        compile 3 next env funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
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
        compile 4 read_byte env funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        tail (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 5))) ch)
      else if ch = 45 then
        compile 4 read_byte env funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
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
        compile 5 read_byte env funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
        tail (left_len + 1 + right_len + 1) (emit3 left_emit emit_push (emit2 right_emit (emit0 7))) ch)
      else if ch = 47 then
        compile 5 read_byte env funcs (base + left_len + 1) (fun right_len -> fun right_emit -> fun ch ->
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
          compile 2 read_byte env funcs (base + left_len + 1) (fun index_len -> fun index_emit -> fun ch ->
          let ch = expect 93 (skip_space ch) in
          tail
            (left_len + 1 + index_len + 1)
            (emit3 left_emit emit_push (emit2 index_emit emit_getfield_dyn))
            ch)
        else if next = 40 then
          compile 2 read_byte env funcs (base + left_len + 1) (fun index_len -> fun index_emit -> fun ch ->
          let ch = expect 41 (skip_space ch) in
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
      compile 0 read_byte env funcs base (fun len -> fun emit -> fun ch ->
      let ch = expect 41 (skip_space ch) in
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
    else if ch = 114 then
      let ch = expect 101 read_byte in
      let ch = expect 97 ch in
      let ch = expect 100 ch in
      let ch = expect 95 ch in
      let ch = expect 98 ch in
      let ch = expect 121 ch in
      let ch = expect 116 ch in
      let ch = expect 101 ch in
      kon 14 (emit2 (emit_const 0) (emit_call_prim 0)) ch
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
      let ch = skip_space ch in
      let target = funcs name in
      if target < 0 then
        let depth = env name in
        if depth < 0 then exit 1 else
        kon 5 (emit_acc depth) ch
      else if atom_start ch then
        compile 6 ch env funcs base (fun arg_len -> fun arg_emit -> fun ch ->
        kon (arg_len + 5) (emit2 arg_emit (emit_call target)) ch)
      else
        let depth = env name in
        if depth < 0 then exit 1 else
        kon 5 (emit_acc depth) ch)
  else
    exit 1
in
compile 0 read_byte empty_env empty_funcs 0 (fun code_len0 -> fun code_emit0 -> fun ch ->
let ch = skip_space ch in
if ch = -1 then
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
