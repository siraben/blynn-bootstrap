module TypesAst
  ( Program(..)
  , TopDecl(..)
  , Param(..)
  , Field(..)
  , CType(..)
  , Stmt(..)
  , Expr(..)
  , renderStmtTag
  , renderExprTag
  ) where

import Base

data Program = Program [TopDecl]

data TopDecl
  = Function CType String [Param] [Stmt]
  | Prototype CType String [Param]
  | Global CType String (Maybe Expr)
  | Globals [(CType, String, Maybe Expr)]
  | ExternGlobals [(CType, String)]
  | StructDecl Bool String [Field]
  | EnumConstants [(String, Int)]
  | TypeDecl [CType]

data Param = Param CType String

data Field = Field CType String

data CType
  = CVoid
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
  | CStruct String
  | CUnion String
  | CStructNamed String [Field]
  | CUnionNamed String [Field]
  | CStructDef [Field]
  | CUnionDef [Field]
  | CEnum String
  | CNamed String
  | CArray CType (Maybe Expr)
  | CFunc CType [CType]
  | CPtr CType

data Stmt
  = SDecl CType String (Maybe Expr)
  | SDecls [(CType, String, Maybe Expr)]
  | STypedef
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

data Expr
  = EInt String
  | EFloat String
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

renderStmtTag :: Stmt -> String
renderStmtTag stmt = case stmt of
  SDecl _ _ _ -> "SDecl"
  SDecls _ -> "SDecls"
  STypedef -> "STypedef"
  SReturn _ -> "SReturn"
  SExpr _ -> "SExpr"
  SIf _ _ _ -> "SIf"
  SWhile _ _ -> "SWhile"
  SDoWhile _ _ -> "SDoWhile"
  SFor _ _ _ _ -> "SFor"
  SSwitch _ _ -> "SSwitch"
  SCase _ -> "SCase"
  SDefault -> "SDefault"
  SBreak -> "SBreak"
  SContinue -> "SContinue"
  SGoto _ -> "SGoto"
  SLabel _ -> "SLabel"
  SBlock _ -> "SBlock"

renderExprTag :: Expr -> String
renderExprTag expr = case expr of
  EInt _ -> "EInt"
  EFloat _ -> "EFloat"
  EChar _ -> "EChar"
  EString _ -> "EString"
  EVar _ -> "EVar"
  ECall _ _ -> "ECall"
  EIndex _ _ -> "EIndex"
  EMember _ _ -> "EMember"
  EPtrMember _ _ -> "EPtrMember"
  EUnary _ _ -> "EUnary"
  ESizeofType _ -> "ESizeofType"
  ESizeofExpr _ -> "ESizeofExpr"
  ECast _ _ -> "ECast"
  EPostfix _ _ -> "EPostfix"
  EBinary _ _ _ -> "EBinary"
  ECond _ _ _ -> "ECond"
  EAssign _ _ -> "EAssign"
  EInitList _ -> "EInitList"
