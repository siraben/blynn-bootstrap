(* Lambda-0 fixture: arithmetic, comparisons, short-circuit, sequencing *)

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let print_int = fun n ->
  (if n < 0 then (write_byte 1 45; print_int_rec (0 - n))
   else print_int_rec n);
  write_byte 1 10

let () =
  print_int (2 + 3 * 4);
  print_int ((2 + 3) * 4);
  print_int (100 / 7);
  print_int (100 mod 7);
  print_int (0 - 42);
  print_int (if 3 < 4 then 1 else 0);
  print_int (if 3 >= 4 then 1 else 0);
  print_int (if 3 <> 4 && 5 = 5 then 7 else 8);
  print_int (if false && 1 / 0 = 0 then 1 else 2);
  print_int (if true || 1 / 0 = 0 then 3 else 4);
  exit 0
