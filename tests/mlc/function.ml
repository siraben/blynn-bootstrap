let rec pick n = if n == 0 then 79 else pick (n - 1) in
let _ = write_byte (pick 3) in
let _ = write_byte 75 in
write_byte 10
