let n = 3 in
let a = Array.create n 79 in
let b = Bytes.create n in
b.[0] <- a.(0);
b.[1] <- 75;
b.[2] <- 10;
let _ = write_byte b.[0] in
let _ = write_byte b.[1] in
write_byte b.[2]
