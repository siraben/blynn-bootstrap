(* ML1 fixture: ADT tree evaluation through nested constructors *)
type expr = Lit of int | Add of expr * expr | Mul of expr * expr | Neg of expr

let rec eval e =
  match e with
  | Lit n -> n
  | Add (a, b) -> eval a + eval b
  | Mul (a, b) -> eval a * eval b
  | Neg a -> 0 - eval a

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let print_int n =
  if n < 0 then (write_byte 1 45; print_int_rec (0 - n)) else print_int_rec n

let () =
  print_int (eval (Add (Mul (Lit 6, Lit 7), Neg (Lit 2))));
  write_byte 1 10
