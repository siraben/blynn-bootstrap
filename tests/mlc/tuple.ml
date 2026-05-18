let pair = (70 + 9, 10) in
let (letter, newline) = pair in
let _ = write_byte letter in
let _ = write_byte (letter - 4) in
write_byte newline
