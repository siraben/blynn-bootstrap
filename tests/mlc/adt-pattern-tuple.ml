type expr = EBad | EByte of int | EAdd of int

let rec emit expr =
  match expr with
    EAdd (lhs, rhs) -> lhs + rhs
  | EByte value -> value
  | _ -> 88
in
let _ = write_byte (emit (EAdd (40, 39))) in
let _ = write_byte (emit (EByte 75)) in
write_byte 10
