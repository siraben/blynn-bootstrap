(* Lambda-1: insertion sort over an array, exercising all three deltas *)

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let print_int n =
  if n < 0 then (write_byte 1 45; print_int_rec (0 - n)) else print_int_rec n

let put c = write_byte 1 c

let rec puts_from s i =
  if i < string_length s then (put (string_get s i); puts_from s (i + 1))

let puts s = puts_from s 0

let a = array_make 8 0

let seed = 1234

let rec scramble i x =
  if i < array_length a then
    (array_set a i (x mod 97);
     scramble (i + 1) ((x * 31 + 17) mod 9973))

let rec shift_down j v =
  if j > 0 && array_get a (j - 1) > v then
    (array_set a j (array_get a (j - 1)); shift_down (j - 1) v)
  else array_set a j v

let rec isort i =
  if i < array_length a then
    (shift_down i (array_get a i); isort (i + 1))

let rec show i =
  if i < array_length a then
    (print_int (array_get a i); put 32; show (i + 1))

let () =
  scramble 0 seed;
  puts "before: "; show 0; put 10;
  isort 1;
  puts "after:  "; show 0; put 10;
  exit 0
