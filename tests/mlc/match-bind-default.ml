type maybe_byte = Missing | Present of int

let rec emit value =
  match value with
    Present x -> x
  | other ->
      match other with
        Missing -> 75
      | _ -> 88
in
let _ = write_byte (emit (Present 79)) in
let _ = write_byte (emit Missing) in
write_byte 10
