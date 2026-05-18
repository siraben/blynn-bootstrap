type expr = EBad | ELeft of int | ERight of int

let rec emit expr =
  match expr with
    ELeft ((lhs, _), rhs) -> lhs + rhs
  | ERight (lhs, (_, rhs)) -> lhs + rhs
  | _ -> 88
in
let _ = write_byte (emit (ELeft ((40, 88), 39))) in
let _ = write_byte (emit (ERight (40, (0, 35)))) in
write_byte 10
