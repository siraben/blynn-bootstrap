(* Lambda-1: arrays via array_make / array_get / array_set / array_length *)

let rec print_int_rec n =
  (if n > 9 then print_int_rec (n / 10));
  write_byte 1 (48 + n mod 10)

let print_int n =
  if n < 0 then (write_byte 1 45; print_int_rec (0 - n)) else print_int_rec n

let nl () = write_byte 1 10

let squares = array_make 10 0

let rec fill i =
  if i < array_length squares then
    (array_set squares i (i * i); fill (i + 1))

let rec sum a i acc =
  if i < array_length a then sum a (i + 1) (acc + array_get a i) else acc

(* sieve of Eratosthenes up to 30 *)
let limit = 30
let composite = array_make 31 0

let rec strike p k =
  if p * k <= limit then (array_set composite (p * k) 1; strike p (k + 1))

let rec sieve p =
  if p <= limit then
    ((if array_get composite p = 0 then (print_int p; write_byte 1 32; strike p 2));
     sieve (p + 1))

let () =
  fill 0;
  print_int (sum squares 0 0); nl ();
  print_int (array_length squares); nl ();
  sieve 2; nl ();
  exit 0
