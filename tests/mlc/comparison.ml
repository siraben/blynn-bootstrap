let _ = write_byte (if 3 != 4 then 79 else 88) in
let _ = write_byte (if 4 <= 4 then 75 else 88) in
let _ = write_byte (if 5 > 4 then 10 else 88) in
let _ = write_byte (if 4 >= 5 then 88 else 79) in
let _ = write_byte (if 3 != 3 then 88 else 75) in
write_byte 10
