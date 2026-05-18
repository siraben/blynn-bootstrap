let rec first text = text.[0] in
let rec second text = text.[1] in
let _ = write_byte (first "OK") in
let _ = write_byte (second "OK") in
write_byte 10
