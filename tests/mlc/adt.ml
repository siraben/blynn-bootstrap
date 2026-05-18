type byte_or_empty = Empty | Byte of int

let _ = write_byte (match Byte 79 with Empty -> 88 | Byte x -> x) in
let _ = write_byte (match Empty with Empty -> 75 | Byte x -> 88) in
write_byte 10
