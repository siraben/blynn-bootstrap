(* ccc part 20: C AST; port of Hcc.TypesAst and Hcc.Operators. One
   mutually recursive group: types and expressions reference each other
   (array bounds, casts). Strings are bytes. *)

type ctype =
  | CVoid
  | CInt
  | CShort
  | CChar
  | CUnsigned
  | CUnsignedShort
  | CUnsignedChar
  | CLong
  | CUnsignedLong
  | CLongLong
  | CUnsignedLongLong
  | CBool
  | CFloat
  | CDouble
  | CLongDouble
  | CStruct of bytes
  | CUnion of bytes
  | CStructNamed of bytes * field list
  | CUnionNamed of bytes * field list
  | CStructDef of field list
  | CUnionDef of field list
  | CEnum of bytes
  | CNamed of bytes
  | CArray of ctype * expr option
  | CFunc of ctype * ctype list
  | CPtr of ctype

and field = Field of ctype * bytes

and expr =
  | EInt of bytes
  | EFloat of bytes
  | EChar of bytes
  | EString of bytes
  | EVar of bytes
  | ECall of expr * expr list
  | EIndex of expr * expr
  | EMember of expr * bytes
  | EPtrMember of expr * bytes
  | EUnary of bytes * expr
  | ESizeofType of ctype
  | ESizeofExpr of expr
  | ECast of ctype * expr
  | EPostfix of bytes * expr
  | EBinary of bytes * expr * expr
  | ECond of expr * expr * expr
  | EAssign of expr * expr
  | ECompoundAssign of bytes * expr * expr
  | EInitList of expr list

type param = Param of ctype * bytes

type stmt =
  | SDecl of ctype * bytes * expr option
  | SDecls of (ctype * bytes * expr option) list
  | STypedef
  | SReturn of expr option
  | SExpr of expr
  | SIf of expr * stmt list * stmt list
  | SWhile of expr * stmt list
  | SDoWhile of stmt list * expr
  | SFor of expr option * expr option * expr option * stmt list
  | SSwitch of expr * stmt list
  | SCase of expr
  | SDefault
  | SBreak
  | SContinue
  | SGoto of bytes
  | SLabel of bytes
  | SBlock of stmt list

type topdecl =
  | DFunction of ctype * bytes * param list * stmt list
  | DPrototype of ctype * bytes * param list
  | DGlobal of ctype * bytes * expr option
  | DGlobals of (ctype * bytes * expr option) list
  | DExternGlobals of (ctype * bytes) list
  | DStructDecl of bool * bytes * field list
  | DEnumConstants of (bytes * int) list
  | DTypeDecl of ctype list

let rec param_types params =
  match params with
  | [] -> []
  | Param (ty, _) :: rest -> ty :: param_types rest

(* binary operator precedence: returns prec, or -1 when not a binop;
   right-associativity is a separate predicate (only assignments) *)
let binop_arith_prec op =
  if bytes_eq_str op "||" then 3
  else if bytes_eq_str op "&&" then 4
  else if bytes_eq_str op "|" then 5
  else if bytes_eq_str op "^" then 6
  else if bytes_eq_str op "&" then 7
  else if bytes_eq_str op "==" || bytes_eq_str op "!=" then 8
  else if bytes_eq_str op "<" || bytes_eq_str op "<=" ||
          bytes_eq_str op ">" || bytes_eq_str op ">=" then 9
  else if bytes_eq_str op "<<" || bytes_eq_str op ">>" then 10
  else if bytes_eq_str op "+" || bytes_eq_str op "-" then 11
  else if bytes_eq_str op "*" || bytes_eq_str op "/" || bytes_eq_str op "%" then 12
  else 0 - 1

let binop_is_assign op =
  bytes_eq_str op "=" || bytes_eq_str op "+=" || bytes_eq_str op "-=" ||
  bytes_eq_str op "*=" || bytes_eq_str op "/=" || bytes_eq_str op "%=" ||
  bytes_eq_str op "<<=" || bytes_eq_str op ">>=" || bytes_eq_str op "&=" ||
  bytes_eq_str op "^=" || bytes_eq_str op "|="

(* full expression-level binop table (Parser.binop): prec or -1 *)
let binop_prec op =
  if bytes_eq_str op "," then 0
  else if binop_is_assign op then 1
  else binop_arith_prec op

let binop_right_assoc op = binop_is_assign op
