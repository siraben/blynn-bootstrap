(* Lambda-0 fixture: lists and pairs, the symbolic core's one data shape *)

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let print_int = fun n -> (print_int_rec n; write_byte 1 10)

let rec iota_rev i = fun acc ->
  if i = 0 then acc else iota_rev (i - 1) (cons i acc)

let rec sum l = if null l then 0 else hd l + sum (tl l)

let rec rev_onto l = fun acc ->
  if null l then acc else rev_onto (tl l) (cons (hd l) acc)

let rec map_double l =
  if null l then nil else cons (2 * hd l) (map_double (tl l))

(* association list of pairs; 0 when the key is absent *)
let rec assoc k = fun ps ->
  if null ps then 0
  else if fst (hd ps) = k then snd (hd ps)
  else assoc k (tl ps)

let () =
  let one_to_ten = iota_rev 10 nil in
  print_int (sum one_to_ten);
  print_int (sum (map_double one_to_ten));
  print_int (hd (rev_onto one_to_ten nil));
  print_int (if null nil then 1 else 0);
  print_int (if null one_to_ten then 1 else 0);
  let p = pair 6 7 in
  print_int (fst p * snd p);
  let tbl = cons (pair 1 11) (cons (pair 2 22) (cons (pair 3 33) nil)) in
  print_int (assoc 2 tbl);
  print_int (assoc 9 tbl);
  exit 0
