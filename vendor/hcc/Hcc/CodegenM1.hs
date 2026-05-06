module Hcc.CodegenM1
  ( CodegenError(..)
  , codegenM1
  ) where

import Hcc.Ast

data CodegenError = CodegenError String
  deriving (Eq, Show)

codegenM1 :: Program -> Either CodegenError String
codegenM1 (Program decls) = do
  mainBody <- findMain decls
  body <- codegenMain mainBody
  pure (unlines (header ++ body))

header :: [String]
header =
  [ "## hcc M1 output"
  , "## target: stage0-posix amd64 M1"
  , ""
  , ":FUNCTION_main"
  ]

findMain :: [TopDecl] -> Either CodegenError [Stmt]
findMain decls = case decls of
  [] -> Left (CodegenError "missing main")
  Function _ "main" _ body:_ -> Right body
  _:rest -> findMain rest

codegenMain :: [Stmt] -> Either CodegenError [String]
codegenMain stmts = case firstReturn stmts of
  Nothing -> Right ["\tLOAD_IMMEDIATE_rax %0", "\tRETURN"]
  Just expr -> do
    code <- codegenExpr expr
    pure (code ++ ["\tRETURN"])

firstReturn :: [Stmt] -> Maybe Expr
firstReturn stmts = case stmts of
  [] -> Nothing
  SReturn (Just expr):_ -> Just expr
  SBlock body:rest -> case firstReturn body of
    Just expr -> Just expr
    Nothing -> firstReturn rest
  SIf _ yes no:rest -> case firstReturn yes of
    Just expr -> Just expr
    Nothing -> case firstReturn no of
      Just expr -> Just expr
      Nothing -> firstReturn rest
  _:rest -> firstReturn rest

codegenExpr :: Expr -> Either CodegenError [String]
codegenExpr expr = case expr of
  EInt text -> pure ["\tLOAD_IMMEDIATE_rax %" ++ renderInt text]
  EChar text -> pure ["\tLOAD_IMMEDIATE_rax %" ++ show (charValue text)]
  EUnary "+" x -> codegenExpr x
  EUnary "-" x -> do
    code <- codegenExpr x
    pure (code ++ ["\tPUSH_RAX", "\tLOAD_IMMEDIATE_rax %0", "\tPOP_RBX", "\tSUBTRACT_rax_from_rbx_into_rbx", "\tMOVE_rbx_to_rax"])
  EBinary op a b | op `elem` ["+", "-", "*"] -> codegenBinary op a b
  _ -> Left (CodegenError ("unsupported expression for M1 backend: " ++ show expr))

codegenBinary :: String -> Expr -> Expr -> Either CodegenError [String]
codegenBinary op a b = do
  acode <- codegenExpr a
  bcode <- codegenExpr b
  opCode <- case op of
    "+" -> Right ["\tADD_rbx_to_rax"]
    "-" -> Right ["\tSUBTRACT_rax_from_rbx_into_rbx", "\tMOVE_rbx_to_rax"]
    "*" -> Right ["\tMULTIPLY_rax_by_rbx_into_rax"]
    _ -> Left (CodegenError ("unsupported binary op: " ++ op))
  pure (acode ++ ["\tPUSH_RAX"] ++ bcode ++ ["\tPOP_RBX"] ++ opCode)

renderInt :: String -> String
renderInt text =
  let clean = stripIntSuffix text
  in case clean of
    '0':'x':_ -> clean
    '0':'X':xs -> "0x" ++ xs
    _ -> clean

stripIntSuffix :: String -> String
stripIntSuffix text = reverse (dropWhile isSuffix (reverse text)) where
  isSuffix c = c `elem` "uUlL"

charValue :: String -> Int
charValue text = case text of
  '\'':'\\':'n':'\'':[] -> 10
  '\'':'\\':'t':'\'':[] -> 9
  '\'':'\\':'0':'\'':[] -> 0
  '\'':c:'\'':[] -> fromEnum c
  _ -> 0
