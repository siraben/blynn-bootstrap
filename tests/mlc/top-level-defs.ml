type point = { x : int; y : int }

let p = { x = 40; y = 39 }
let c = Cell.create p.x
let current = Cell.get c
let _ = Cell.set c (current + p.y)
let rec emit value = write_byte value
emit (Cell.get c)
