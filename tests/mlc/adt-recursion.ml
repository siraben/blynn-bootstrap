type bytes = Empty | Link of int

let rec emit node =
  match node with
    Empty -> 10
  | Link payload ->
      let (byte, rest) = payload in
      let _ = write_byte byte in
      emit rest
in
write_byte (emit (Link (79, Link (75, Empty))))
