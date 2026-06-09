(* ML1 fixture: recursive list type, tail-position match arms *)
type ilist = Nil | Cons of int * ilist

let rec sum l =
  match l with
  | Nil -> 0
  | Cons (h, t) -> h + sum t

let rec last l =
  match l with
  | Nil -> 0 - 1
  | Cons (h, t) -> (match t with | Nil -> h | _ -> last t)

let rec build i acc = if i = 0 then acc else build (i - 1) (Cons (i, acc))

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let () =
  print_int_rec (sum (build 100 Nil));
  write_byte 1 10;
  print_int_rec (last (build 100 Nil));
  write_byte 1 10
