type expr = EBad | ERight of int | ELeft of int

let rec emit expr =
  match expr with
    ERight (_, rhs) -> rhs
  | ELeft (lhs, _) -> lhs
  | _ -> 88
in
let _ = write_byte (emit (ERight (88, 79))) in
let _ = write_byte (emit (ELeft (75, 88))) in
write_byte 10
