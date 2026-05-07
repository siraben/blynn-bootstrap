module Hcc.Lower
  ( lowerProgram
  ) where

import Hcc.Ast
import Hcc.CompileM
import Hcc.Ir

lowerProgram :: Program -> Either CompileError ModuleIr
lowerProgram (Program decls) = runCompileM (ModuleIr <$> lowerTopDecls decls)

lowerTopDecls :: [TopDecl] -> CompileM [FunctionIr]
lowerTopDecls decls = case decls of
  [] -> pure []
  Function _ name params body:rest -> do
    fn <- lowerFunction name params body
    fns <- lowerTopDecls rest
    pure (fn:fns)
  Global{}:rest -> lowerTopDecls rest

lowerFunction :: String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunction name params body = withFunctionScope $ do
  bid <- freshBlock
  (paramNames, paramInstrs) <- lowerParams 0 params
  (bodyInstrs, term) <- lowerStatements body
  pure (FunctionIr name paramNames [BasicBlock bid (paramInstrs ++ bodyInstrs) term])

lowerParams :: Int -> [Param] -> CompileM ([String], [Instr])
lowerParams index params = case params of
  [] -> pure ([], [])
  Param _ name:rest -> do
    temp <- freshTemp
    bindVar name temp
    (names, instrs) <- lowerParams (index + 1) rest
    pure (name:names, IParam temp index:instrs)

lowerStatements :: [Stmt] -> CompileM ([Instr], Terminator)
lowerStatements stmts = case stmts of
  [] -> pure ([], TRet (Just (OImm 0)))
  SReturn value:_ -> case value of
    Nothing -> pure ([], TRet Nothing)
    Just expr -> do
      (instrs, op) <- lowerExpr expr
      pure (instrs, TRet (Just op))
  SBlock body:rest -> do
    (a, term) <- lowerStatements body
    case term of
      TRet{} -> pure (a, term)
      _ -> do
        (b, term') <- lowerStatements rest
        pure (a ++ b, term')
  SDecl _ name initExpr:rest -> do
    (a, temp) <- case initExpr of
      Nothing -> do
        t <- freshTemp
        pure ([IConst t 0], t)
      Just expr -> do
        (instrs, op) <- lowerExpr expr
        t <- materialize op
        pure (instrs, t)
    bindVar name temp
    (b, term) <- lowerStatements rest
    pure (a ++ b, term)
  SExpr expr:rest -> do
    a <- lowerSideEffect expr
    (b, term) <- lowerStatements rest
    pure (a ++ b, term)
  stmt:_ -> throwC ("unsupported statement in lowering: " ++ show stmt)

lowerSideEffect :: Expr -> CompileM [Instr]
lowerSideEffect expr = case expr of
  ECall (EVar "asm") _ ->
    pure []
  ECall (EVar name) args -> do
    lowered <- lowerExprs args
    let instrs = concatMap fst lowered
    let ops = map snd lowered
    pure (instrs ++ [ICall Nothing name ops])
  EAssign (EVar name) rhs -> do
    (instrs, op) <- lowerExpr rhs
    temp <- materialize op
    bindVar name temp
    pure instrs
  _ -> do
    (instrs, _) <- lowerExpr expr
    pure instrs

lowerExpr :: Expr -> CompileM ([Instr], Operand)
lowerExpr expr = case expr of
  EInt text -> do
    temp <- freshTemp
    pure ([IConst temp (parseInt text)], OTemp temp)
  EChar text -> do
    temp <- freshTemp
    pure ([IConst temp (charValue text)], OTemp temp)
  EVar name -> OTemp <$> lookupVar name >>= \op -> pure ([], op)
  EUnary "+" x -> lowerExpr x
  EUnary "-" x -> do
    (a, op) <- lowerExpr x
    zero <- freshTemp
    out <- freshTemp
    pure (a ++ [IConst zero 0, IBin out ISub (OTemp zero) op], OTemp out)
  EUnary "!" x -> do
    (a, op) <- lowerExpr x
    zero <- freshTemp
    out <- freshTemp
    pure (a ++ [IConst zero 0, IBin out IEq op (OTemp zero)], OTemp out)
  EBinary op a b | Just iop <- lowerBinOp op -> do
    (ai, ao) <- lowerExpr a
    (bi, bo) <- lowerExpr b
    out <- freshTemp
    pure (ai ++ bi ++ [IBin out iop ao bo], OTemp out)
  ECall (EVar name) args -> do
    lowered <- lowerExprs args
    out <- freshTemp
    let instrs = concatMap fst lowered
    let ops = map snd lowered
    pure (instrs ++ [ICall (Just out) name ops], OTemp out)
  _ -> throwC ("unsupported expression in lowering: " ++ show expr)

lowerExprs :: [Expr] -> CompileM [([Instr], Operand)]
lowerExprs args = case args of
  [] -> pure []
  x:xs -> do
    first <- lowerExpr x
    rest <- lowerExprs xs
    pure (first:rest)

materialize :: Operand -> CompileM Temp
materialize op = case op of
  OTemp temp -> pure temp
  OImm value -> do
    temp <- freshTemp
    pure temp <* pure value
  OGlobal name -> throwC ("cannot materialize global yet: " ++ name)

lowerBinOp :: String -> Maybe BinOp
lowerBinOp op = case op of
  "+" -> Just IAdd
  "-" -> Just ISub
  "*" -> Just IMul
  "==" -> Just IEq
  "!=" -> Just INe
  "<" -> Just ILt
  "<=" -> Just ILe
  ">" -> Just IGt
  ">=" -> Just IGe
  _ -> Nothing

parseInt :: String -> Int
parseInt text =
  let clean = stripIntSuffix text
  in case clean of
    '0':'x':xs -> readHex xs
    '0':'X':xs -> readHex xs
    _ -> read clean

stripIntSuffix :: String -> String
stripIntSuffix text = reverse (dropWhile isSuffix (reverse text)) where
  isSuffix c = c `elem` "uUlL"

readHex :: String -> Int
readHex = go 0 where
  go n xs = case xs of
    [] -> n
    c:rest -> go (n * 16 + hexDigit c) rest

hexDigit :: Char -> Int
hexDigit c
  | c >= '0' && c <= '9' = fromEnum c - fromEnum '0'
  | c >= 'a' && c <= 'f' = 10 + fromEnum c - fromEnum 'a'
  | c >= 'A' && c <= 'F' = 10 + fromEnum c - fromEnum 'A'
  | otherwise = 0

charValue :: String -> Int
charValue text = case text of
  '\'':'\\':'n':'\'':[] -> 10
  '\'':'\\':'t':'\'':[] -> 9
  '\'':'\\':'0':'\'':[] -> 0
  '\'':c:'\'':[] -> fromEnum c
  _ -> 0
