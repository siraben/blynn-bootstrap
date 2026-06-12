(* Lambda-1: strings stored in arrays, walked with multi-parameter helpers *)

let put c = write_byte 1 c

let rec puts_from s i =
  if i < string_length s then (put (string_get s i); puts_from s (i + 1))

let puts s = puts_from s 0

let words = array_make 4 ""

let () = array_set words 0 "data"
let () = array_set words 1 "lambda"
let () = array_set words 2 "rung"
let () = array_set words 3 "two"

let rec show i =
  if i < array_length words then
    (puts (array_get words i); put 10; show (i + 1))

let rec total i acc =
  if i < array_length words then
    total (i + 1) (acc + string_length (array_get words i))
  else acc

let () =
  show 0;
  put (48 + total 0 0 / 10);
  put (48 + total 0 0 mod 10);
  put 10;
  exit 0
