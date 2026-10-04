(* arrays, while-via-recursion, arithmetic: count primes below 1000 = 168 *)
let n = 1000

let rec mark sieve i step =
  if i < n then (array_set sieve i 1; mark sieve (i + step) step)

let rec outer sieve i =
  if i * i < n then
    ((if array_get sieve i = 0 then mark sieve (i * i) i);
     outer sieve (i + 1))

let rec count sieve i acc =
  if i >= n then acc
  else if array_get sieve i = 0 then count sieve (i + 1) (acc + 1)
  else count sieve (i + 1) acc

let rec print_int_rec v =
  if v > 9 then print_int_rec (v / 10);
  write_byte 1 (48 + v mod 10)

let () =
  let sieve = array_make n 0 in
  outer sieve 2;
  print_int_rec (count sieve 2 0);
  write_byte 1 10
