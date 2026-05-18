let bytes = Bytes.create 2 in
let text = "OK\n" in
let _ = write_byte (String.length text + 76) in
let _ = write_byte (Bytes.length bytes + 73) in
write_byte text.[2]
