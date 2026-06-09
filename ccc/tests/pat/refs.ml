(* ML2 fixture: references and let-pattern destructuring *)
let counter = ref 0

let bump_by n = counter := !counter + n

let divmod a b = (a / b, a mod b)

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let () =
  bump_by 40;
  bump_by 2;
  print_int_rec !counter;
  write_byte 1 10;
  let (q, r) = divmod 47 5 in
  print_int_rec q;
  write_byte 1 32;
  print_int_rec r;
  write_byte 1 10;
  let acc = ref 0 in
  let rec go i =
    if i > 0 then (acc := !acc + i; go (i - 1)) in
  go 10;
  print_int_rec !acc;
  write_byte 1 10
