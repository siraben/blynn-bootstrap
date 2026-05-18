type maybe_byte = Missing | Present of int

let _ = write_byte (match Present 79 with Present value -> value | _ -> 88) in
let _ = write_byte (match Missing with Present value -> 88 | _ -> 75) in
write_byte 10
