let rec byte n =
  n - (n / 256) * 256
in
let rec write_u32 n =
  let _ = write_byte (byte n) in
  let _ = write_byte (byte (n / 256)) in
  let _ = write_byte (byte (n / 65536)) in
  write_byte (byte (n / 16777216))
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
  let start = skip_space ch in
  if is_digit start then
    number_loop (start - 48) read_byte kon
  else
    exit 1
in
let rec emit_header ch =
  let ch = expect 40 (skip_space ch) in
  number ch (fun code_len -> fun ch ->
  number ch (fun prim_count -> fun ch ->
  number ch (fun global_count -> fun ch ->
  let ch = expect 41 (skip_space ch) in
  let _ = write_byte 77 in
  let _ = write_byte 90 in
  let _ = write_byte 66 in
  let _ = write_byte 67 in
  let _ = write_u32 1 in
  let _ = write_u32 code_len in
  let _ = write_u32 prim_count in
  let _ = write_u32 global_count in
  ch)))
in
let rec emit_const ch =
  number ch (fun n -> fun ch ->
  let ch = expect 41 (skip_space ch) in
  let _ = write_byte 1 in
  let _ = write_u32 n in
  ch)
in
let rec emit_prim ch =
  number ch (fun argc -> fun ch ->
  number ch (fun prim -> fun ch ->
  let ch = expect 41 (skip_space ch) in
  let _ = write_byte 14 in
  let _ = write_u32 argc in
  let _ = write_u32 prim in
  ch))
in
let rec emit_halt ch =
  let ch = expect 41 (skip_space ch) in
  let _ = write_byte 0 in
  ch
in
let rec item ch =
  let ch = expect 40 (skip_space ch) in
  let tag = skip_space ch in
  if tag = 99 then
    emit_const read_byte
  else if tag = 112 then
    emit_prim read_byte
  else if tag = 104 then
    emit_halt read_byte
  else
    exit 1
in
let rec items ch =
  let ch = skip_space ch in
  if ch = -1 then
    0
  else
    items (item ch)
in
let ch = emit_header read_byte in
items ch
