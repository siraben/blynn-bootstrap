(* Initial self-host compiler placeholder.

   This is not the compiler yet. It deliberately uses the seed language surface
   that the real MinCaml-shaped compiler will need: ADT declarations,
   constructor allocation, pattern matching, tuple destructuring, local names,
   and literal output.
*)

type output = Done | Emit of int

let pair = (79, 10) in
let (letter, newline) = pair in
let first = Emit letter in
let _ = write_byte (match first with Emit value -> value | _ -> 88) in
let _ = write_string "K" in
write_byte newline
