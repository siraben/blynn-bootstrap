type letter = A | B | C

let rec emit value =
  match value with
    A -> 79
  | B -> 75
  | C -> 10
in
let _ = write_byte (emit A) in
let _ = write_byte (emit B) in
write_byte (emit C)
