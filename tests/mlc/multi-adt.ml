type color = Red | Green
type maybe_byte = Missing | Present of int

let _ = write_byte (match Present 79 with Present value -> value | Missing -> 88) in
let _ = write_byte (match Missing with Present value -> 88 | Missing -> 75) in
write_byte 10
