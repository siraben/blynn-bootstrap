(* Lambda-0 fixture: bytes as the one data structure *)

let rec fill b = fun i ->
  if i < bytes_length b then
    (bytes_set b i (65 + i mod 26); fill b (i + 1))

let rec dump b = fun i ->
  if i < bytes_length b then
    (write_byte 1 (bytes_get b i); dump b (i + 1))

let rec rev b = fun i ->
  let n = bytes_length b in
  if i < n / 2 then
    (let t = bytes_get b i in
     bytes_set b i (bytes_get b (n - 1 - i));
     bytes_set b (n - 1 - i) t;
     rev b (i + 1))

let () =
  let b = bytes_create 30 in
  fill b 0;
  dump b 0;
  write_byte 1 10;
  rev b 0;
  dump b 0;
  write_byte 1 10;
  exit 0
