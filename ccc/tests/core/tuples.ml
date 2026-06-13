(* tuples with fst/snd, sequencing, let-in chains, operators *)
let swap p = (snd p, fst p)

let () =
  let p = (3, 4) in
  let q = swap p in
  let x = fst q * 10 + snd q in            (* 43 *)
  let y = (1 lsl 4) lor (255 land 8) in    (* 24 *)
  let z = (x + y) mod 100 in               (* 67 *)
  write_byte 1 (z - 19);                   (* '0' = 48 *)
  (if (5 > 3 && 2 <= 2) || false then write_byte 1 107 else write_byte 1 110);
  write_byte 1 10;
  exit 0
