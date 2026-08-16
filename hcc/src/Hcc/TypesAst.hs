module TypesAst
  ( Program(..)
  , TopDecl(..)
  , Linkage(..)
  , Param(..)
  , Field(..)
  , CType(..)
  , LocalStorage(..)
  , ForInit(..)
  , Stmt(..)
  , Expr(..)
  , paramTypes
  , renderStmtTag
  , renderExprTag
  ) where

import Base

data Program = Program [TopDecl]

data Linkage = ExternalLinkage | InternalLinkage

data TopDecl
  = Function Linkage CType String [Param] [Stmt]
  | Prototype Linkage CType String [Param]
  | Global Linkage CType String (Maybe Expr)
  | Globals Linkage [(CType, String, Maybe Expr)]
  | ExternGlobals [(CType, String)]
  | StructDecl Bool String [Field]
  | EnumConstants [(String, Int)]
  | TypeDecl [CType]

data Param = Param CType String

-- The optional expression is the declared width of a C bit-field.  Keeping it
-- in the AST matters even for translation units that never read the field:
-- bit-fields participate in aggregate size, alignment, and every following
-- member offset.
data Field = Field CType String (Maybe Expr)

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
  | CEnum String [(String, Int)]
  | CNamed String
  | CArray CType (Maybe Expr)
  | CFunc CType [CType]
  | CPtr CType

data LocalStorage
  = AutomaticStorage
  | StaticStorage
  | ExternalStorage

data ForInit
  = ForNoInit
  | ForExpr Expr
  | ForDecls LocalStorage [(CType, String, Maybe Expr)]

data Stmt
  = SDecl LocalStorage CType String (Maybe Expr)
  | SDecls LocalStorage [(CType, String, Maybe Expr)]
  | STypedef [CType]
  | SReturn (Maybe Expr)
  | SExpr Expr
  | SIf Expr [Stmt] [Stmt]
  | SWhile Expr [Stmt]
  | SDoWhile [Stmt] Expr
  | SFor ForInit (Maybe Expr) (Maybe Expr) [Stmt]
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
  | EAlignofType CType
  | EAlignofExpr Expr
  | EVaArg Expr CType
  | EStmtExpr [Stmt]
  | ECast CType Expr
  | EPostfix String Expr
  | EBinary String Expr Expr
  | ECond Expr Expr Expr
  | EAssign Expr Expr
  | ECompoundAssign String Expr Expr
  | EInitList [Expr]

paramTypes :: [Param] -> [CType]
paramTypes = map (\(Param ty _) -> ty)

renderStmtTag :: Stmt -> String
renderStmtTag stmt = case stmt of
  SDecl _ _ _ _ -> "SDecl"
  SDecls _ _ -> "SDecls"
  STypedef _ -> "STypedef"
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
  EAlignofType _ -> "EAlignofType"
  EAlignofExpr _ -> "EAlignofExpr"
  EVaArg _ _ -> "EVaArg"
  EStmtExpr _ -> "EStmtExpr"
  ECast _ _ -> "ECast"
  EPostfix _ _ -> "EPostfix"
  EBinary _ _ _ -> "EBinary"
  ECond _ _ _ -> "ECond"
  EAssign _ _ -> "EAssign"
  ECompoundAssign _ _ _ -> "ECompoundAssign"
  EInitList _ -> "EInitList"
