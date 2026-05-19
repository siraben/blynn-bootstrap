let rec first n = if n == 0 then 79 else second (n - 1)
and second n = if n == 0 then 88 else third (n - 1)
and third n = if n == 0 then 75 else first (n - 1)
in
let _ = write_byte (first 3) in
let _ = write_byte (third 0) in
write_byte 10
