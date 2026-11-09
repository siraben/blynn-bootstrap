(* ML2 fixture: list sugar in expressions and patterns *)
let rec sum l =
  match l with
  | [] -> 0
  | h :: t -> h + sum t

let rec pairs l =
  match l with
  | a :: b :: t -> (a + b) :: pairs t
  | [x] -> [x]
  | [] -> []

let second l =
  match l with
  | _ :: x :: _ -> x
  | _ -> 0 - 1

let rec rev acc l =
  match l with
  | [] -> acc
  | h :: t -> rev (h :: acc) t

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let () =
  print_int_rec (sum [1; 2; 3; 4; 5]);
  write_byte 1 10;
  print_int_rec (sum (pairs [1; 2; 3; 4; 5]));
  write_byte 1 10;
  print_int_rec (second [7; 8; 9]);
  write_byte 1 10;
  print_int_rec (sum (rev [] (6 :: 7 :: [])));
  write_byte 1 10
