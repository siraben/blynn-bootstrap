(* Initial self-host compiler placeholder.

   The first checked target is mlc-seed.c, which only emits bytecode for the
   write_byte fixture used by the VM smoke test. This file is where the
   MinCaml-shaped compiler grows next: lexer, parser, monomorphic type
   inference, K-normalization, simplification, closure conversion, and MZBC
   emission.
*)

let _ = write_byte 79 in
let _ = write_byte 75 in
write_byte 10
