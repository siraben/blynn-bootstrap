let rec pick pair =
  let (letter, next) = pair in
  let _ = write_byte letter in
  next
in
let _ = write_byte (pick (79, 79) - 4) in
write_byte 10
