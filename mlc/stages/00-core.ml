let rec emit_count n =
  if n = 0 then
    write_byte 'K'
  else
    let _ = write_byte 'O' in
    emit_count (n - 1)
in
let emit = fun ch -> write_byte ch in
let _ = emit 'O' in
let _ = emit_count 1 in
write_string "\010"
