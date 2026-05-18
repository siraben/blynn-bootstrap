(* Initial self-host compiler placeholder.

   This is not the compiler yet. It deliberately uses the seed language surface
   that the real MinCaml-shaped compiler will need: ADT declarations,
   constructor allocation, pattern matching, tuple destructuring, local names,
   and literal output.
*)

type output = Done | Emit of int

let rec select n = if n == 0 then 79 else select (n - 1) in
let pair = (79, 10) in
let (letter, newline) = pair in
let text = "K" in
let buffer = Bytes.create 1 in
buffer.[0] <- newline;
let first = Emit (select 2) in
let _ = write_byte (match first with Emit value -> value | _ -> 88) in
let _ = write_byte text.[0] in
write_byte buffer.[0]
