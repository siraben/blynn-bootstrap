type maybe_byte = Missing | Present of int

let answer = 79 in
let newline = 10 in
let _ = write_byte answer in
let result = Present newline in
write_byte (match result with Present payload -> payload | Missing -> 88)
