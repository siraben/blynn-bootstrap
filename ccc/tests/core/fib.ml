(* mutual recursion via let rec ... and ..., decimal printing, closures *)
let rec is_even n = if n = 0 then true else is_odd (n - 1)
and is_odd n = if n = 0 then false else is_even (n - 1)

let rec fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

let rec print_int_rec n =
  if n > 9 then print_int_rec (n / 10);
  write_byte 1 (48 + n mod 10)

let print_int n =
  if n < 0 then (write_byte 1 45; print_int_rec (0 - n)) else print_int_rec n

let newline () = write_byte 1 10

let () =
  print_int (fib 20); newline ();
  (if is_even 10 then print_int 1 else print_int 0); newline ();
  (if is_odd 7 then print_int 1 else print_int 0); newline ();
  let add = fun a b -> a + b in
  let inc = add 1 in
  print_int (inc 41); newline ()
