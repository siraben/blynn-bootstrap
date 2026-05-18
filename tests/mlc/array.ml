let buffer = Array.create 2 88 in
buffer.(0) <- 79;
buffer.(1) <- 75;
write_byte buffer.(0);
write_byte buffer.(1);
write_byte 10
