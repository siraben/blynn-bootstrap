let bytes = Bytes.create 3 in
bytes.[0] <- 79;
bytes.[1] <- 75;
bytes.[2] <- 10;
write_byte bytes.[0];
write_byte bytes.[1];
write_byte bytes.[2]
