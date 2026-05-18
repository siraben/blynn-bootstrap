let c = Cell.create 40 in
let _ = Cell.set c 79 in
let _ = write_byte (Cell.get c) in
let _ = Cell.set c 75 in
let _ = write_byte (Cell.get c) in
write_byte 10
