let bytes = Bytes.create 3 in
let zero = 0 in
let one = zero + 1 in
let two = one + 1 in
bytes.[zero] <- 79;
bytes.[one] <- 75;
bytes.[two] <- 10;
write_byte bytes.[zero];
write_byte bytes.[one];
write_byte bytes.[two]
