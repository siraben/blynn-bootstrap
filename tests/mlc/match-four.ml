type letter = A | B | C | D

let rec emit value =
  match value with
    A -> 88
  | B -> 88
  | C -> 88
  | D -> 79
in
let _ = write_byte (emit D) in
write_byte 10
