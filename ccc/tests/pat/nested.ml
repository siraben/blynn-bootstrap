(* ML2 fixture: nested patterns across constructors, tuples and lists *)
type shape = Pt | Circle of int | Rect of int * int

type stree = Leaf of shape | Node of stree * stree

let rec area t =
  match t with
  | Leaf Pt -> 0
  | Leaf (Circle r) -> 3 * r * r
  | Leaf (Rect (w, h)) -> w * h
  | Node (Leaf (Rect (w, 2)), r) -> w + area r
  | Node (l, r) -> area l + area r

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let classify p =
  match p with
  | (0, 0) -> 1
  | (0, _) -> 2
  | (_, 0) -> 3
  | (x, y) -> x + y

let () =
  print_int_rec (area (Node (Leaf (Circle 2), Node (Leaf (Rect (3, 4)), Leaf Pt))));
  write_byte 1 10;
  print_int_rec (area (Node (Leaf (Rect (5, 2)), Leaf (Circle 1))));
  write_byte 1 10;
  print_int_rec (classify (0, 0));
  print_int_rec (classify (0, 9));
  print_int_rec (classify (7, 0));
  print_int_rec (classify (20, 22));
  write_byte 1 10
