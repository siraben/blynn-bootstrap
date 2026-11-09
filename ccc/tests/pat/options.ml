(* ML2 fixture: parameterized and mutually recursive type declarations *)
type 'a option = None | Some of 'a

type expr2 = Num of int | Neg2 of expr2 | Grp of ty2
and ty2 = TInt2 | TArr of ty2 * expr2 option

let rec eval2 e =
  match e with
  | Num n -> n
  | Neg2 a -> 0 - eval2 a
  | Grp t -> tysize t

and tysize t =
  match t with
  | TInt2 -> 4
  | TArr (elt, bound) ->
      (match bound with
       | None -> tysize elt
       | Some b -> tysize elt * eval2 b)

let opt_default d o = match o with | None -> d | Some v -> v

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let () =
  print_int_rec (eval2 (Grp (TArr (TArr (TInt2, Some (Num 3)), Some (Neg2 (Num (0 - 4)))))));
  write_byte 1 10;
  print_int_rec (opt_default 7 None);
  print_int_rec (opt_default 7 (Some 9));
  write_byte 1 10
