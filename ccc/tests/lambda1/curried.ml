(* Lambda-1: multi-parameter functions with curried semantics *)

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let print_int n =
  if n < 0 then (write_byte 1 45; print_int_rec (0 - n)) else print_int_rec n

let nl () = write_byte 1 10

let add3 x y z = x + y + z

let twice f x = f (f x)

let rec pow b e = if e = 0 then 1 else b * pow b (e - 1)

let rec gcd a b = if b = 0 then a else gcd b (a mod b)

let () =
  print_int (add3 1 20 300); nl ();
  (* partial application of a multi-parameter function *)
  let add21 = add3 1 20 in
  print_int (add21 4000); nl ();
  print_int (twice (add3 1 1) 40); nl ();
  print_int (twice (fun a -> a * a) 3); nl ();
  (* multi-parameter fun expression *)
  let mul = fun a b -> a * b in
  print_int (mul 6 7); nl ();
  print_int (pow 2 16); nl ();
  print_int (gcd 1071 462); nl ();
  (* local multi-parameter let and let rec *)
  let dist a b = if a > b then a - b else b - a in
  let rec ack m n =
    if m = 0 then n + 1
    else if n = 0 then ack (m - 1) 1
    else ack (m - 1) (ack m (n - 1)) in
  print_int (dist 3 45); nl ();
  print_int (ack 2 3); nl ();
  exit 0
