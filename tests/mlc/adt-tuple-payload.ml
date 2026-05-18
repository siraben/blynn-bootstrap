type expr = EBad | EByte of int | EAdd of int

let rec emit expr =
  match expr with
    EAdd pair ->
      let (lhs, rhs) = pair in
      lhs + rhs
  | EByte value -> value
  | _ -> 88
in
let expr = EAdd (40, 39) in
let _ = write_byte (emit expr) in
let _ = write_byte (emit (EByte 75)) in
write_byte 10
