type expr = EBad | EPair of int

let rec emit expr =
  match expr with
    EPair ((lhs, _), rhs) -> lhs + rhs
  | _ -> 88
in
let _ = write_byte (emit (EPair ((40, 88), 39))) in
let _ = write_byte (emit (EPair ((75, 88), 0))) in
write_byte 10
