(* Lambda-0 fixture: deep tail recursion (APPTERM) printing digit sums *)

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let rec loop i = fun acc ->
  if i = 0 then acc
  else loop (i - 1) (acc + i mod 7)

let rec fib n =
  if n < 2 then n else fib (n - 1) + fib (n - 2)

let () =
  print_int_rec (loop 100000 0);
  write_byte 1 10;
  print_int_rec (fib 20);
  write_byte 1 10;
  exit 0
