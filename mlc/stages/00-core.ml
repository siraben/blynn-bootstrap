let rec emit_count n =
  if n = 0 then
    write_byte 75
  else
    let _ = write_byte 79 in
    emit_count (n - 1)
in
let emit = fun ch -> write_byte ch in
let _ = emit 79 in
let _ = emit_count 1 in
write_byte 10
