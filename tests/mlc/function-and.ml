let rec even n = if n == 0 then 79 else odd (n - 1)
and odd n = if n == 0 then 88 else even (n - 1)
in
let _ = write_byte (even 4) in
let _ = write_byte (odd 4 - 13) in
write_byte 10
