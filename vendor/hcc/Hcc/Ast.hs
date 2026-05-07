module Hcc.Ast where

data Program = Program [TopDecl]
  deriving (Eq, Show)

data TopDecl
  = Function CType String [Param] [Stmt]
  | Global CType String (Maybe Expr)
  deriving (Eq, Show)

data Param = Param CType String
  deriving (Eq, Show)

data CType
  = CVoid
  | CInt
  | CChar
  | CUnsigned
  | CLong
  | CNamed String
  | CPtr CType
  deriving (Eq, Show)

data Stmt
  = SDecl CType String (Maybe Expr)
  | SReturn (Maybe Expr)
  | SExpr Expr
  | SIf Expr [Stmt] [Stmt]
  | SWhile Expr [Stmt]
  | SDoWhile [Stmt] Expr
  | SFor (Maybe Expr) (Maybe Expr) (Maybe Expr) [Stmt]
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
  | EUnary String Expr
  | EBinary String Expr Expr
  | EAssign Expr Expr
  deriving (Eq, Show)
