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

(* diagnostic tags, mirroring TypesAst.renderStmtTag/renderExprTag *)
let render_stmt_tag s =
  match s with
  | SDecl (_, _, _) -> str_to_bytes "SDecl"
  | SDecls _ -> str_to_bytes "SDecls"
  | STypedef -> str_to_bytes "STypedef"
  | SReturn _ -> str_to_bytes "SReturn"
  | SExpr _ -> str_to_bytes "SExpr"
  | SIf (_, _, _) -> str_to_bytes "SIf"
  | SWhile (_, _) -> str_to_bytes "SWhile"
  | SDoWhile (_, _) -> str_to_bytes "SDoWhile"
  | SFor (_, _, _, _) -> str_to_bytes "SFor"
  | SSwitch (_, _) -> str_to_bytes "SSwitch"
  | SCase _ -> str_to_bytes "SCase"
  | SDefault -> str_to_bytes "SDefault"
  | SBreak -> str_to_bytes "SBreak"
  | SContinue -> str_to_bytes "SContinue"
  | SGoto _ -> str_to_bytes "SGoto"
  | SLabel _ -> str_to_bytes "SLabel"
  | SBlock _ -> str_to_bytes "SBlock"

let render_expr_tag e =
  match e with
  | EInt _ -> str_to_bytes "EInt"
  | EFloat _ -> str_to_bytes "EFloat"
  | EChar _ -> str_to_bytes "EChar"
  | EString _ -> str_to_bytes "EString"
  | EVar _ -> str_to_bytes "EVar"
  | ECall (_, _) -> str_to_bytes "ECall"
  | EIndex (_, _) -> str_to_bytes "EIndex"
  | EMember (_, _) -> str_to_bytes "EMember"
  | EPtrMember (_, _) -> str_to_bytes "EPtrMember"
  | EUnary (_, _) -> str_to_bytes "EUnary"
  | ESizeofType _ -> str_to_bytes "ESizeofType"
  | ESizeofExpr _ -> str_to_bytes "ESizeofExpr"
  | ECast (_, _) -> str_to_bytes "ECast"
  | EPostfix (_, _) -> str_to_bytes "EPostfix"
  | EBinary (_, _, _) -> str_to_bytes "EBinary"
  | ECond (_, _, _) -> str_to_bytes "ECond"
  | EAssign (_, _) -> str_to_bytes "EAssign"
  | ECompoundAssign (_, _, _) -> str_to_bytes "ECompoundAssign"
  | EInitList _ -> str_to_bytes "EInitList"

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
