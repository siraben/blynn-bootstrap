module Ast where

import Base

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

renderProgram :: Program -> String
renderProgram (Program decls) = "Program " ++ astRenderList renderTopDecl decls

renderTopDecl :: TopDecl -> String
renderTopDecl decl = case decl of
  Function ty name params body -> "Function " ++ renderCType ty ++ " " ++ show name ++ " " ++ astRenderList renderParam params ++ " " ++ astRenderList renderStmt body
  Prototype ty name params -> "Prototype " ++ renderCType ty ++ " " ++ show name ++ " " ++ astRenderList renderParam params
  Global ty name value -> "Global " ++ renderCType ty ++ " " ++ show name ++ " " ++ astRenderMaybe renderExpr value
  Globals values -> "Globals " ++ astRenderList renderGlobal values
  ExternGlobals values -> "ExternGlobals " ++ astRenderList renderExtern values
  StructDecl complete name fields -> "StructDecl " ++ show complete ++ " " ++ show name ++ " " ++ astRenderList renderField fields
  EnumConstants values -> "EnumConstants " ++ show values
  TypeDecl -> "TypeDecl"

renderParam :: Param -> String
renderParam (Param ty name) = "Param " ++ renderCType ty ++ " " ++ show name

renderField :: Field -> String
renderField (Field ty name) = "Field " ++ renderCType ty ++ " " ++ show name

renderGlobal :: (CType, String, Maybe Expr) -> String
renderGlobal (ty, name, value) =
  "(" ++ renderCType ty ++ "," ++ show name ++ "," ++ astRenderMaybe renderExpr value ++ ")"

renderExtern :: (CType, String) -> String
renderExtern (ty, name) = "(" ++ renderCType ty ++ "," ++ show name ++ ")"

renderCType :: CType -> String
renderCType ty = case ty of
  CVoid -> "CVoid"
  CInt -> "CInt"
  CChar -> "CChar"
  CUnsigned -> "CUnsigned"
  CUnsignedChar -> "CUnsignedChar"
  CLong -> "CLong"
  CFloat -> "CFloat"
  CDouble -> "CDouble"
  CLongDouble -> "CLongDouble"
  CStruct name -> "CStruct " ++ show name
  CUnion name -> "CUnion " ++ show name
  CStructNamed name fields -> "CStructNamed " ++ show name ++ " " ++ astRenderList renderField fields
  CUnionNamed name fields -> "CUnionNamed " ++ show name ++ " " ++ astRenderList renderField fields
  CStructDef fields -> "CStructDef " ++ astRenderList renderField fields
  CUnionDef fields -> "CUnionDef " ++ astRenderList renderField fields
  CEnum name -> "CEnum " ++ show name
  CNamed name -> "CNamed " ++ show name
  CArray elemTy size -> "CArray " ++ renderCType elemTy ++ " " ++ astRenderMaybe renderExpr size
  CPtr elemTy -> "CPtr " ++ renderCType elemTy

renderStmt :: Stmt -> String
renderStmt stmt = case stmt of
  SDecl ty name value -> "SDecl " ++ renderCType ty ++ " " ++ show name ++ " " ++ astRenderMaybe renderExpr value
  SDecls values -> "SDecls " ++ astRenderList renderGlobal values
  SReturn value -> "SReturn " ++ astRenderMaybe renderExpr value
  SExpr expr -> "SExpr " ++ renderExpr expr
  SIf cond yes no -> "SIf " ++ renderExpr cond ++ " " ++ astRenderList renderStmt yes ++ " " ++ astRenderList renderStmt no
  SWhile cond body -> "SWhile " ++ renderExpr cond ++ " " ++ astRenderList renderStmt body
  SDoWhile body cond -> "SDoWhile " ++ astRenderList renderStmt body ++ " " ++ renderExpr cond
  SFor initExpr cond step body -> "SFor " ++ astRenderMaybe renderExpr initExpr ++ " " ++ astRenderMaybe renderExpr cond ++ " " ++ astRenderMaybe renderExpr step ++ " " ++ astRenderList renderStmt body
  SSwitch expr body -> "SSwitch " ++ renderExpr expr ++ " " ++ astRenderList renderStmt body
  SCase expr -> "SCase " ++ renderExpr expr
  SDefault -> "SDefault"
  SBreak -> "SBreak"
  SContinue -> "SContinue"
  SGoto name -> "SGoto " ++ show name
  SLabel name -> "SLabel " ++ show name
  SBlock body -> "SBlock " ++ astRenderList renderStmt body

renderExpr :: Expr -> String
renderExpr expr = case expr of
  EInt value -> "EInt " ++ show value
  EChar value -> "EChar " ++ show value
  EString value -> "EString " ++ show value
  EVar name -> "EVar " ++ show name
  ECall fun args -> "ECall " ++ renderExpr fun ++ " " ++ astRenderList renderExpr args
  EIndex array index -> "EIndex " ++ renderExpr array ++ " " ++ renderExpr index
  EMember base name -> "EMember " ++ renderExpr base ++ " " ++ show name
  EPtrMember base name -> "EPtrMember " ++ renderExpr base ++ " " ++ show name
  EUnary op value -> "EUnary " ++ show op ++ " " ++ renderExpr value
  ESizeofType ty -> "ESizeofType " ++ renderCType ty
  ESizeofExpr value -> "ESizeofExpr " ++ renderExpr value
  ECast ty value -> "ECast " ++ renderCType ty ++ " " ++ renderExpr value
  EPostfix op value -> "EPostfix " ++ show op ++ " " ++ renderExpr value
  EBinary op left right -> "EBinary " ++ show op ++ " " ++ renderExpr left ++ " " ++ renderExpr right
  ECond cond yes no -> "ECond " ++ renderExpr cond ++ " " ++ renderExpr yes ++ " " ++ renderExpr no
  EAssign dst src -> "EAssign " ++ renderExpr dst ++ " " ++ renderExpr src
  EInitList values -> "EInitList " ++ astRenderList renderExpr values

astRenderMaybe :: (a -> String) -> Maybe a -> String
astRenderMaybe render value = case value of
  Nothing -> "Nothing"
  Just x -> "Just " ++ render x

astRenderList :: (a -> String) -> [a] -> String
astRenderList render values = "[" ++ astRenderListItems render values ++ "]"

astRenderListItems :: (a -> String) -> [a] -> String
astRenderListItems render values = case values of
  [] -> ""
  x:xs -> render x ++ astRenderListTail render xs

astRenderListTail :: (a -> String) -> [a] -> String
astRenderListTail render values = case values of
  [] -> ""
  x:xs -> "," ++ render x ++ astRenderListTail render xs
