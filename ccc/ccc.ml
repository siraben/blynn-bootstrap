(* Initial CCC bytecode smoke.

   This is not the C compiler yet. It pins the mlc -> ccc.byte build edge
   while the real C frontend and M1 emitter are ported.
*)

let _ = write_byte 79 in
let _ = write_byte 75 in
write_byte 10
