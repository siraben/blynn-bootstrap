let rec byte n =
  n - (n / 256) * 256
in
let rec write_u32 n =
  let _ = write_byte (byte n) in
  let _ = write_byte (byte (n / 256)) in
  let _ = write_byte (byte (n / 65536)) in
  write_byte (byte (n / 16777216))
in
let rec emit_const n =
  let _ = write_byte 1 in
  write_u32 n
in
let rec emit_call_write_byte dummy =
  let _ = write_byte 14 in
  let _ = write_u32 1 in
  write_u32 1
in
let rec emit_push dummy =
  write_byte 2
in
let rec emit_add dummy =
  write_byte 5
in
let rec emit_halt dummy =
  write_byte 0
in
let rec is_space ch =
  if ch = 32 then 1 else
  if ch = 9 then 1 else
  if ch = 10 then 1 else
  if ch = 13 then 1 else 0
in
let rec is_digit ch =
  if ch < 48 then 0 else if ch > 57 then 0 else 1
in
let rec skip_space ch =
  if is_space ch then skip_space read_byte else ch
in
let rec expect want =
  fun ch ->
  if ch = want then read_byte else exit 1
in
let rec expect_word_rite_byte ch =
  let ch = expect 114 ch in
  let ch = expect 105 ch in
  let ch = expect 116 ch in
  let ch = expect 101 ch in
  let ch = expect 95 ch in
  let ch = expect 98 ch in
  let ch = expect 121 ch in
  let ch = expect 116 ch in
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
let rec emit_join a =
  fun b ->
  fun dummy ->
  let _ = a 0 in
  b 0
in
let rec parse_atom ch =
  fun kon ->
  let ch = skip_space ch in
  number ch (fun n -> fun ch ->
  kon 5 (fun dummy -> emit_const n) ch)
in
let rec parse_expr_tail left_len =
  fun left_emit ->
  fun ch ->
  fun kon ->
  let ch = skip_space ch in
  if ch = 43 then
    parse_atom read_byte (fun right_len -> fun right_emit -> fun ch ->
    parse_expr_tail
      (left_len + 1 + right_len + 1)
      (emit_join (emit_join left_emit emit_push) (emit_join right_emit emit_add))
      ch
      kon)
  else
    kon left_len left_emit ch
in
let rec parse_expr ch =
  fun kon ->
  parse_atom ch (fun left_len -> fun left_emit -> fun ch ->
  parse_expr_tail left_len left_emit ch kon)
in
let rec parse_stmt ch =
  fun kon ->
  let ch = expect 119 (skip_space ch) in
  let ch = expect_word_rite_byte ch in
  parse_expr ch (fun expr_len -> fun expr_emit -> fun ch ->
  kon
    (expr_len + 9)
    (emit_join expr_emit emit_call_write_byte)
    ch)
in
let rec parse_program ch =
  fun total_len ->
  fun total_emit ->
  fun kon ->
  let ch = skip_space ch in
  if ch = -1 then
    kon (total_len + 1) (emit_join total_emit emit_halt)
  else
    parse_stmt ch (fun stmt_len -> fun stmt_emit -> fun ch ->
    let next_emit = emit_join total_emit stmt_emit in
    let next_len = total_len + stmt_len in
    let ch = skip_space ch in
    if ch = 59 then
      parse_program read_byte next_len next_emit kon
    else
      if ch = -1 then
        kon (next_len + 1) (emit_join next_emit emit_halt)
      else
        exit 1)
in
parse_program read_byte 0 (fun dummy -> 0) (fun code_len -> fun code_emit ->
let _ = write_byte 77 in
let _ = write_byte 90 in
let _ = write_byte 66 in
let _ = write_byte 67 in
let _ = write_u32 1 in
let _ = write_u32 code_len in
let _ = write_u32 3 in
let _ = write_u32 0 in
code_emit 0)
