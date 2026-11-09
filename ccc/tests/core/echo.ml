(* copy stdin to stdout byte by byte; loop must be tail-call safe for
   large inputs *)
let rec copy () =
  let b = read_byte 0 in
  if b >= 0 then (write_byte 1 b; copy ())

let () = copy ()
