type summary = FuncConst of int | FuncArg | FuncNotArg | FuncAddArgs | FuncCmpArgs | FuncArgEqAny of int

let value = FuncArgEqAny 79 in
write_byte (match value with
  FuncConst n -> n
| FuncArg -> 65
| FuncNotArg -> 66
| FuncAddArgs -> 67
| FuncCmpArgs -> 68
| FuncArgEqAny n -> n)
