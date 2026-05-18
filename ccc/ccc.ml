(* Initial CCC bytecode smoke.

   This is not the C compiler yet. It pins the mlc -> ccc.byte build edge
   while the real C frontend and M1 emitter are ported.
*)

let _ = write_byte 35 in
let _ = write_byte 32 in
let _ = write_byte 99 in
let _ = write_byte 99 in
let _ = write_byte 99 in
let _ = write_byte 32 in
let _ = write_byte 115 in
let _ = write_byte 109 in
let _ = write_byte 111 in
let _ = write_byte 107 in
let _ = write_byte 101 in
let _ = write_byte 32 in
let _ = write_byte 77 in
let _ = write_byte 49 in
write_byte 10
