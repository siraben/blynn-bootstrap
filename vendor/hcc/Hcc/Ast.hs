module Ast where

data Program = Program [TopDecl]
  deriving (Eq, Show)

data TopDecl
  = Function CType String [Param] [Stmt]
  | Prototype CType String [Param]
  | Global CType String (Maybe Expr)
  | Globals [(CType, String, Maybe Expr)]
  | ExternGlobals [(CType, String)]
  | StructDecl Bool String [Field]
  | EnumConstants [(String, Int)]
  | TypeDecl
  deriving (Eq, Show)

data Param = Param CType String
  deriving (Eq, Show)

data Field = Field CType String
  deriving (Eq, Show)

data CType
  = CVoid
  | CInt
  | CChar
  | CUnsigned
  | CUnsignedChar
  | CLong
  | CFloat
  | CDouble
  | CLongDouble
  | CStruct String
  | CUnion String
  | CStructNamed String [Field]
  | CUnionNamed String [Field]
  | CStructDef [Field]
  | CUnionDef [Field]
  | CEnum String
  | CNamed String
  | CArray CType (Maybe Expr)
  | CPtr CType
  deriving (Eq, Show)

data Stmt
  = SDecl CType String (Maybe Expr)
  | SDecls [(CType, String, Maybe Expr)]
  | SReturn (Maybe Expr)
  | SExpr Expr
  | SIf Expr [Stmt] [Stmt]
  | SWhile Expr [Stmt]
  | SDoWhile [Stmt] Expr
  | SFor (Maybe Expr) (Maybe Expr) (Maybe Expr) [Stmt]
  | SSwitch Expr [Stmt]
  | SCase Expr
  | SDefault
  | SBreak
  | SContinue
  | SGoto String
  | SLabel String
  | SBlock [Stmt]
  deriving (Eq, Show)

data Expr
  = EInt String
  | EChar String
  | EString String
  | EVar String
  | ECall Expr [Expr]
  | EIndex Expr Expr
  | EMember Expr String
  | EPtrMember Expr String
  | EUnary String Expr
  | ESizeofType CType
  | ESizeofExpr Expr
  | ECast CType Expr
  | EPostfix String Expr
  | EBinary String Expr Expr
  | ECond Expr Expr Expr
  | EAssign Expr Expr
  | EInitList [Expr]
  deriving (Eq, Show)
