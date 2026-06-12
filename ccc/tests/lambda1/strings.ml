(* Lambda-1: string literals are first-class values *)

let put c = write_byte 1 c

let rec puts_from s i =
  if i < string_length s then (put (string_get s i); puts_from s (i + 1))

let puts s = puts_from s 0

let nl () = put 10

let greeting = "hello, lambda-1"

let shout s =
  let rec up i =
    if i < string_length s then
      (let c = string_get s i in
       put (if c >= 97 && c <= 122 then c - 32 else c);
       up (i + 1)) in
  up 0

let () =
  puts greeting; nl ();
  puts "string literals are values"; nl ();
  shout greeting; nl ();
  put (48 + string_length "abcde"); nl ();
  exit 0
