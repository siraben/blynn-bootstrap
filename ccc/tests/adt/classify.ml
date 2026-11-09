(* ML1 fixture: literal, char, bool, constant-constructor and default arms *)
type color = Red | Green | Blue

let classify n =
  match n with
  | 0 -> 100
  | 1 -> 101
  | 'A' -> 102
  | x -> x * 2

let color_code c =
  match c with
  | Red -> 'r'
  | Green -> 'g'
  | Blue -> 'b'

let flag b =
  match b with
  | true -> 'T'
  | false -> 'F'

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let () =
  print_int_rec (classify 0); write_byte 1 10;
  print_int_rec (classify 1); write_byte 1 10;
  print_int_rec (classify 65); write_byte 1 10;
  print_int_rec (classify 21); write_byte 1 10;
  write_byte 1 (color_code Red);
  write_byte 1 (color_code Green);
  write_byte 1 (color_code Blue);
  write_byte 1 (flag true);
  write_byte 1 (flag (1 > 2));
  write_byte 1 10
