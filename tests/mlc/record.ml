type point = { x : int; y : int }

let p = { x = 40; y = 39 } in
let _ = write_byte (p.x + p.y) in
write_byte 10
