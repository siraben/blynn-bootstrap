(* Lambda-0 fixture: closures, currying, capture threading, local rec *)

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let print_int = fun n -> (print_int_rec n; write_byte 1 10)

let add = fun a -> fun b -> a + b

let twice = fun f -> fun x -> f (f x)

(* capture threading two levels deep *)
let outer = fun a ->
  fun b ->
    fun c ->
      a * 100 + b * 10 + c

let compose = fun f -> fun g -> fun x -> f (g x)

let () =
  print_int (add 2 3);
  let add10 = add 10 in
  print_int (add10 32);
  print_int (twice (add 7) 1);
  print_int (outer 1 2 3);
  print_int (compose (add 1) (add 2) 39);
  (* local let rec with self-capture and an outer capture *)
  let base = 5 in
  let rec sum n = if n = 0 then base else n + sum (n - 1) in
  print_int (sum 10);
  (* closure returned from a branch *)
  let pick = fun w -> if w = 1 then add 100 else add 200 in
  print_int (pick 1 1);
  print_int (pick 2 1);
  exit 0
