let rec first n = if n == 0 then 79 else first (n - 1) in
let rec second n = if n == 0 then first 2 - 4 else second (n - 1) in
let _ = write_byte (first 1) in
let _ = write_byte (second 3) in
write_byte 10
