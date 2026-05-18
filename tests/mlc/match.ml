type option = None | Some of int

let _ = write_byte (match Some 79 with Some x -> x | None -> 88) in
let _ = write_byte (match None with Some x -> 88 | None -> 75) in
write_byte 10
