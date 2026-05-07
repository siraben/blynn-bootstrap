module Hcc.Lower
  ( lowerProgram
  ) where

import Hcc.Ast
import Hcc.CompileM
import Hcc.Ir

lowerProgram :: Program -> Either CompileError ModuleIr
lowerProgram (Program decls) = runCompileM $ do
  fns <- lowerTopDecls decls
  dataItems <- getDataItems
  pure (ModuleIr dataItems fns)

lowerTopDecls :: [TopDecl] -> CompileM [FunctionIr]
lowerTopDecls decls = case decls of
  [] -> pure []
  Function _ name params body:rest -> do
    fn <- lowerFunction name params body
    fns <- lowerTopDecls rest
    pure (fn:fns)
  Prototype{}:rest -> lowerTopDecls rest
  Global{}:rest -> lowerTopDecls rest

lowerFunction :: String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunction name params body = withFunctionScope $ do
  bid <- freshBlock
  (paramNames, paramInstrs) <- lowerParams 0 params
  blocks <- lowerStatementsFrom bid paramInstrs body (TRet (Just (OImm 0)))
  pure (FunctionIr name paramNames blocks)

lowerParams :: Int -> [Param] -> CompileM ([String], [Instr])
lowerParams index params = case params of
  [] -> pure ([], [])
  Param _ name:rest -> do
    temp <- freshTemp
    bindVar name temp
    (names, instrs) <- lowerParams (index + 1) rest
    pure (name:names, IParam temp index:instrs)

lowerStatementsFrom :: BlockId -> [Instr] -> [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerStatementsFrom bid instrs stmts defaultTerm = case stmts of
  [] -> pure [BasicBlock bid instrs defaultTerm]
  SReturn value:rest -> case value of
    Nothing -> do
      tailBlocks <- lowerUnreachableLabels rest defaultTerm
      pure (BasicBlock bid instrs (TRet Nothing) : tailBlocks)
    Just expr -> do
      (retInstrs, op) <- lowerExpr expr
      tailBlocks <- lowerUnreachableLabels rest defaultTerm
      pure (BasicBlock bid (instrs ++ retInstrs) (TRet (Just op)) : tailBlocks)
  SBlock body:rest -> do
    restId <- freshBlock
    bodyBlocks <- withVarScope (lowerStatementsFrom bid instrs body (TJump restId))
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure (bodyBlocks ++ restBlocks)
  SDecl _ name initExpr:rest -> do
    (declInstrs, temp) <- case initExpr of
      Nothing -> do
        t <- freshTemp
        pure ([IConst t 0], t)
      Just expr -> do
        (exprInstrs, op) <- lowerExpr expr
        (copyInstrs, t) <- materialize op
        pure (exprInstrs ++ copyInstrs, t)
    bindVar name temp
    lowerStatementsFrom bid (instrs ++ declInstrs) rest defaultTerm
  SExpr expr:rest -> do
    exprInstrs <- lowerSideEffect expr
    lowerStatementsFrom bid (instrs ++ exprInstrs) rest defaultTerm
  SWhile cond body:rest -> do
    condId <- freshBlock
    bodyId <- freshBlock
    restId <- freshBlock
    (condInstrs, condOp) <- lowerExpr cond
    bodyBlocks <- lowerStatementsFrom bodyId [] body (TJump condId)
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure ( BasicBlock bid instrs (TJump condId)
         : BasicBlock condId condInstrs (TBranch condOp bodyId restId)
         : bodyBlocks ++ restBlocks)
  SGoto name:rest -> do
    target <- labelBlock name
    tailBlocks <- lowerUnreachableLabels rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : tailBlocks)
  SLabel name:rest -> do
    target <- labelBlock name
    blocks <- lowerStatementsFrom target [] rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : blocks)
  SIf cond yes no:rest -> do
    (condInstrs, condOp) <- lowerExpr cond
    yesId <- freshBlock
    noId <- freshBlock
    restId <- freshBlock
    let noTarget = if null no then restId else noId
    yesBlocks <- lowerStatementsFrom yesId [] yes (TJump restId)
    noBlocks <- if null no
      then pure []
      else lowerStatementsFrom noId [] no (TJump restId)
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure (BasicBlock bid (instrs ++ condInstrs) (TBranch condOp yesId noTarget) : yesBlocks ++ noBlocks ++ restBlocks)
  stmt:_ -> throwC ("unsupported statement in lowering: " ++ show stmt)

lowerUnreachableLabels :: [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerUnreachableLabels stmts defaultTerm = case stmts of
  [] -> pure []
  SLabel name:rest -> do
    target <- labelBlock name
    lowerStatementsFrom target [] rest defaultTerm
  _:rest ->
    lowerUnreachableLabels rest defaultTerm

lowerSideEffect :: Expr -> CompileM [Instr]
lowerSideEffect expr = case expr of
  ECall (EVar name) _ | name `elem` ignoredSideEffectCalls ->
    pure []
  ECall (EVar name) args -> do
    lowered <- lowerExprs args
    let instrs = concatMap fst lowered
    let ops = map snd lowered
    pure (instrs ++ [ICall Nothing name ops])
  EAssign (EVar name) rhs -> do
    (instrs, op) <- lowerExpr rhs
    temp <- lookupVar name
    pure (instrs ++ [ICopy temp op])
  EPostfix "--" (EVar name) -> do
    temp <- lookupVar name
    one <- freshTemp
    pure [IConst one 1, IBin temp ISub (OTemp temp) (OTemp one)]
  EPostfix "++" (EVar name) -> do
    temp <- lookupVar name
    one <- freshTemp
    pure [IConst one 1, IBin temp IAdd (OTemp temp) (OTemp one)]
  _ -> do
    (instrs, _) <- lowerExpr expr
    pure instrs

ignoredSideEffectCalls :: [String]
ignoredSideEffectCalls = ["asm", "oputs", "eputs"]

lowerExpr :: Expr -> CompileM ([Instr], Operand)
lowerExpr expr = case expr of
  EInt text -> do
    temp <- freshTemp
    pure ([IConst temp (parseInt text)], OTemp temp)
  EChar text -> do
    temp <- freshTemp
    pure ([IConst temp (charValue text)], OTemp temp)
  EString text -> do
    label <- freshLabel
    addDataItem (DataItem label (stringBytes text))
    pure ([], OGlobal ("HCC_DATA_" ++ label))
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
  EUnary "++" (EVar name) -> do
    temp <- lookupVar name
    one <- freshTemp
    pure ([IConst one 1, IBin temp IAdd (OTemp temp) (OTemp one)], OTemp temp)
  EUnary "--" (EVar name) -> do
    temp <- lookupVar name
    one <- freshTemp
    pure ([IConst one 1, IBin temp ISub (OTemp temp) (OTemp one)], OTemp temp)
  ECast CUnsignedChar x -> do
    (a, op) <- lowerExpr x
    out <- freshTemp
    pure (a ++ [IBin out IAnd op (OImm 255)], OTemp out)
  ECast _ x -> lowerExpr x
  EBinary op a b | Just iop <- lowerBinOp op -> do
    (ai, ao) <- lowerExpr a
    (bi, bo) <- lowerExpr b
    out <- freshTemp
    pure (ai ++ bi ++ [IBin out iop ao bo], OTemp out)
  EIndex base ix -> do
    (baseInstrs, baseOp) <- lowerExpr base
    (ixInstrs, ixOp) <- lowerExpr ix
    addr <- freshTemp
    out <- freshTemp
    pure (baseInstrs ++ ixInstrs ++ [IBin addr IAdd baseOp ixOp, ILoad8 out (OTemp addr)], OTemp out)
  ECall (EVar name) args -> do
    lowered <- lowerExprs args
    out <- freshTemp
    let instrs = concatMap fst lowered
    let ops = map snd lowered
    pure (instrs ++ [ICall (Just out) name ops], OTemp out)
  EAssign (EVar name) rhs -> do
    (instrs, op) <- lowerExpr rhs
    temp <- lookupVar name
    pure (instrs ++ [ICopy temp op], OTemp temp)
  EPostfix "--" (EVar name) -> do
    temp <- lookupVar name
    old <- freshTemp
    one <- freshTemp
    pure ([IBin old IAdd (OTemp temp) (OImm 0), IConst one 1, IBin temp ISub (OTemp temp) (OTemp one)], OTemp old)
  EPostfix "++" (EVar name) -> do
    temp <- lookupVar name
    old <- freshTemp
    one <- freshTemp
    pure ([IBin old IAdd (OTemp temp) (OImm 0), IConst one 1, IBin temp IAdd (OTemp temp) (OTemp one)], OTemp old)
  _ -> throwC ("unsupported expression in lowering: " ++ show expr)

lowerExprs :: [Expr] -> CompileM [([Instr], Operand)]
lowerExprs args = case args of
  [] -> pure []
  x:xs -> do
    first <- lowerExpr x
    rest <- lowerExprs xs
    pure (first:rest)

materialize :: Operand -> CompileM ([Instr], Temp)
materialize op = case op of
  OTemp temp -> pure ([], temp)
  OImm value -> do
    temp <- freshTemp
    pure ([IConst temp value], temp)
  OGlobal _ -> do
    temp <- freshTemp
    pure ([ICopy temp op], temp)

lowerBinOp :: String -> Maybe BinOp
lowerBinOp op = case op of
  "+" -> Just IAdd
  "-" -> Just ISub
  "*" -> Just IMul
  "/" -> Just IDiv
  "%" -> Just IMod
  "<<" -> Just IShl
  ">>" -> Just IShr
  "==" -> Just IEq
  "!=" -> Just INe
  "<" -> Just ILt
  "<=" -> Just ILe
  ">" -> Just IGt
  ">=" -> Just IGe
  "&&" -> Just IAnd
  "||" -> Just IOr
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
  '\'':'\\':'a':'\'':[] -> 7
  '\'':'\\':'b':'\'':[] -> 8
  '\'':'\\':'0':'\'':[] -> 0
  '\'':c:'\'':[] -> fromEnum c
  _ -> 0

stringBytes :: String -> [Int]
stringBytes text = go (stripQuotes text) where
  go chars = case chars of
    [] -> [0]
    '\\':'n':rest -> 10 : go rest
    '\\':'t':rest -> 9 : go rest
    '\\':'a':rest -> 7 : go rest
    '\\':'b':rest -> 8 : go rest
    '\\':'0':rest -> 0 : go rest
    '\\':c:rest -> fromEnum c : go rest
    c:rest -> fromEnum c : go rest

stripQuotes :: String -> String
stripQuotes text = case text of
  '"':rest -> reverse (dropQuote (reverse rest))
  _ -> text
  where
    dropQuote xs = case xs of
      '"':ys -> ys
      _ -> xs
