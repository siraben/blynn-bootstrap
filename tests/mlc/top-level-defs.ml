type point = { x : int; y : int }

let p = { x = 40; y = 39 }
let c = Cell.create p.x
let _ = Cell.set c (Cell.get c + p.y)
let rec emit value = write_byte value
emit (Cell.get c)
