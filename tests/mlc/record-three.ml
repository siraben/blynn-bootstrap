type triple = { a : int; b : int; c : int }

let t = { a = 40; b = 30; c = 5 } in
let _ = write_byte (t.a + t.b + t.c + 4) in
write_byte 10
