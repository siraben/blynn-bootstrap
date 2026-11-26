module Lower
  ( lowerFunction
  , globalData
  , completeArrayType
  ) where

import Base
import BootstrapTypes
import TypesAst
import CompileM
import TypesIr
import LowerBuiltins
import LowerRegisters
import Literal
import LowerLiterals
import TypesLower
import LowerTypeInfo

lowerFunction :: String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunction name params body =
  withErrorContext ("function " ++ name) (withFunctionScope (withCurrentFunction name (lowerFunctionBody name params body)))

lowerFunctionBody :: String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunctionBody name params body = do
  bid <- freshBlock
  paramInstrs <- lowerParams 0 params
  defaultTerm <- defaultReturnTerm
  blocks <- lowerStatementsFrom bid paramInstrs body defaultTerm
  pure (FunctionIr name blocks)

lowerParams :: Int -> [Param] -> CompileM [Instr]
lowerParams index params = case params of
  [] -> pure []
  Param ty name:rest -> do
    temp <- freshTemp
    bindVar name temp ty
    instrs <- lowerParams (index + 1) rest
    -- Capture all incoming registers before emitting any conversions.
    case ty of
      CBool -> do
        (convert, value) <- coerceBool (OTemp temp)
        pure (IParam temp index : instrs ++ convert ++ [ICopy temp value])
      _ -> pure (IParam temp index:instrs)

defaultReturnTerm :: CompileM Terminator
defaultReturnTerm = do
  mty <- currentReturnType
  case mty of
    Just CVoid -> pure (TRet Nothing)
    _ -> pure (TRet (Just (OImm 0)))

coerceReturnOperand :: Operand -> CompileM ([Instr], Operand)
coerceReturnOperand op = do
  mty <- currentReturnType
  case mty of
    Just CVoid -> pure ([], op)
    Just ty -> coerceScalar ty op
    Nothing -> pure ([], op)

lowerStatementsFrom :: BlockId -> [Instr] -> [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerStatementsFrom bid instrs stmts defaultTerm =
  lowerStatementChunks bid [instrs] stmts defaultTerm

-- Chunks are newest first; flatten only when the current block is emitted.
lowerStatementChunks :: BlockId -> [[Instr]] -> [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerStatementChunks bid chunks stmts defaultTerm = case stmts of
  [] -> pure [BasicBlock bid instrs defaultTerm]
  SReturn value:rest -> case value of
    Nothing -> do
      tailBlocks <- lowerUnreachableLabels rest defaultTerm
      pure (BasicBlock bid instrs (TRet Nothing) : tailBlocks)
    Just expr -> do
      (retInstrs, op) <- lowerExpr expr
      (coerceInstrs, retOp) <- coerceReturnOperand op
      tailBlocks <- lowerUnreachableLabels rest defaultTerm
      pure (BasicBlock bid (instrs ++ retInstrs ++ coerceInstrs) (TRet (Just retOp)) : tailBlocks)
  SBlock body:rest -> do
    if null rest
      then withVarScope (lowerStatementChunks bid chunks body defaultTerm)
      else do
        restId <- freshBlock
        bodyBlocks <- withVarScope (lowerStatementChunks bid chunks body (TJump restId))
        restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
        pure (bodyBlocks ++ restBlocks)
  SDecls decls:rest -> do
    declInstrs <- lowerDecls decls
    lowerStatementChunks bid (declInstrs:chunks) rest defaultTerm
  SStaticDecls decls:rest -> do
    mapM_ lowerStaticDecl decls
    lowerStatementChunks bid chunks rest defaultTerm
  SExternDecls decls:rest -> do
    mapM_ (\(ty, name) -> registerTypeIntroductions ty >> bindScopedGlobal name name ty) decls
    lowerStatementChunks bid chunks rest defaultTerm
  SPrototype ty name:rest -> do
    registerTypeIntroductions ty
    bindScopedFunction name ty
    lowerStatementChunks bid chunks rest defaultTerm
  STypeDecl types:rest -> do
    mapM_ registerTypeIntroductions types
    lowerStatementChunks bid chunks rest defaultTerm
  SExpr expr:rest -> do
    exprInstrs <- lowerSideEffect expr
    lowerStatementChunks bid (exprInstrs:chunks) rest defaultTerm
  SWhile cond body:rest -> do
    condId <- freshBlock
    bodyId <- freshBlock
    restId <- freshBlock
    condBlocks <- lowerConditionBlock condId [] cond bodyId restId
    bodyBlocks <- withLoopTargets restId condId (lowerStatementsFrom bodyId [] body (TJump condId))
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure ( BasicBlock bid instrs (TJump condId)
         : condBlocks ++ bodyBlocks ++ restBlocks)
  SDoWhile body cond:rest -> do
    bodyId <- freshBlock
    condId <- freshBlock
    restId <- freshBlock
    bodyBlocks <- withLoopTargets restId condId (lowerStatementsFrom bodyId [] body (TJump condId))
    condBlocks <- lowerConditionBlock condId [] cond bodyId restId
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure ( BasicBlock bid instrs (TJump bodyId)
         : bodyBlocks ++
           condBlocks ++ restBlocks)
  SFor initClause condExpr stepExpr body:rest -> do
    restId <- freshBlock
    loopBlocks <- case initClause of
      ForDecls _ -> withVarScope (lowerForLoop bid instrs initClause condExpr stepExpr body restId)
      _ -> lowerForLoop bid instrs initClause condExpr stepExpr body restId
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure (loopBlocks ++ restBlocks)
  SSwitch value body:rest -> do
    (valueInstrs, valueOp) <- lowerExpr value
    switchTy <- promotedExprType value
    (convertInstrs, convertedValue) <- coerceScalar switchTy valueOp
    dispatchId <- freshBlock
    restId <- freshBlock
    switchBlocks <- withVarScope (lowerSwitch dispatchId restId switchTy convertedValue body)
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure (BasicBlock bid (instrs ++ valueInstrs ++ convertInstrs) (TJump dispatchId) : switchBlocks ++ restBlocks)
  SCase value:rest -> do
    switchTy <- currentSwitchType
    (valueInstrs, valueOp) <- lowerExpr value
    (convertInstrs, convertedValue) <- coerceScalar switchTy valueOp
    target <- freshBlock
    addSwitchLabel (Just (valueInstrs ++ convertInstrs, convertedValue)) target
    blocks <- lowerStatementsFrom target [] rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : blocks)
  SDefault:rest -> do
    _ <- currentSwitchType
    target <- freshBlock
    addSwitchLabel Nothing target
    blocks <- lowerStatementsFrom target [] rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : blocks)
  SGoto name:rest -> do
    target <- labelBlock name
    tailBlocks <- lowerUnreachableLabels rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : tailBlocks)
  SLabel name:rest -> do
    target <- labelBlock name
    blocks <- lowerStatementsFrom target [] rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : blocks)
  SIf cond yes no:rest -> do
    yesId <- freshBlock
    noId <- freshBlock
    restId <- case (rest, defaultTerm) of
      ([], TJump target) -> pure target
      _ -> freshBlock
    let noTarget = if null no then restId else noId
    -- Bindings/type introductions in the condition precede the lexical tail.
    condBlocks <- lowerConditionBlock bid instrs cond yesId noTarget
    yesBlocks <- withVarScope (lowerStatementsFrom yesId [] yes (TJump restId))
    noBlocks <- withVarScope (lowerIfNoBlocks no noId restId)
    restBlocks <- case (rest, defaultTerm) of
      ([], TJump _) -> pure []
      _ -> lowerStatementsFrom restId [] rest defaultTerm
    pure (condBlocks ++ yesBlocks ++ noBlocks ++ restBlocks)
  SBreak:rest -> do
    target <- requireBreakTarget
    tailBlocks <- lowerUnreachableLabels rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : tailBlocks)
  SContinue:rest -> do
    target <- requireContinueTarget
    tailBlocks <- lowerUnreachableLabels rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : tailBlocks)
  where
    instrs = concat (reverse chunks)

lowerForLoop :: BlockId -> [Instr] -> ForInit -> Maybe Expr -> Maybe Expr -> [Stmt] -> BlockId -> CompileM [BasicBlock]
lowerForLoop bid instrs initClause condExpr stepExpr body restId = do
    initInstrs <- lowerForInit initClause
    condId <- freshBlock
    bodyId <- freshBlock
    stepId <- freshBlock
    condBlocks <- lowerLoopConditionBlocks condExpr condId bodyId restId
    stepInstrs <- maybe (pure []) lowerSideEffect stepExpr
    bodyBlocks <- withLoopTargets restId stepId (lowerStatementsFrom bodyId [] body (TJump stepId))
    pure ( BasicBlock bid (instrs ++ initInstrs) (TJump condId)
         : condBlocks ++ bodyBlocks ++
           [BasicBlock stepId stepInstrs (TJump condId)])

lowerForInit :: ForInit -> CompileM [Instr]
lowerForInit initClause = case initClause of
  ForNoInit -> pure []
  ForExpr expr -> lowerSideEffect expr
  ForDecls decls -> lowerDecls decls

lowerIfNoBlocks :: [Stmt] -> BlockId -> BlockId -> CompileM [BasicBlock]
lowerIfNoBlocks no noId restId = case no of
  [] -> pure []
  _ -> lowerStatementsFrom noId [] no (TJump restId)

-- A goto may enter a nested statement. Lower every nonempty suffix without
-- an incoming edge: even label-free declarations can bind names in a later
-- switch clause. Initializers remain disconnected, not executed.
lowerUnreachableLabels :: [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerUnreachableLabels stmts defaultTerm = case stmts of
  [] -> pure []
  _ -> do
    bid <- freshBlock
    lowerStatementsFrom bid [] stmts defaultTerm

lowerLoopConditionBlocks :: Maybe Expr -> BlockId -> BlockId -> BlockId -> CompileM [BasicBlock]
lowerLoopConditionBlocks condExpr condId bodyId restId = case condExpr of
  Nothing -> pure [BasicBlock condId [] (TJump bodyId)]
  Just cond -> lowerConditionBlock condId [] cond bodyId restId

lowerConditionBlock :: BlockId -> [Instr] -> Expr -> BlockId -> BlockId -> CompileM [BasicBlock]
lowerConditionBlock bid instrs cond trueId falseId = case cond of
  EBinary "&&" left right -> do
    rightId <- freshBlock
    leftBlocks <- lowerConditionBlock bid instrs left rightId falseId
    rightBlocks <- lowerConditionBlock rightId [] right trueId falseId
    pure (leftBlocks ++ rightBlocks)
  EBinary "||" left right -> do
    rightId <- freshBlock
    leftBlocks <- lowerConditionBlock bid instrs left trueId rightId
    rightBlocks <- lowerConditionBlock rightId [] right trueId falseId
    pure (leftBlocks ++ rightBlocks)
  EUnary "!" value ->
    lowerConditionBlock bid instrs value falseId trueId
  EBinary op left right ->
    if isComparisonOpString op
      then do
        (condInstrs, iop, leftOp, rightOp) <- lowerBranchComparison op left right
        pure [BasicBlock bid (instrs ++ condInstrs) (TBranchCmp iop leftOp rightOp trueId falseId)]
      else lowerValueConditionBlock bid instrs cond trueId falseId
  _ ->
    lowerValueConditionBlock bid instrs cond trueId falseId

lowerValueConditionBlock :: BlockId -> [Instr] -> Expr -> BlockId -> BlockId -> CompileM [BasicBlock]
lowerValueConditionBlock bid instrs cond trueId falseId = do
  (condInstrs, condOp) <- lowerExpr cond
  pure [BasicBlock bid (instrs ++ condInstrs) (TBranch condOp trueId falseId)]

isComparisonOpString :: String -> Bool
isComparisonOpString op =
  op `elem` ["==", "!=", "<", "<=", ">", ">="]

lowerBranchComparison :: String -> Expr -> Expr -> CompileM ([Instr], BinOp, Operand, Operand)
lowerBranchComparison op a b = do
  (ai, ao) <- lowerExpr a
  (bi, bo) <- lowerExpr b
  commonTy <- comparisonOperandType a b
  (ac, ao') <- coerceScalar commonTy ao
  (bc, bo') <- coerceScalar commonTy bo
  pure (ai ++ bi ++ ac ++ bc, comparisonOp op commonTy, ao', bo')

requireBreakTarget :: CompileM BlockId
requireBreakTarget = do
  target <- currentBreakTarget
  case target of
    Just bid -> pure bid
    Nothing -> throwC "break outside loop or switch"

requireContinueTarget :: CompileM BlockId
requireContinueTarget = do
  target <- currentContinueTarget
  case target of
    Just bid -> pure bid
    Nothing -> throwC "continue outside loop"

lowerSwitch :: BlockId -> BlockId -> CType -> Operand -> [Stmt] -> CompileM [BasicBlock]
lowerSwitch dispatchId restId switchTy valueOp body = do
  -- The body entry has no edge from dispatch. Only a case, default, or
  -- explicit goto may enter it; lexical fallthrough is lowered normally.
  bodyId <- freshBlock
  (bodyBlocks, labels) <- withSwitch switchTy restId (lowerStatementsFrom bodyId [] body (TJump restId))
  let split = splitSwitchLabels labels
  defaultTarget <- case snd split of
    [] -> pure restId
    [target] -> pure target
    _ -> throwC "multiple default labels in switch"
  dispatchBlocks <- lowerSwitchDispatch dispatchId valueOp defaultTarget (fst split)
  pure (dispatchBlocks ++ bodyBlocks)

splitSwitchLabels :: [(Maybe ([Instr], Operand), BlockId)] -> ([([Instr], Operand, BlockId)], [BlockId])
splitSwitchLabels = splitSwitchLabelsInto [] []

splitSwitchLabelsInto :: [([Instr], Operand, BlockId)] -> [BlockId] -> [(Maybe ([Instr], Operand), BlockId)] -> ([([Instr], Operand, BlockId)], [BlockId])
splitSwitchLabelsInto checks fallback remaining = case remaining of
  [] -> (reverse checks, reverse fallback)
  entry:rest -> case fst entry of
    Nothing -> splitSwitchLabelsInto checks (snd entry:fallback) rest
    Just lowered -> splitSwitchLabelsInto ((fst lowered, snd lowered, snd entry):checks) fallback rest

lowerSwitchDispatch :: BlockId -> Operand -> BlockId -> [([Instr], Operand, BlockId)] -> CompileM [BasicBlock]
lowerSwitchDispatch bid valueOp defaultTarget switchCasePairs = case switchCasePairs of
  [] -> pure [BasicBlock bid [] (TJump defaultTarget)]
  (caseInstrs, caseOp, target):tailCases -> do
    nextId <- case tailCases of
      [] -> pure defaultTarget
      _ -> freshBlock
    let block = BasicBlock bid caseInstrs (TBranchCmp IEq valueOp caseOp target nextId)
    case tailCases of
      [] -> pure [block]
      _ -> do
        restBlocks <- lowerSwitchDispatch nextId valueOp defaultTarget tailCases
        pure (block:restBlocks)

lowerSideEffect :: Expr -> CompileM [Instr]
lowerSideEffect expr = case expr of
  ECall (EVar name) args -> do
    binding <- resolveName name
    case binding of
      LocalBinding _ _ -> lowerCallWithBinding Nothing name binding args
      GlobalBinding _ _ -> lowerCallWithBinding Nothing name binding args
      _ | name == "asm" ->
        if noOpInlineAsmArgs args then pure [] else throwC "unsupported inline assembly"
      _ | isIgnoredSideEffectCall name -> mapM_ registerDiscardedExprIntroductions args >> pure []
      _ -> lowerCall Nothing (EVar name) args
  ECall callee args -> lowerCall Nothing callee args
  EAssign lhs rhs ->
    lowerResultInstrs (lowerAssignment lhs rhs)
  ECompoundAssign op lhs rhs ->
    lowerResultInstrs (lowerCompoundAssignment op lhs rhs)
  EPostfix "--" target ->
    lowerIncDecSideEffect ISub target
  EPostfix "++" target ->
    lowerIncDecSideEffect IAdd target
  _ -> do
    (instrs, _) <- lowerExpr expr
    pure instrs

noOpInlineAsmArgs :: [Expr] -> Bool
noOpInlineAsmArgs args = case args of
  [EString bytes] -> bytes == [110, 111, 112, 0]
  _ -> False

lowerResultInstrs :: CompileM ([Instr], Operand) -> CompileM [Instr]
lowerResultInstrs action = do
  (instrs, _) <- action
  pure instrs

lowerIncDecSideEffect :: BinOp -> Expr -> CompileM [Instr]
lowerIncDecSideEffect op target =
  lowerResultInstrs (lowerIncDec True op target)

lowerDecls :: [(CType, String, Maybe Expr)] -> CompileM [Instr]
lowerDecls decls = do
  lowered <- mapM (\(ty, name, initExpr) -> lowerDecl ty name initExpr) decls
  pure (concat lowered)

lowerDecl :: CType -> String -> Maybe Expr -> CompileM [Instr]
lowerDecl declTy name initExpr = do
  let ty = completeArrayType declTy initExpr
  registerTypeIntroductions ty
  aggregateStorage <- isAggregateTypeM ty
  temp <- freshTemp
  bindVar name temp ty
  if aggregateStorage
    then lowerAggregateDecl ty temp initExpr
    else lowerScalarDecl ty temp initExpr

lowerStaticDecl :: (CType, String, Maybe Expr) -> CompileM ()
lowerStaticDecl (declTy, name, initExpr) = do
  let ty = completeArrayType declTy initExpr
  registerTypeIntroductions ty
  label <- freshDataLabel
  bindScopedGlobal name label ty
  values <- globalData ty initExpr
  addDataItem (DataItem label values)

completeArrayType :: CType -> Maybe Expr -> CType
completeArrayType ty initExpr = case ty of
  CArray inner Nothing -> case initExpr of
    Just (EInitList exprs) -> CArray inner (Just (EInt (show (length exprs))))
    Just (EString bytes) -> CArray inner (Just (EInt (show (length bytes))))
    _ -> ty
  _ -> ty

lowerAggregateDecl :: CType -> Temp -> Maybe Expr -> CompileM [Instr]
lowerAggregateDecl ty temp initExpr = do
  size <- typeSize ty
  initInstrs <- lowerAggregateDeclInit ty temp initExpr
  pure (IAlloca temp size : initInstrs)

lowerAggregateDeclInit :: CType -> Temp -> Maybe Expr -> CompileM [Instr]
lowerAggregateDeclInit ty temp initExpr = do
  template <- localAggregateTemplateData ty initExpr
  case template of
    Just label ->
      copyObject (OTemp temp) (OGlobal label) ty
    Nothing ->
      lowerAggregateDeclRuntime ty temp initExpr

lowerAggregateDeclRuntime :: CType -> Temp -> Maybe Expr -> CompileM [Instr]
lowerAggregateDeclRuntime ty temp initExpr = case initExpr of
  Just (EInitList _) -> do
    zeroInstrs <- zeroObject (OTemp temp) ty
    writeInstrs <- lowerAggregateInitWrites (OTemp temp) ty initExpr
    pure (zeroInstrs ++ writeInstrs)
  Just expr -> do
    (exprInstrs, op) <- lowerExpr expr
    copyInstrs <- copyObject (OTemp temp) op ty
    pure (exprInstrs ++ copyInstrs)
  Nothing -> pure []

lowerScalarDecl :: CType -> Temp -> Maybe Expr -> CompileM [Instr]
lowerScalarDecl ty temp initExpr = case initExpr of
  Nothing -> pure [IConst temp 0]
  Just expr -> do
    (exprInstrs, op) <- lowerExpr expr
    (coerceInstrs, coerceOp) <- coerceScalar ty op
    pure (exprInstrs ++ coerceInstrs ++ [ICopy temp coerceOp])

localAggregateTemplateData :: CType -> Maybe Expr -> CompileM (Maybe String)
localAggregateTemplateData ty initExpr = case ty of
  CArray _ _ -> localArrayTemplateData ty initExpr
  _ -> localNonArrayTemplateData ty initExpr

localArrayTemplateData :: CType -> Maybe Expr -> CompileM (Maybe String)
localArrayTemplateData ty initExpr = case initExpr of
  Just expr ->
    if staticInitializerExpr expr
      then case expr of
        EInitList _ -> localDataItem ty initExpr
        EString _ -> localDataItem ty initExpr
        _ -> pure Nothing
      else pure Nothing
  Nothing -> pure Nothing

localNonArrayTemplateData :: CType -> Maybe Expr -> CompileM (Maybe String)
localNonArrayTemplateData ty initExpr = case initExpr of
  Just expr -> case expr of
    EInitList _ -> do
      aggregateStorage <- isAggregateTypeM ty
      if aggregateStorage && staticInitializerExpr expr then localDataItem ty initExpr else pure Nothing
    _ -> pure Nothing
  Nothing -> pure Nothing

-- A conservative template optimization: names and addresses use the runtime
-- initializer path, without needing binding or relocation classification here.
staticInitializerExpr :: Expr -> Bool
staticInitializerExpr expr = case expr of
  EInitList exprs -> and (map staticInitializerExpr exprs)
  EString _ -> True
  EInt _ -> True
  EFloat _ -> True
  EChar _ -> True
  ESizeofType _ -> True
  ESizeofExpr _ -> True
  ECast _ value -> staticInitializerExpr value
  EUnary "-" value -> staticInitializerExpr value
  EUnary "+" value -> staticInitializerExpr value
  EUnary "~" value -> staticInitializerExpr value
  EUnary "!" value -> staticInitializerExpr value
  _ -> False

localDataItem :: CType -> Maybe Expr -> CompileM (Maybe String)
localDataItem ty initExpr = do
  dataLabel <- freshDataLabel
  values <- globalData ty initExpr
  addDataItem (DataItem dataLabel values)
  pure (Just dataLabel)

lowerAggregateInitWrites :: Operand -> CType -> Maybe Expr -> CompileM [Instr]
lowerAggregateInitWrites dst ty initExpr = case initExpr of
  Just (EInitList exprs) -> lowerAggregateInitList dst ty exprs
  _ -> pure []

lowerAggregateInitList :: Operand -> CType -> [Expr] -> CompileM [Instr]
lowerAggregateInitList dst ty exprs = case ty of
  CArray inner count -> do
    bound <- arrayBoundSize count
    if length exprs > bound
      then throwC "excess elements in array initializer"
      else lowerArrayInitWrites dst inner 0 exprs
  _ -> do
    aggregate <- aggregateFields ty
    case aggregate of
      Just aggregateInfo -> case aggregateInfo of
        (False, fields) -> lowerStructInitWrites dst 0 fields exprs
        (True, fields) -> lowerUnionInitWrites dst fields exprs
      _ -> pure []

lowerUnionInitWrites :: Operand -> [Field] -> [Expr] -> CompileM [Instr]
lowerUnionInitWrites dst fields exprs = case exprs of
  [] -> pure []
  [expr] -> case fields of
    Field fieldTy _:_ -> lowerAggregateElementWrite dst 0 fieldTy expr
    [] -> throwC "excess elements in union initializer"
  _ -> throwC "excess elements in union initializer"

lowerArrayInitWrites :: Operand -> CType -> Int -> [Expr] -> CompileM [Instr]
lowerArrayInitWrites dst inner index exprs = case exprs of
  [] -> pure []
  expr:rest -> do
    elemSize <- typeSize inner
    current <- lowerAggregateElementWrite dst (index * elemSize) inner expr
    tailInstrs <- lowerArrayInitWrites dst inner (index + 1) rest
    pure (current ++ tailInstrs)

lowerStructInitWrites :: Operand -> Int -> [Field] -> [Expr] -> CompileM [Instr]
lowerStructInitWrites dst offset fields exprs = case fields of
  [] -> case exprs of
    [] -> pure []
    _ -> throwC "excess elements in struct initializer"
  field:fieldRest -> case exprs of
    [] -> pure []
    expr:exprRest -> case field of
      Field fieldTy _ -> do
        align <- typeAlign fieldTy
        fieldSize <- typeSize fieldTy
        let aligned = alignUp offset align
        current <- lowerAggregateElementWrite dst aligned fieldTy expr
        tailInstrs <- lowerStructInitWrites dst (aligned + fieldSize) fieldRest exprRest
        pure (current ++ tailInstrs)

lowerAggregateElementWrite :: Operand -> Int -> CType -> Expr -> CompileM [Instr]
lowerAggregateElementWrite dst offset fieldTy expr = do
  (addrInstrs, addr) <- offsetAddress dst offset
  aggregateStorage <- isAggregateTypeM fieldTy
  valueInstrs <- lowerAggregateElementValueWrite aggregateStorage addr fieldTy expr
  pure (addrInstrs ++ valueInstrs)

lowerAggregateElementValueWrite :: Bool -> Operand -> CType -> Expr -> CompileM [Instr]
lowerAggregateElementValueWrite aggregateStorage addr fieldTy expr =
  if aggregateStorage
    then lowerAggregateElementAggregateWrite addr fieldTy expr
    else lowerAggregateElementScalarWrite addr fieldTy expr

lowerAggregateElementAggregateWrite :: Operand -> CType -> Expr -> CompileM [Instr]
lowerAggregateElementAggregateWrite addr fieldTy expr = case expr of
  EInitList exprs -> lowerAggregateInitList addr fieldTy exprs
  EString _ -> do
    label <- localDataItem fieldTy (Just expr)
    case label of
      Just name -> copyObject addr (OGlobal name) fieldTy
      Nothing -> pure []
  _ -> do
    (exprInstrs, op) <- lowerExpr expr
    copyInstrs <- copyObject addr op fieldTy
    pure (exprInstrs ++ copyInstrs)

lowerAggregateElementScalarWrite :: Operand -> CType -> Expr -> CompileM [Instr]
lowerAggregateElementScalarWrite addr fieldTy (EInitList [expr]) =
  lowerAggregateElementScalarWrite addr fieldTy expr
lowerAggregateElementScalarWrite addr fieldTy expr = do
  (exprInstrs, op) <- lowerExpr expr
  (coerceInstrs, coerceOp) <- coerceScalar fieldTy op
  store <- storeScalar fieldTy addr coerceOp
  pure (exprInstrs ++ coerceInstrs ++ store)

lowerExpr :: Expr -> CompileM ([Instr], Operand)
lowerExpr expr = case expr of
  EInt text -> case intConstOperand text of
    Left msg -> throwC msg
    Right op -> pure ([], op)
  EFloat text -> case floatLiteralBytes (floatLiteralSize text) text of
    Left msg -> throwC msg
    Right bytes -> pure ([], OImmBytes bytes)
  EChar text ->
    pure ([], OImm (charValue text))
  EString bytes -> do
    dataLabel <- freshDataLabel
    addDataItem (DataItem dataLabel (map DByte bytes))
    pure ([], OGlobal dataLabel)
  EVar name -> lowerVarExpr name
  EUnary "+" x -> do
    (a, op) <- lowerExpr x
    ty <- promotedExprType x
    (coerceInstrs, coerceOp) <- coerceScalar ty op
    pure (a ++ coerceInstrs, coerceOp)
  EUnary "-" x -> do
    (a, op) <- lowerExpr x
    zero <- freshTemp
    out <- freshTemp
    ty <- promotedExprType x
    (coerceInstrs, coerceOp) <- coerceScalar ty (OTemp out)
    pure (a ++ [IConst zero 0, IBin out ISub (OTemp zero) op] ++ coerceInstrs, coerceOp)
  EUnary "!" x -> do
    (a, op) <- lowerExpr x
    zero <- freshTemp
    out <- freshTemp
    pure (a ++ [IConst zero 0, IBin out IEq op (OTemp zero)], OTemp out)
  EUnary "~" x -> do
    (a, op) <- lowerExpr x
    zero <- freshTemp
    neg <- freshTemp
    out <- freshTemp
    ty <- promotedExprType x
    (coerceInstrs, coerceOp) <- coerceScalar ty (OTemp out)
    pure (a ++ [IConst zero 0, IBin neg ISub (OTemp zero) op, IBin out ISub (OTemp neg) (OImm 1)] ++ coerceInstrs, coerceOp)
  EUnary "*" (EUnary "&" value) ->
    lowerExpr value
  EUnary "&" target ->
    lowerLValueAddress target
  EUnary "*" _ ->
    readLValueExpr expr
  EUnary "++" target ->
    lowerIncDec True IAdd target
  EUnary "--" target ->
    lowerIncDec True ISub target
  ECast ty x -> do
    registerTypeIntroductions ty
    (a, op) <- lowerExpr x
    (coerceInstrs, coerceOp) <- coerceScalar ty op
    pure (a ++ coerceInstrs, coerceOp)
  ESizeofType ty -> do
    registerExprIntroductions expr
    size <- typeSize ty
    temp <- freshTemp
    pure ([IConst temp size], OTemp temp)
  ESizeofExpr value -> do
    registerExprIntroductions expr
    size <- sizeofExprSize value
    temp <- freshTemp
    pure ([IConst temp size], OTemp temp)
  ECond cond yes no -> do
    (ci, co) <- lowerExpr cond
    (yi, yo) <- lowerExpr yes
    (ni, noOp) <- lowerExpr no
    resultTy <- conditionalType yes no
    (yc, yesOp) <- coerceMaybeScalar resultTy yo
    (nc, noResult) <- coerceMaybeScalar resultTy noOp
    out <- freshTemp
    pure ([ICond out ci co (yi ++ yc) yesOp (ni ++ nc) noResult], OTemp out)
  EBinary "," a b -> do
    ai <- lowerSideEffect a
    (bi, bo) <- lowerExpr b
    pure (ai ++ bi, bo)
  EBinary "&&" a b ->
    lowerShortCircuit True a b
  EBinary "||" a b ->
    lowerShortCircuit False a b
  EBinary "+" a b ->
    lowerAddExpr a b
  EBinary "-" a b ->
    lowerSubExpr a b
  EBinary ">>" a b ->
    lowerShiftExpr ">>" a b
  EBinary op a b -> lowerBinaryExpr op a b
  EIndex _ _ ->
    readLValueExpr expr
  EPtrMember _ _ ->
    readLValueExpr expr
  EMember _ _ ->
    readLValueExpr expr
  ECall callee args -> do
    out <- freshTemp
    instrs <- lowerCall (Just out) callee args
    pure (instrs, OTemp out)
  EAssign lhs rhs ->
    lowerAssignment lhs rhs
  ECompoundAssign op lhs rhs ->
    lowerCompoundAssignment op lhs rhs
  EPostfix "--" target ->
    lowerIncDec False ISub target
  EPostfix "++" target ->
    lowerIncDec False IAdd target
  _ -> throwC ("unsupported expression in lowering: " ++ renderExprTag expr)

lowerVarExpr :: String -> CompileM ([Instr], Operand)
lowerVarExpr name = do
  binding <- resolveName name
  case binding of
    LocalBinding temp ty -> coerceScalar ty (OTemp temp)
    GlobalBinding label ty -> lowerTypedGlobalVarExpr label ty
    FunctionBinding _ -> pure ([], OFunction name)
    UnknownBinding ->
      if isFunctionNameMacro name
        then lowerFunctionNameMacro
        else do
          constant <- lookupConstant name
          case constant of
            Just value -> pure ([], OImm value)
            Nothing -> case builtinConstant name of
              Just value -> pure ([], OImm value)
              Nothing -> throwC ("unknown identifier: " ++ name)

lowerFunctionNameMacro :: CompileM ([Instr], Operand)
lowerFunctionNameMacro = do
  mname <- currentFunctionName
  case mname of
    Just name -> lowerExpr (EString (map fromEnum name ++ [0]))
    Nothing -> pure ([], OImm 0)

lowerTypedGlobalVarExpr :: String -> CType -> CompileM ([Instr], Operand)
lowerTypedGlobalVarExpr name ty = case ty of
  CArray _ _ -> pure ([], OGlobal name)
  _ -> do
    aggregateStorage <- isAggregateTypeM ty
    if aggregateStorage
      then pure ([], OGlobal name)
      else do
        out <- freshTemp
        load <- loadInstr out ty (OGlobal name)
        pure ([load], OTemp out)

lowerBinaryExpr :: String -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerBinaryExpr op a b
  | isComparisonOpString op = lowerComparisonExpr op a b
  | op == "/" || op == "%" = do
      (ai, ao) <- lowerExpr a
      (bi, bo) <- lowerExpr b
      commonTy <- usualArithmeticType a b
      let iop
            | isUnsignedType commonTy = if op == "/" then IUDiv else IUMod
            | op == "/" = IDiv
            | otherwise = IMod
      lowerPlainBinOperands iop commonTy ai ao bi bo
  | otherwise = case lowerBinOp op of
      Just iop ->
        if op == "<<"
          then lowerShiftExpr op a b
          else lowerPlainBin iop a b
      Nothing -> throwC ("unsupported binary operator in lowering: " ++ op)

lowerComparisonExpr :: String -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerComparisonExpr op a b = do
  (instrs, iop, ao, bo) <- lowerBranchComparison op a b
  out <- freshTemp
  pure (instrs ++ [IBin out iop ao bo], OTemp out)

data CallTarget = DirectCall String | IndirectCall Operand

lowerCall :: Maybe Temp -> Expr -> [Expr] -> CompileM [Instr]
lowerCall result callee args = case callee of
  EVar name -> resolveCallee name >>= \binding -> lowerCallWithBinding result name binding args
  _ -> lowerComputedCall result callee args

lowerCallWithBinding :: Maybe Temp -> String -> NameBinding -> [Expr] -> CompileM [Instr]
lowerCallWithBinding result name binding args = case binding of
  FunctionBinding ty -> emitTypedCall result (DirectCall name) ty args
  _ -> lowerComputedCall result (EVar name) args

lowerComputedCall :: Maybe Temp -> Expr -> [Expr] -> CompileM [Instr]
lowerComputedCall result callee args = do
  (setup, ptr) <- lowerExpr callee
  ty <- exprType callee
  call <- emitTypedCall result (IndirectCall ptr) ty args
  pure (setup ++ call)

emitTypedCall :: Maybe Temp -> CallTarget -> Maybe CType -> [Expr] -> CompileM [Instr]
emitTypedCall result target ty args = do
  let signature = ty >>= functionSignature
  let fixed = maybe [] snd signature
  (argInstrs, argOps) <- lowerCallArgs fixed args
  let call = case target of
        DirectCall name -> ICall result name argOps
        IndirectCall ptr -> ICallIndirect result ptr argOps
  converted <- case (result, signature) of
    (Just out, Just (ret, _)) -> do
      (instrs, op) <- coerceScalar ret (OTemp out)
      pure (if null instrs then [] else instrs ++ [ICopy out op])
    _ -> pure []
  pure (argInstrs ++ [call] ++ converted)

-- Extra arguments still follow the bootstrap convention for variadic and
-- unprototyped calls. Only a known fixed prefix supplies conversions.
lowerCallArgs :: [CType] -> [Expr] -> CompileM ([Instr], [Operand])
lowerCallArgs fixed args = do
  lowered <- go fixed args
  pure (concatMap fst lowered, map snd lowered)
  where
    go tys exprs = case exprs of
      [] -> pure []
      arg:rest -> case tys of
        [] -> mapM (lowerCallArg Nothing) exprs
        ty:more -> do
          lowered <- lowerCallArg (Just ty) arg
          remaining <- go more rest
          pure (lowered:remaining)

-- The internal convention passes aggregate addresses, not platform ABI
-- aggregate registers/stack slots. Snapshot each struct/union argument as
-- it is evaluated: the callee may mutate this copy, never the source object.
-- Arrays still decay to pointers and must not be copied.
lowerCallArg :: Maybe CType -> Expr -> CompileM ([Instr], Operand)
lowerCallArg param expr = do
  (instrs, raw) <- lowerExpr expr
  (coercions, op) <- coerceMaybeScalar param raw
  let setup = instrs ++ coercions
  mty <- exprType expr
  case mty of
    Nothing -> pure (setup, op)
    Just ty -> do
      aggregate <- aggregateFields ty
      case aggregate of
        Nothing -> pure (setup, op)
        Just _ -> do
          size <- typeSize ty
          temp <- freshTemp
          copies <- copyObject (OTemp temp) op ty
          pure (setup ++ [IAlloca temp size] ++ copies, OTemp temp)

lowerShortCircuit :: Bool -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerShortCircuit isAnd left right = do
  (leftInstrs, leftOp) <- lowerExpr left
  (rightInstrs, rightBool) <- lowerTruthExpr right
  out <- freshTemp
  let (trueIns, trueOp, falseIns, falseOp) =
        if isAnd
          then (rightInstrs, rightBool, [], OImm 0)
          else ([], OImm 1, rightInstrs, rightBool)
  pure ([ICond out leftInstrs leftOp trueIns trueOp falseIns falseOp], OTemp out)

lowerTruthExpr :: Expr -> CompileM ([Instr], Operand)
lowerTruthExpr expr = do
  (instrs, op) <- lowerExpr expr
  if exprIsBoolean expr
    then pure (instrs, op)
    else do
      out <- freshTemp
      pure (instrs ++ [IBin out INe op (OImm 0)], OTemp out)

exprIsBoolean :: Expr -> Bool
exprIsBoolean expr = case expr of
  EUnary "!" _ -> True
  EBinary op _ _ -> op `elem` ["==", "!=", "<", "<=", ">", ">=", "&&", "||"]
  _ -> False

lowerShiftExpr :: String -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerShiftExpr op left right = do
  (leftInstrs, leftOp) <- lowerExpr left
  (rightInstrs, rightOp) <- lowerExpr right
  out <- freshTemp
  iop <- case op of
    ">>" -> shiftRightOp left
    "<<" -> pure IShl
    _ -> pure IShl
  resultTy <- exprType (EBinary op left right)
  (coerceInstrs, coerceOp) <- coerceMaybeScalar resultTy (OTemp out)
  pure (leftInstrs ++ rightInstrs ++ [IBin out iop leftOp rightOp] ++ coerceInstrs, coerceOp)

lowerAddExpr :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerAddExpr a b = do
  (ai, ao) <- lowerExpr a
  (bi, bo) <- lowerExpr b
  aty <- exprType a
  bty <- exprType b
  case pointerElementType aty of
    Just elemTy -> lowerPointerOffset IAdd (ai ++ bi) ao bo elemTy
    Nothing -> case pointerElementType bty of
      Just elemTy -> lowerPointerOffset IAdd (ai ++ bi) bo ao elemTy
      Nothing -> do
        commonTy <- arithmeticTypeFromOperands a aty b bty
        lowerPlainBinOperands IAdd commonTy ai ao bi bo

lowerSubExpr :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerSubExpr a b = do
  (ai, ao) <- lowerExpr a
  (bi, bo) <- lowerExpr b
  aty <- exprType a
  bty <- exprType b
  case pointerElementType aty of
    Just elemTy -> case pointerElementType bty of
      Just _ -> lowerPointerDiff (ai ++ bi) ao bo elemTy
      Nothing -> lowerPointerOffset ISub (ai ++ bi) ao bo elemTy
    Nothing -> do
      commonTy <- arithmeticTypeFromOperands a aty b bty
      lowerPlainBinOperands ISub commonTy ai ao bi bo

lowerPointerDiff :: [Instr] -> Operand -> Operand -> CType -> CompileM ([Instr], Operand)
lowerPointerDiff instrs ao bo elemTy = do
  diff <- freshTemp
  out <- freshTemp
  size <- typeSize elemTy
  pure (instrs ++ [IBin diff ISub ao bo, IBin out IDiv (OTemp diff) (OImm size)], OTemp out)

lowerPointerOffset :: BinOp -> [Instr] -> Operand -> Operand -> CType -> CompileM ([Instr], Operand)
lowerPointerOffset op instrs po oo elemTy = do
  size <- typeSize elemTy
  (scaledInstrs, scaledOp) <- scaledOffset oo size
  out <- freshTemp
  pure (instrs ++ scaledInstrs ++ [IBin out op po scaledOp], OTemp out)

scaledOffset :: Operand -> Int -> CompileM ([Instr], Operand)
scaledOffset offset size =
  if size == 1
    then pure ([], offset)
    else case offset of
      OImm value -> pure ([], OImm (value * size))
      _ -> do
        scaled <- freshTemp
        pure ([IBin scaled IMul offset (OImm size)], OTemp scaled)

lowerPlainBin :: BinOp -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerPlainBin op a b = do
  (ai, ao) <- lowerExpr a
  (bi, bo) <- lowerExpr b
  commonTy <- usualArithmeticType a b
  lowerPlainBinOperands op commonTy ai ao bi bo

lowerPlainBinOperands :: BinOp -> CType -> [Instr] -> Operand -> [Instr] -> Operand -> CompileM ([Instr], Operand)
lowerPlainBinOperands op commonTy ai ao bi bo = do
  (ac, ao') <- coerceScalar commonTy ao
  (bc, bo') <- coerceScalar commonTy bo
  out <- freshTemp
  (rc, result) <- coerceScalar commonTy (OTemp out)
  pure (ai ++ bi ++ ac ++ bc ++ [IBin out op ao' bo'] ++ rc, result)

pointerElementType :: Maybe CType -> Maybe CType
pointerElementType mty = case mty of
  Just (CPtr ty) -> Just ty
  Just (CArray ty _) -> Just ty
  _ -> Nothing

lowerAssignment :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerAssignment lhs rhs = do
  (lhsInstrs, lvalue) <- lowerLValue lhs
  (rhsInstrs, rhsOp) <- lowerExpr rhs
  targetTy <- lValueType lvalue
  (coerceInstrs, coerceOp) <- coerceScalar targetTy rhsOp
  writeInstrs <- writeLValue lvalue coerceOp
  pure (lhsInstrs ++ rhsInstrs ++ coerceInstrs ++ writeInstrs, coerceOp)

lowerCompoundAssignment :: String -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerCompoundAssignment op lhs rhs = do
  (lhsInstrs, lvalue) <- lowerLValue lhs
  (readInstrs, currentOp) <- readLValue lvalue
  targetTy <- lValueType lvalue
  (rhsInstrs, rhsOp) <- lowerExpr rhs
  (opInstrs, resultOp) <- compoundBinOp op targetTy currentOp rhs rhsOp
  (coerceInstrs, coerceOp) <- coerceScalar targetTy resultOp
  writeInstrs <- writeLValue lvalue coerceOp
  pure ( lhsInstrs ++ readInstrs ++ rhsInstrs ++ opInstrs ++ coerceInstrs ++ writeInstrs
       , coerceOp)

compoundBinOp :: String -> CType -> Operand -> Expr -> Operand -> CompileM ([Instr], Operand)
compoundBinOp op targetTy lhsOp rhsExpr rhsOp = case targetTy of
  CPtr elemTy | op == "+" || op == "-" ->
    pointerCompoundOffset (if op == "+" then IAdd else ISub) lhsOp rhsOp elemTy
  _ -> do
    leftTy <- promoteIntegerType targetTy
    rightTy <- promotedExprType rhsExpr
    commonTy <- if op == "<<" || op == ">>"
      then pure leftTy
      else usualArithmeticTypes leftTy rightTy
    (leftInstrs, leftOp) <- coerceScalar commonTy lhsOp
    (rightInstrs, rightOp) <- coerceScalar (if op == "<<" || op == ">>" then rightTy else commonTy) rhsOp
    iop <- case op of
      "/" -> pure (if isUnsignedType commonTy then IUDiv else IDiv)
      "%" -> pure (if isUnsignedType commonTy then IUMod else IMod)
      ">>" -> pure (if isUnsignedType commonTy then IShr else ISar)
      _ -> case lowerBinOp op of
        Just o -> pure o
        Nothing -> throwC ("unsupported compound assignment operator: " ++ op)
    out <- freshTemp
    pure (leftInstrs ++ rightInstrs ++ [IBin out iop leftOp rightOp], OTemp out)

pointerCompoundOffset :: BinOp -> Operand -> Operand -> CType -> CompileM ([Instr], Operand)
pointerCompoundOffset op base offset elemTy = do
  size <- typeSize elemTy
  if size == 1
    then do
      out <- freshTemp
      pure ([IBin out op base offset], OTemp out)
    else do
      scaled <- freshTemp
      out <- freshTemp
      pure ([IBin scaled IMul offset (OImm size), IBin out op base (OTemp scaled)], OTemp out)

lowerIncDec :: Bool -> BinOp -> Expr -> CompileM ([Instr], Operand)
lowerIncDec prefix op target = do
  (lvInstrs, lvalue) <- lowerLValue target
  (readInstrs, current) <- readLValue lvalue
  out <- freshTemp
  step <- incDecStep target
  if prefix
    then do
      ty <- lValueType lvalue
      (coerceInstrs, coerceOp) <- coerceScalar ty (OTemp out)
      writeInstrs <- writeLValue lvalue coerceOp
      pure (lvInstrs ++ readInstrs ++ [IBin out op current (OImm step)] ++ coerceInstrs ++ writeInstrs, coerceOp)
    else do
      old <- freshTemp
      writeInstrs <- writeLValue lvalue (OTemp out)
      let opInstrs = [IBin old IAdd current (OImm 0), IBin out op (OTemp old) (OImm step)]
      pure (lvInstrs ++ readInstrs ++ opInstrs ++ writeInstrs, OTemp old)

incDecStep :: Expr -> CompileM Int
incDecStep target = do
  mty <- exprType target
  case mty of
    Just (CPtr ty) -> typeSize ty
    _ -> pure 1

readLValueExpr :: Expr -> CompileM ([Instr], Operand)
readLValueExpr target = do
  (instrs, lvalue) <- lowerLValue target
  (readInstrs, op) <- readLValue lvalue
  pure (instrs ++ readInstrs, op)

readLValue :: LValue -> CompileM ([Instr], Operand)
readLValue lvalue = case lvalue of
  LLocal temp ty ->
    coerceScalar ty (OTemp temp)
  LAddress addr ty -> case ty of
    CArray _ _ -> pure ([], addr)
    -- Dereferencing a function pointer designates the function, not data at its address.
    CFunc _ _ -> pure ([], addr)
    _ -> do
      aggregateStorage <- isAggregateTypeM ty
      if aggregateStorage
        then pure ([], addr)
        else do
          out <- freshTemp
          load <- loadInstr out ty addr
          pure ([load], OTemp out)

writeLValue :: LValue -> Operand -> CompileM [Instr]
writeLValue lvalue value = case lvalue of
  LLocal temp ty -> do
    aggregateStorage <- isAggregateTypeM ty
    if aggregateStorage
      then copyObject (OTemp temp) value ty
      else pure [ICopy temp value]
  LAddress addr ty -> do
    aggregateStorage <- isAggregateTypeM ty
    if aggregateStorage
      then copyObject addr value ty
      else storeScalar ty addr value

lValueType :: LValue -> CompileM CType
lValueType lvalue = case lvalue of
  LLocal _ ty -> pure ty
  LAddress _ ty -> pure ty

coerceMaybeScalar :: Maybe CType -> Operand -> CompileM ([Instr], Operand)
coerceMaybeScalar mty op = case mty of
  Just ty -> coerceScalar ty op
  Nothing -> pure ([], op)

-- A float value is a signed integer of four bytes, as it is in memory.
coerceScalar :: CType -> Operand -> CompileM ([Instr], Operand)
coerceScalar ty op = case ty of
  CBool -> coerceBool op
  CFloat -> coerceScalar CInt op
  _ -> do
    integer <- isIntegerTypeM ty
    if not integer
      then pure ([], op)
      else do
        size <- typeSize ty
        if size >= 8
          then pure ([], op)
          else case coerceImmediateScalar (isSignedIntegerType ty) size op of
            Just coerced -> pure ([], coerced)
            Nothing ->
              if isSignedIntegerType ty
                then signExtendScalar size op
                else maskScalar size op

coerceBool :: Operand -> CompileM ([Instr], Operand)
coerceBool op = case immediateScalarValue op of
  Just value -> pure ([], OImm (if value == 0 then 0 else 1))
  Nothing -> do
    out <- freshTemp
    pure ([IBin out INe op (OImm 0)], OTemp out)

coerceImmediateScalar :: Bool -> Int -> Operand -> Maybe Operand
coerceImmediateScalar signed size op =
  if size >= 4
    then coerceWordImmediateScalar signed op
    else case immediateScalarValue op of
      Nothing -> Nothing
      Just value ->
        let modulus = pow2 (size * 8)
            masked = positiveMod value modulus
            signBit = pow2 (size * 8 - 1)
            coerced =
              if signed && masked >= signBit
                then masked - modulus
                else masked
        in Just (OImm coerced)

coerceWordImmediateScalar :: Bool -> Operand -> Maybe Operand
coerceWordImmediateScalar signed op = case op of
  OImm value ->
    if signed || value >= 0
      then Just (OImm value)
      else Nothing
  _ -> Nothing

immediateScalarValue :: Operand -> Maybe Int
immediateScalarValue op = case op of
  OImm value -> Just value
  OImmBytes bytes -> Just (littleEndianValue bytes 0)
  _ -> Nothing

littleEndianValue :: [Int] -> Int -> Int
littleEndianValue bytes shift = case bytes of
  [] -> 0
  byte:rest -> byte * pow2 shift + littleEndianValue rest (shift + 8)

positiveMod :: Int -> Int -> Int
positiveMod value modulus =
  let result = value `mod` modulus
  in if result < 0 then result + modulus else result

maskScalar :: Int -> Operand -> CompileM ([Instr], Operand)
maskScalar size op = do
  out <- freshTemp
  pure ([IZExt out size op], OTemp out)

signExtendScalar :: Int -> Operand -> CompileM ([Instr], Operand)
signExtendScalar size op = do
  out <- freshTemp
  pure ([ISExt out size op], OTemp out)

copyObject :: Operand -> Operand -> CType -> CompileM [Instr]
copyObject dst src ty = do
  size <- typeSize ty
  copyObjectBytes dst src 0 size

zeroObject :: Operand -> CType -> CompileM [Instr]
zeroObject dst ty = do
  size <- typeSize ty
  zeroObjectBytes dst 0 size

zeroObjectBytes :: Operand -> Int -> Int -> CompileM [Instr]
zeroObjectBytes dst offset remaining =
  if remaining <= 0
    then pure []
    else do
      word <- targetWordSize
      let width
            | remaining >= word = word
            | remaining >= 4 = 4
            | otherwise = 1
      (dstInstrs, dstAddr) <- offsetAddress dst offset
      let store
            | width == 8 = IStore64 dstAddr (OImm 0)
            | width == 4 = IStore32 dstAddr (OImm 0)
            | otherwise = IStore8 dstAddr (OImm 0)
      rest <- zeroObjectBytes dst (offset + width) (remaining - width)
      pure (dstInstrs ++ [store] ++ rest)

copyObjectBytes :: Operand -> Operand -> Int -> Int -> CompileM [Instr]
copyObjectBytes dst src offset remaining =
  if remaining <= 0
    then pure []
    else do
      word <- targetWordSize
      let width
            | remaining >= word = word
            | remaining >= 4 = 4
            | otherwise = 1
      (dstInstrs, dstAddr) <- offsetAddress dst offset
      (srcInstrs, srcAddr) <- offsetAddress src offset
      val <- freshTemp
      let load = unsignedLoadAt width val srcAddr
      let store = unsignedStoreAt width dstAddr (OTemp val)
      rest <- copyObjectBytes dst src (offset + width) (remaining - width)
      pure (dstInstrs ++ srcInstrs ++ [load, store] ++ rest)

unsignedLoadAt :: Int -> Temp -> Operand -> Instr
unsignedLoadAt width dst addr
  | width == 8 = ILoad64 dst addr
  | width == 4 = ILoad32 dst addr
  | otherwise  = ILoad8 dst addr

unsignedStoreAt :: Int -> Operand -> Operand -> Instr
unsignedStoreAt width addr value
  | width == 8 = IStore64 addr value
  | width == 4 = IStore32 addr value
  | otherwise  = IStore8 addr value

offsetAddress :: Operand -> Int -> CompileM ([Instr], Operand)
offsetAddress base offset =
  if offset == 0
    then pure ([], base)
    else do
      out <- freshTemp
      pure ([IBin out IAdd base (OImm offset)], OTemp out)

lowerLValueAddress :: Expr -> CompileM ([Instr], Operand)
lowerLValueAddress target = case target of
  EVar name -> lowerVarAddress name
  _ -> lowerNonFunctionAddress target

lowerVarAddress :: String -> CompileM ([Instr], Operand)
lowerVarAddress name = do
  binding <- resolveName name
  if isFunctionBinding binding
    then pure ([], OFunction name)
    else lowerNonFunctionAddress (EVar name)

-- A scalar local has a slot of eight bytes, but a long double has 16 bytes.
-- A write of 16 bytes through its address would go into the next slot.
lowerNonFunctionAddress :: Expr -> CompileM ([Instr], Operand)
lowerNonFunctionAddress target = do
  (instrs, lvalue) <- lowerLValue target
  case lvalue of
    LAddress addr _ -> pure (instrs, addr)
    LLocal temp ty -> do
      aggregateStorage <- isAggregateTypeM ty
      if aggregateStorage
        then pure (instrs, OTemp temp)
        else do
          size <- typeSize ty
          if size > 8
            then throwC "unsupported address of a long double local"
            else do
              out <- freshTemp
              pure (instrs ++ [IAddrOf out temp], OTemp out)

lowerLValue :: Expr -> CompileM ([Instr], LValue)
lowerLValue target = case target of
  EVar name -> do
    binding <- resolveName name
    case binding of
      LocalBinding temp ty -> pure ([], LLocal temp ty)
      GlobalBinding label ty -> pure ([], LAddress (OGlobal label) ty)
      _ -> throwC ("not an object: " ++ name)
  EUnary "*" ptr -> do
    (instrs, op) <- lowerExpr ptr
    ty <- exprType target
    knownTy <- requireMaybeType "dereference has unknown pointed-to type" ty
    pure (instrs, LAddress op knownTy)
  EIndex base ix -> do
    (baseInstrs, baseOp) <- lowerExpr base
    (ixInstrs, ixOp) <- lowerExpr ix
    elemTy <- indexedElementType base
    elemSize <- typeSize elemTy
    (scaleInstrs, offsetOp) <- scaledIndex ixOp elemSize
    addr <- freshTemp
    pure (baseInstrs ++ ixInstrs ++ scaleInstrs ++ [IBin addr IAdd baseOp offsetOp], LAddress (OTemp addr) elemTy)
  EPtrMember base field -> do
    (baseInstrs, baseOp) <- lowerExpr base
    baseTy <- exprType base
    (fieldTy, offset) <- memberInfo baseTy field
    (addrInstrs, addrOp) <- offsetAddress baseOp offset
    pure (baseInstrs ++ addrInstrs, LAddress addrOp fieldTy)
  EMember base field -> do
    (baseInstrs, baseAddr) <- lowerLValueAddress base
    baseTy <- exprType base
    knownBaseTy <- requireMaybeType "member base has unknown type" baseTy
    (fieldTy, offset) <- memberInfo (Just (CPtr knownBaseTy)) field
    (addrInstrs, addrOp) <- offsetAddress baseAddr offset
    pure (baseInstrs ++ addrInstrs, LAddress addrOp fieldTy)
  _ -> throwC ("unsupported lvalue: " ++ renderExprTag target)

sizeofExprSize :: Expr -> CompileM Int
sizeofExprSize value = case value of
  EString bytes -> pure (length bytes)
  _ -> do
    mty <- exprType value
    ty <- requireMaybeType "sizeof expression has unknown type" mty
    typeSize ty

requireMaybeType :: String -> Maybe CType -> CompileM CType
requireMaybeType msg mty = case mty of
  Just ty -> pure ty
  Nothing -> throwC msg

indexedElementType :: Expr -> CompileM CType
indexedElementType base = do
  mty <- exprType base
  case mty of
    Just (CPtr ty) -> pure ty
    Just (CArray ty _) -> pure ty
    _ -> throwC "subscripted value has unknown element type"

scaledIndex :: Operand -> Int -> CompileM ([Instr], Operand)
scaledIndex index size =
  if size == 1
    then pure ([], index)
    else do
      scaled <- freshTemp
      pure ([IBin scaled IMul index (OImm size)], OTemp scaled)

exprType :: Expr -> CompileM (Maybe CType)
exprType expr = case expr of
  EInt text -> Just <$> integerLiteralType text
  EFloat text -> pure (Just (floatLiteralType text))
  EChar _ -> pure (Just CInt)
  EString _ -> pure (Just (CPtr CChar))
  ESizeofType _ -> pure (Just (CNamed "size_t"))
  ESizeofExpr _ -> pure (Just (CNamed "size_t"))
  EVar name -> do
    binding <- resolveName name
    pure (case binding of
      UnknownBinding | isFunctionNameMacro name -> Just (CPtr CChar)
      UnknownBinding -> fmap (const CInt) (builtinConstant name)
      _ -> bindingType binding)
  ECast ty _ -> pure (Just ty)
  EUnary "+" value -> do
    ty <- promotedExprType value
    pure (Just ty)
  EUnary "-" value -> do
    ty <- promotedExprType value
    pure (Just ty)
  EUnary "~" value -> do
    ty <- promotedExprType value
    pure (Just ty)
  EUnary "!" _ -> pure (Just CInt)
  EUnary "*" value -> do
    mty <- exprType value
    pure (case mty of
      Just (CPtr ty) -> Just ty
      Just (CArray ty _) -> Just ty
      _ -> Nothing)
  EUnary "&" value -> do
    mty <- exprType value
    pure (fmap CPtr mty)
  EIndex base _ -> do
    mty <- exprType base
    pure (case mty of
      Just (CPtr ty) -> Just ty
      Just (CArray ty _) -> Just ty
      _ -> Nothing)
  EPtrMember base field -> do
    baseTy <- exprType base
    info <- memberInfoMaybe baseTy field
    pure (fmap fst info)
  EMember base field -> do
    baseTy <- exprType base
    knownBaseTy <- requireMaybeType "member base has unknown type" baseTy
    info <- memberInfoMaybe (Just (CPtr knownBaseTy)) field
    pure (fmap fst info)
  EBinary "<<" left _ -> do
    leftTy <- exprType left
    promoteMaybeIntegerType leftTy
  EBinary ">>" left _ -> do
    leftTy <- exprType left
    promoteMaybeIntegerType leftTy
  EBinary "," _ right -> exprType right
  EBinary "&&" _ _ -> pure (Just CInt)
  EBinary "||" _ _ -> pure (Just CInt)
  EBinary op left right -> do
    if isComparisonOpString op
      then pure (Just CInt)
      else do
        leftTy <- exprType left
        rightTy <- exprType right
        arithmeticTy <- arithmeticTypeFromOperands left leftTy right rightTy
        pure (case op of
          "+" -> addExprResultType leftTy rightTy arithmeticTy
          "-" -> subExprResultType leftTy rightTy arithmeticTy
          _ -> Just arithmeticTy)
  ECond _ yes no -> conditionalType yes no
  EAssign lhs _ -> exprType lhs
  ECompoundAssign _ lhs _ -> exprType lhs
  EPostfix _ value -> exprType value
  EUnary "++" value -> exprType value
  EUnary "--" value -> exprType value
  ECall (EVar name) _ -> do
    binding <- resolveName name
    pure (case binding of
      UnknownBinding | allowsImplicitFunction name -> Just CLong
      FunctionBinding Nothing -> Just CLong
      _ -> functionResultType =<< bindingType binding)
  ECall callee _ -> do
    calleeTy <- exprType callee
    pure (functionResultType =<< calleeTy)
  _ -> pure Nothing

conditionalType :: Expr -> Expr -> CompileM (Maybe CType)
conditionalType yes no = do
  yesTy <- exprType yes
  noTy <- exprType no
  case (yesTy, noTy) of
    (Just a, Just b) -> do
      ai <- isIntegerTypeM a
      bi <- isIntegerTypeM b
      if (ai || isFloatingType a) && (bi || isFloatingType b)
        then do
          ty <- arithmeticTypeFromOperands yes yesTy no noTy
          pure (Just ty)
        else case pointerElementType yesTy of
          Just inner -> pure (Just (CPtr inner))
          Nothing -> case pointerElementType noTy of
            Just inner -> pure (Just (CPtr inner))
            Nothing -> pure yesTy
    (Just _, Nothing) -> pure yesTy
    _ -> pure noTy

promoteMaybeIntegerType :: Maybe CType -> CompileM (Maybe CType)
promoteMaybeIntegerType mty = case mty of
  Nothing -> pure Nothing
  Just ty -> do
    promoted <- promoteIntegerType ty
    pure (Just promoted)

functionResultType :: CType -> Maybe CType
functionResultType ty = fst <$> functionSignature ty

functionSignature :: CType -> Maybe (CType, [CType])
functionSignature ty = case ty of
  CFunc ret params -> Just (ret, params)
  CPtr inner -> functionSignature inner
  _ -> Nothing

isFunctionNameMacro :: String -> Bool
isFunctionNameMacro name =
  name `elem` ["__func__", "__FUNCTION__", "__PRETTY_FUNCTION__"]

addExprResultType :: Maybe CType -> Maybe CType -> CType -> Maybe CType
addExprResultType leftTy rightTy arithmeticTy = case pointerElementType leftTy of
  Just inner -> Just (CPtr inner)
  Nothing -> case pointerElementType rightTy of
    Just inner -> Just (CPtr inner)
    Nothing -> Just arithmeticTy

subExprResultType :: Maybe CType -> Maybe CType -> CType -> Maybe CType
subExprResultType leftTy rightTy arithmeticTy = case pointerElementType leftTy of
  Just inner -> case pointerElementType rightTy of
    Just _ -> Just CLong
    Nothing -> Just (CPtr inner)
  Nothing -> Just arithmeticTy

memberInfo :: Maybe CType -> String -> CompileM (CType, Int)
memberInfo mty field = do
  found <- memberInfoMaybe mty field
  case found of
    Just info -> pure info
    Nothing -> throwC ("unknown struct member: " ++ field ++ " on aggregate")

memberInfoMaybe :: Maybe CType -> String -> CompileM (Maybe (CType, Int))
memberInfoMaybe mty field = case mty of
  Just (CPtr ty) -> memberInfoForAggregate ty field
  _ -> pure Nothing

memberInfoForAggregate :: CType -> String -> CompileM (Maybe (CType, Int))
memberInfoForAggregate ty field = case aggregateCacheName ty of
  Just name -> do
    cached <- lookupStructMemberCache name field
    case cached of
      Just info -> pure (Just info)
      Nothing -> do
        found <- memberInfoForAggregateUncached ty field
        case found of
          Just info -> cacheStructMember name field info >> pure (Just info)
          Nothing -> pure Nothing
  Nothing -> memberInfoForAggregateUncached ty field

memberInfoForAggregateUncached :: CType -> String -> CompileM (Maybe (CType, Int))
memberInfoForAggregateUncached ty field = do
  aggregate <- aggregateFields ty
  case aggregate of
    Nothing -> pure Nothing
    Just aggregateInfo -> case aggregateInfo of
      (isUnion, fields) -> fieldOffset 0 isUnion field 0 fields

aggregateCacheName :: CType -> Maybe String
aggregateCacheName ty = case ty of
  CStruct name -> Just name
  CUnion name -> Just name
  CStructNamed name _ -> Just name
  CUnionNamed name _ -> Just name
  CNamed name -> Just name
  _ -> Nothing

fieldOffset :: Int -> Bool -> String -> Int -> [Field] -> CompileM (Maybe (CType, Int))
fieldOffset baseOffset isUnion field offset fields = case fields of
  [] -> pure Nothing
  item:rest -> case item of
    Field ty name -> do
      align <- typeAlign ty
      let aligned = alignUp offset align
      let memberOffset = baseOffset + unionOffset isUnion aligned
      if name == field
        then pure (Just (ty, memberOffset))
        else do
          size <- typeSize ty
          nested <- anonymousMemberInfoForName memberOffset ty name field
          case nested of
            Just info -> pure (Just info)
            Nothing -> fieldOffset baseOffset isUnion field (aligned + size) rest

unionOffset :: Bool -> Int -> Int
unionOffset isUnion aligned =
  if isUnion then 0 else aligned

anonymousMemberInfoForName :: Int -> CType -> String -> String -> CompileM (Maybe (CType, Int))
anonymousMemberInfoForName offset ty name field =
  if name == ""
    then anonymousMemberInfo offset ty field
    else pure Nothing

anonymousMemberInfo :: Int -> CType -> String -> CompileM (Maybe (CType, Int))
anonymousMemberInfo baseOffset ty field = do
  aggregate <- aggregateFields ty
  case aggregate of
    Nothing -> pure Nothing
    Just aggregateInfo -> case aggregateInfo of
      (isUnion, fields) -> fieldOffset baseOffset isUnion field 0 fields

loadInstr :: Temp -> CType -> Operand -> CompileM Instr
loadInstr out ty addr = do
  size <- typeSize ty
  let signed = isSignedIntegerType ty || isFloatingType ty
  pure (if size <= 1
        then (if signed then ILoadS8 else ILoad8) out addr
        else if size <= 2
        then (if signed then ILoadS16 else ILoad16) out addr
        else if size <= 4
        then (if signed then ILoadS32 else ILoad32) out addr
        else ILoad64 out addr)

isSignedIntegerType :: CType -> Bool
isSignedIntegerType ty = case ty of
  CChar -> True
  CShort -> True
  CInt -> True
  CLong -> True
  CLongLong -> True
  CEnum _ -> True
  CNamed name -> isSignedNamedInteger name
  _ -> False

isIntegerTypeM :: CType -> CompileM Bool
isIntegerTypeM ty = case ty of
  CChar -> pure True
  CShort -> pure True
  CUnsignedChar -> pure True
  CUnsignedShort -> pure True
  CInt -> pure True
  CUnsigned -> pure True
  CLong -> pure True
  CUnsignedLong -> pure True
  CLongLong -> pure True
  CUnsignedLongLong -> pure True
  CBool -> pure True
  CEnum _ -> pure True
  CNamed name -> pure (isNamedInteger name)
  _ -> pure False

promoteIntegerType :: CType -> CompileM CType
promoteIntegerType ty = do
  integer <- isIntegerTypeM ty
  if not integer
    then pure ty
    else do
      size <- typeSize ty
      pure (if size < 4 then CInt else ty)

usualArithmeticType :: Expr -> Expr -> CompileM CType
usualArithmeticType left right = do
  leftTy0 <- promotedExprType left
  rightTy0 <- promotedExprType right
  usualArithmeticTypes leftTy0 rightTy0

-- These callers already queried both operands. Re-querying their ASTs here
-- doubles the recursive type walks at each nested arithmetic operator.
arithmeticTypeFromOperands :: Expr -> Maybe CType -> Expr -> Maybe CType -> CompileM CType
arithmeticTypeFromOperands left leftTy right rightTy = do
  a <- promoteOperandType left leftTy
  b <- promoteOperandType right rightTy
  usualArithmeticTypes a b

usualArithmeticTypes :: CType -> CType -> CompileM CType
usualArithmeticTypes leftTy0 rightTy0 =
  if isFloatingType leftTy0 || isFloatingType rightTy0
    then pure (usualFloatingType leftTy0 rightTy0)
    else do
      leftTy <- canonicalIntegerType leftTy0
      rightTy <- canonicalIntegerType rightTy0
      if integerKindId leftTy == integerKindId rightTy
        then pure leftTy
        else if isUnsignedType leftTy == isUnsignedType rightTy
          then pure (higherRankType leftTy rightTy)
          else do
            let (signedTy, unsignedTy) =
                  if isUnsignedType leftTy then (rightTy, leftTy) else (leftTy, rightTy)
            if integerRank unsignedTy >= integerRank signedTy
              then pure unsignedTy
              else do
                signedSize <- typeSize signedTy
                unsignedSize <- typeSize unsignedTy
                if signedSize > unsignedSize
                  then pure signedTy
                  else pure (correspondingUnsigned signedTy)

isFloatingType :: CType -> Bool
isFloatingType ty = case ty of
  CFloat -> True
  CDouble -> True
  CLongDouble -> True
  _ -> False

usualFloatingType :: CType -> CType -> CType
usualFloatingType leftTy rightTy
  | isLongDoubleType leftTy || isLongDoubleType rightTy = CLongDouble
  | isDoubleType leftTy || isDoubleType rightTy = CDouble
  | otherwise = CFloat

isLongDoubleType :: CType -> Bool
isLongDoubleType ty = case ty of
  CLongDouble -> True
  _ -> False

isDoubleType :: CType -> Bool
isDoubleType ty = case ty of
  CDouble -> True
  _ -> False

canonicalIntegerType :: CType -> CompileM CType
canonicalIntegerType ty = do
  integer <- isIntegerTypeM ty
  if not integer
    then pure ty
    else case ty of
      CInt -> pure ty
      CUnsigned -> pure ty
      CLong -> pure ty
      CUnsignedLong -> pure ty
      CLongLong -> pure ty
      CUnsignedLongLong -> pure ty
      _ -> do
        size <- typeSize ty
        word <- targetWordSize
        pure (canonicalIntegerBySize size word (isUnsignedType ty))

canonicalIntegerBySize :: Int -> Int -> Bool -> CType
canonicalIntegerBySize size word unsigned
  | size <= 4 = if unsigned then CUnsigned else CInt
  | size == word = if unsigned then CUnsignedLong else CLong
  | otherwise = if unsigned then CUnsignedLongLong else CLongLong

integerRank :: CType -> Int
integerRank ty = case ty of
  CInt -> 1
  CUnsigned -> 1
  CLong -> 2
  CUnsignedLong -> 2
  CLongLong -> 3
  CUnsignedLongLong -> 3
  _ -> 1

integerKindId :: CType -> Int
integerKindId ty = case ty of
  CInt -> 0
  CUnsigned -> 1
  CLong -> 2
  CUnsignedLong -> 3
  CLongLong -> 4
  CUnsignedLongLong -> 5
  _ -> -1

higherRankType :: CType -> CType -> CType
higherRankType a b = if integerRank a >= integerRank b then a else b

correspondingUnsigned :: CType -> CType
correspondingUnsigned ty = case ty of
  CInt -> CUnsigned
  CLong -> CUnsignedLong
  CLongLong -> CUnsignedLongLong
  _ -> ty

integerLiteralType :: String -> CompileM CType
integerLiteralType text = do
  word <- targetWordSize
  case constantLiteralRankedChecked word False text of
    Left msg -> throwC msg
    Right (rank, Constant _ unsigned _) -> pure (case rank of
      1 -> if unsigned then CUnsigned else CInt
      2 -> if unsigned then CUnsignedLong else CLong
      _ -> if unsigned then CUnsignedLongLong else CLongLong)

promotedExprType :: Expr -> CompileM CType
promotedExprType expr = exprType expr >>= promoteOperandType expr

promoteOperandType :: Expr -> Maybe CType -> CompileM CType
promoteOperandType expr mty = do
  ty <- requireMaybeType ("expression has unknown type: " ++ renderExprTag expr) mty
  promoteIntegerType ty

floatLiteralType :: String -> CType
floatLiteralType text =
  case floatLiteralSize text of
    4 -> CFloat
    16 -> CLongDouble
    _ -> CDouble

-- A long double has eight value bytes. The store sets the other bytes to
-- zero, thus a zero value is zero in all bytes of the object.
storeScalar :: CType -> Operand -> Operand -> CompileM [Instr]
storeScalar ty addr value = do
  size <- typeSize ty
  store <- storeInstr ty addr value
  pad <- zeroObjectBytes addr 8 (size - 8)
  pure (store : pad)

storeInstr :: CType -> Operand -> Operand -> CompileM Instr
storeInstr ty addr value = do
  size <- typeSize ty
  pure (if size <= 1 then IStore8 addr value else if size <= 2 then IStore16 addr value else if size <= 4 then IStore32 addr value else IStore64 addr value)

typeSize :: CType -> CompileM Int
typeSize ty = case ty of
  CVoid -> pure 1
  CBool -> pure 1
  CChar -> pure 1
  CUnsignedChar -> pure 1
  CShort -> pure 2
  CUnsignedShort -> pure 2
  CInt -> pure 4
  CUnsigned -> pure 4
  CFloat -> pure 4
  CLong -> targetWordSize
  CUnsignedLong -> targetWordSize
  CLongLong -> pure 8
  CUnsignedLongLong -> pure 8
  CDouble -> pure 8
  CLongDouble -> pure 16
  CPtr _ -> targetWordSize
  CFunc _ _ -> targetWordSize
  CArray inner count -> do
    size <- typeSize inner
    bound <- arrayBoundSize count
    checkedArraySize size bound
  CStruct name -> structSize name
  CUnion name -> structSize name
  CStructNamed _ fields -> aggregateSize False fields
  CUnionNamed _ fields -> aggregateSize True fields
  CStructDef fields -> aggregateSize False fields
  CUnionDef fields -> aggregateSize True fields
  CEnum _ -> pure 4
  CNamed name -> namedTypeSize name

namedTypeSize :: String -> CompileM Int
namedTypeSize name = do
  word <- targetWordSize
  case namedIntegerSize word name of
    Just size -> pure size
    Nothing -> do
      fields <- lookupStruct name
      case fields of
        Just _ -> structSize name
        Nothing -> throwC ("unknown type: " ++ name)

typeAlign :: CType -> CompileM Int
typeAlign ty = case ty of
  CArray inner _ -> typeAlign inner
  _ -> do
    aggregate <- aggregateFields ty
    case aggregate of
      Just (_, fields) -> aggregateAlign fields
      Nothing -> do
        size <- typeSize ty
        pure (if size >= 8 then 8 else if size >= 4 then 4 else if size >= 2 then 2 else 1)

aggregateAlign :: [Field] -> CompileM Int
aggregateAlign fields = case fields of
  [] -> pure 1
  Field ty _:rest -> do
    align <- typeAlign ty
    restAlign <- aggregateAlign rest
    pure (max align restAlign)

structSize :: String -> CompileM Int
structSize name = do
  cached <- lookupStructSizeCache name
  case cached of
    Just size -> pure size
    Nothing -> do
      aggregate <- lookupStruct name
      case aggregate of
        Nothing -> throwC ("unknown struct or union: " ++ name)
        Just aggregateInfo -> case aggregateInfo of
          (isUnion, fields) -> do
            size <- aggregateSize isUnion fields
            cacheStructSize name size
            pure size

aggregateSize :: Bool -> [Field] -> CompileM Int
aggregateSize isUnion fields =
  if isUnion
    then aggregateUnionSize fields
    else aggregateStructSize fields

aggregateStructSize :: [Field] -> CompileM Int
aggregateStructSize fields = do
  folded <- foldAggregateFields 0 1 fields
  case folded of
    (size, maxAlign) -> pure (alignUp size maxAlign)

foldAggregateFields :: Int -> Int -> [Field] -> CompileM (Int, Int)
foldAggregateFields offset maxAlign members = case members of
  [] -> pure (offset, maxAlign)
  item:rest -> case item of
    Field ty _ -> do
      align <- typeAlign ty
      size <- typeSize ty
      let aligned = alignUp offset align
      foldAggregateFields (aligned + size) (max maxAlign align) rest

aggregateUnionSize :: [Field] -> CompileM Int
aggregateUnionSize members = do
  folded <- unionFields members
  case folded of
    (size, align) -> pure (alignUp size align)

unionFields :: [Field] -> CompileM (Int, Int)
unionFields members = case members of
  [] -> pure (0, 1)
  item:rest -> case item of
    Field ty _ -> do
      size <- typeSize ty
      align <- typeAlign ty
      folded <- unionFields rest
      case folded of
        (restSize, restAlign) -> pure (max size restSize, max align restAlign)

alignUp :: Int -> Int -> Int
alignUp offset align =
  let remnant = offset `mod` align
  in if remnant == 0 then offset else offset + align - remnant

globalData :: CType -> Maybe Expr -> CompileM [DataValue]
globalData ty initExpr = do
  values <- globalDataValue ty initExpr
  size <- typeSize ty
  padDataTarget size values

globalDataValue :: CType -> Maybe Expr -> CompileM [DataValue]
globalDataValue ty initExpr = case initExpr of
  Nothing -> zeroDataForType ty
  Just expr -> globalDataExpr ty expr

zeroData :: Int -> [DataValue]
zeroData n = if n <= 0 then [] else [DZero n]

zeroDataForType :: CType -> CompileM [DataValue]
zeroDataForType ty = do
  size <- typeSize ty
  pure (zeroData size)

globalDataExpr :: CType -> Expr -> CompileM [DataValue]
globalDataExpr ty expr = case expr of
  EInitList exprs -> globalInitListData ty exprs
  EString bytes -> globalStringData ty bytes
  EInt _ -> scalarConstantData ty expr
  EFloat text -> scalarFloatData ty text
  EChar _ -> scalarConstantData ty expr
  ECast castTy value -> do
    registerTypeIntroductions castTy
    address <- staticAddressInitializer value
    if address then globalDataValue ty (Just value) else scalarConstantData ty expr
  EUnary "&" value -> globalAddressExprData ty value
  EVar name -> globalVarData ty name
  _ -> scalarConstantData ty expr

-- Relocations are not integer constants.
staticAddressInitializer :: Expr -> CompileM Bool
staticAddressInitializer expr = case expr of
  ECast _ value -> staticAddressInitializer value
  EString _ -> pure True
  EUnary "&" (EVar _) -> pure True
  EVar name -> do
    value <- lookupConstant name
    pure (case value of
      Just _ -> False
      Nothing -> case builtinConstant name of
        Just _ -> False
        Nothing -> True)
  _ -> pure False

globalInitListData :: CType -> [Expr] -> CompileM [DataValue]
globalInitListData ty exprs =
  if not (isAggregateType ty) && singleExprList exprs
    then case exprs of
      expr:_ -> globalDataValue ty (Just expr)
      [] -> zeroDataForType ty
    else case ty of
      CArray inner count -> globalArrayInitData inner count exprs
      _ -> globalAggregateInitData ty exprs

singleExprList :: [Expr] -> Bool
singleExprList exprs = case exprs of
  [_] -> True
  _ -> False

globalArrayInitData :: CType -> Maybe Expr -> [Expr] -> CompileM [DataValue]
globalArrayInitData inner count exprs = do
  items <- globalArrayData inner exprs
  case count of
    Nothing -> pure items
    Just bound -> do
      n <- arrayBoundSize (Just bound)
      elemSize <- typeSize inner
      size <- checkedArraySize elemSize n
      if length exprs > n
        then throwC "excess elements in array initializer"
        else padDataTarget size items

globalAggregateInitData :: CType -> [Expr] -> CompileM [DataValue]
globalAggregateInitData ty exprs = do
  aggregate <- aggregateFields ty
  case aggregate of
    Just aggregateInfo -> case aggregateInfo of
      (False, fields) -> globalStructData fields exprs
      (True, fields) -> globalUnionData fields exprs
    Nothing -> case exprs of
      [] -> zeroDataForType ty
      _ -> throwC "excess elements in scalar initializer"

globalStringData :: CType -> [Int] -> CompileM [DataValue]
globalStringData ty bytes = case ty of
  CArray CChar count -> do
    size <- stringDataSize count bytes
    -- An array with the length of the text has no terminator.
    if length bytes == size + 1
      then pure (map DByte (take size bytes))
      else if length bytes > size
        then throwC "string initializer is longer than its array"
        else padDataTarget size (map DByte bytes)
  _ -> if isPointerType ty
    then do
      dataLabel <- freshDataLabel
      addDataItem (DataItem dataLabel (map DByte bytes))
      pure [DAddress dataLabel]
    else scalarConstantData ty (EString bytes)

stringDataSize :: Maybe Expr -> [Int] -> CompileM Int
stringDataSize count bytes = case count of
  Nothing -> pure (length bytes)
  Just bound -> arrayBoundSize (Just bound)

globalAddressExprData :: CType -> Expr -> CompileM [DataValue]
globalAddressExprData ty value = case value of
  EVar name -> globalAddressData name
  _ -> scalarConstantData ty (EUnary "&" value)

globalVarData :: CType -> String -> CompileM [DataValue]
globalVarData ty name = do
  constant <- lookupConstant name
  case constant of
    Just value -> scalarData ty value
    Nothing -> case builtinConstant name of
      Just value -> scalarData ty value
      Nothing -> globalAddressData name

globalArrayData :: CType -> [Expr] -> CompileM [DataValue]
globalArrayData inner exprs = case exprs of
  [] -> pure []
  expr:rest -> do
    item <- globalDataValue inner (Just expr)
    elemSize <- typeSize inner
    tailItems <- globalArrayData inner rest
    padded <- padDataTarget elemSize item
    pure (padded ++ tailItems)

globalStructData :: [Field] -> [Expr] -> CompileM [DataValue]
globalStructData fields exprs = do
  (values, used) <- structFields 0 fields exprs
  padDataTarget used values

structFields :: Int -> [Field] -> [Expr] -> CompileM ([DataValue], Int)
structFields offset remaining values = case remaining of
  [] -> case values of
    [] -> pure ([], offset)
    _ -> throwC "excess elements in struct initializer"
  field:rest -> case field of
    Field fieldTy _ -> do
      align <- typeAlign fieldTy
      let aligned = alignUp offset align
      fieldSize <- typeSize fieldTy
      let (valueHead, valueTail) = case values of
            [] -> (Nothing, [])
            expr:restExprs -> (Just expr, restExprs)
      fieldData <- globalDataValue fieldTy valueHead
      paddedField <- padDataTarget fieldSize fieldData
      (restData, end) <- structFields (aligned + fieldSize) rest valueTail
      pure (zeroData (aligned - offset) ++ paddedField ++ restData, end)

globalUnionData :: [Field] -> [Expr] -> CompileM [DataValue]
globalUnionData fields exprs = case exprs of
  [] -> zeroUnionData fields
  [expr] -> case fields of
    Field fieldTy _:_ -> do
      item <- globalDataValue fieldTy (Just expr)
      size <- unionSizeFromFields fields
      padDataTarget size item
    [] -> throwC "excess elements in union initializer"
  _ -> throwC "excess elements in union initializer"

zeroUnionData :: [Field] -> CompileM [DataValue]
zeroUnionData fields = do
  size <- unionSizeFromFields fields
  pure (zeroData size)

unionSizeFromFields :: [Field] -> CompileM Int
unionSizeFromFields fields = case fields of
  [] -> pure 0
  Field ty _:rest -> do
    size <- typeSize ty
    tailSize <- unionSizeFromFields rest
    pure (max size tailSize)

isAggregateTypeM :: CType -> CompileM Bool
isAggregateTypeM ty = case ty of
  CArray _ _ -> pure True
  CNamed _ -> do
    aggregate <- aggregateFields ty
    pure (maybe False (const True) aggregate)
  _ -> pure (isAggregateType ty)

scalarData :: CType -> Int -> CompileM [DataValue]
scalarData ty value = constantData ty (constantInt 4 value)

scalarConstantData :: CType -> Expr -> CompileM [DataValue]
scalarConstantData ty expr = do
  value <- constExprTyped True True expr
  constantData ty value

-- Integer zero has a supported floating storage representation on our
-- targets. Handle it only at serialization: floating intermediates are not
-- integer Constants, and general floating conversions remain unsupported.
constantData :: CType -> Constant -> CompileM [DataValue]
constantData ty value =
  if isFloatingType ty && not (constantTrue value)
    then zeroDataForType ty
    else do
      converted <- castConstant ty value
      case converted of
        Constant _ _ bytes -> pure (map DByte bytes)

castConstant :: CType -> Constant -> CompileM Constant
castConstant ty value = case ty of
  CBool -> pure (constantInt 1 (boolToInt (constantTrue value)))
  _ -> do
    integer <- isIntegerTypeM ty
    if integer || isPointerType ty
      then do
        size <- typeSize ty
        pure (constantConvert size (isUnsignedType ty || isPointerType ty) value)
      else throwC "unsupported non-integer constant conversion"

scalarFloatData :: CType -> String -> CompileM [DataValue]
scalarFloatData ty text = do
  size <- typeSize ty
  case floatLiteralBytes size text of
    Left msg -> throwC msg
    Right bytes -> pure (map DByte bytes)

padDataTarget :: Int -> [DataValue] -> CompileM [DataValue]
padDataTarget size values = do
  word <- targetWordSize
  let used = dataSizeTarget word values
  if used > size
    then throwC (if dataHasAddress values
      then "address initializer is larger than its object"
      else "initializer is larger than its object")
    else pure (values ++ zeroData (size - used))

dataHasAddress :: [DataValue] -> Bool
dataHasAddress values = case values of
  [] -> False
  DAddress _:_ -> True
  _:rest -> dataHasAddress rest

dataSizeTarget :: Int -> [DataValue] -> Int
dataSizeTarget word = foldr addSize 0 where
  addSize value n = case value of
    DByte _ -> 1 + n
    DZero count -> count + n
    DAddress _ -> word + n

globalAddressData :: String -> CompileM [DataValue]
globalAddressData name = do
  binding <- resolveName name
  case binding of
    LocalBinding _ _ -> throwC ("constant initializer has the address of local " ++ name)
    GlobalBinding label _ -> pure [DAddress label]
    FunctionBinding _ -> pure [DAddress ("FUNCTION_" ++ name)]
    UnknownBinding -> throwC ("unknown identifier: " ++ name)

-- Preserve target widths and signedness until the final storage conversion.
-- Layout queries fold bounds without introducing definitions or function names.
constExprTyped :: Bool -> Bool -> Expr -> CompileM Constant
constExprTyped introductions live expr = case expr of
  EInt text -> do
    word <- targetWordSize
    case constantLiteralChecked word False text of
      Right value -> pure value
      Left msg -> throwC msg
  EChar text -> pure (constantInt 4 (charValue text))
  ESizeofType ty -> do
    if introductions then registerExprIntroductions expr else pure ()
    typeSize ty >>= sizeConstant
  ESizeofExpr value -> do
    if introductions then registerExprIntroductions expr else pure ()
    -- sizeof never folds its operand's value (including casts and comma).
    sizeofExprSize value >>= sizeConstant
  EUnary "&" (EPtrMember (ECast (CPtr ty) (EInt "0")) field) -> do
    if introductions then registerTypeIntroductions ty else pure ()
    info <- memberInfo (Just (CPtr ty)) field
    sizeConstant (snd info)
  EVar name -> do
    constant <- lookupConstant name
    case constant of
      Just value -> pure (constantInt 4 value)
      Nothing -> case builtinConstant name of
        Just value -> pure (constantInt 4 value)
        Nothing -> if live then throwC ("unknown constant: " ++ name)
                   else unevaluatedConstant introductions expr
  ECast ty value -> do
    if introductions then registerTypeIntroductions ty else pure ()
    constExprTyped introductions live value >>= castConstant ty
  EUnary op value | op `elem` ["-", "+", "~", "!"] -> do
    n <- constExprTyped introductions live value
    pure (if op == "!" then constantInt 4 (boolToInt (not (constantTrue n)))
          else constantUnary op (constantPromote n))
  EBinary op left right -> do
    a <- constExprTyped introductions live left
    let rightLive = live && (if op == "&&" then constantTrue a
                            else if op == "||" then not (constantTrue a) else True)
    b <- constExprTyped introductions rightLive right
    let a' = constantPromote a
        b' = constantPromote b
    case constantBinary op a' b' of
      Right value -> pure value
      Left msg -> if live then throwC msg
        else pure (if op == "<<" || op == ">>" then a' else fst (constantCommon a' b'))
  ECond cond yes no -> do
    c <- constExprTyped introductions live cond
    a <- constExprTyped introductions (live && constantTrue c) yes
    b <- constExprTyped introductions (live && not (constantTrue c)) no
    let (a', b') = constantCommon (constantPromote a) (constantPromote b)
    pure (if constantTrue c then a' else b')
  _ -> if live then throwC ("unsupported constant expression: " ++ renderExprTag expr)
       else unevaluatedConstant introductions expr

-- Dead constant-expression arms contribute their type, not a runtime value.
-- sizeof queries exprType directly and never enters the value folder.
unevaluatedConstant :: Bool -> Expr -> CompileM Constant
unevaluatedConstant introductions expr = do
  if introductions then registerExprIntroductions expr else pure ()
  mty <- exprType expr
  ty <- requireMaybeType "unevaluated constant expression has unknown type" mty
  castConstant ty (constantInt 4 0)

sizeConstant :: Int -> CompileM Constant
sizeConstant n = do
  word <- targetWordSize
  pure (constantConvert word True (constantInt word n))

arrayBoundSize :: Maybe Expr -> CompileM Int
arrayBoundSize bound = case bound of
  Nothing -> pure 0
  Just expr -> do
    value <- constExprTyped False True expr
    case constantToIntChecked value of
      Nothing -> throwC "array extent exceeds supported layout range"
      Just n -> if n < 0 then throwC "negative array extent" else pure n

checkedArraySize :: Int -> Int -> CompileM Int
checkedArraySize size count =
  if count > 0 && size > 2147483647 `div` count
    then throwC "array size exceeds supported layout range"
    else pure (size * count)

shiftRightOp :: Expr -> CompileM BinOp
shiftRightOp expr = do
  ty <- promotedExprType expr
  pure (if isUnsignedType ty then IShr else ISar)

-- Pointer comparisons (including integer null constants on either side)
-- use pointer-width operands, not the integer usual arithmetic conversions.
-- Keep this separate from numeric operations and pointer offset lowering.
comparisonOperandType :: Expr -> Expr -> CompileM CType
comparisonOperandType a b = do
  aty <- exprType a
  bty <- exprType b
  case pointerElementType aty of
    Just inner -> pure (CPtr inner)
    Nothing -> case pointerElementType bty of
      Just inner -> pure (CPtr inner)
      Nothing -> arithmeticTypeFromOperands a aty b bty

comparisonOp :: String -> CType -> BinOp
comparisonOp op ty = case op of
  "!=" -> INe
  "<" -> if isUnsignedType ty then IULt else ILt
  "<=" -> if isUnsignedType ty then IULe else ILe
  ">" -> if isUnsignedType ty then IUGt else IGt
  ">=" -> if isUnsignedType ty then IUGe else IGe
  _ -> IEq

isUnsignedType :: CType -> Bool
isUnsignedType ty = case ty of
  CUnsigned -> True
  CUnsignedChar -> True
  CUnsignedShort -> True
  CUnsignedLong -> True
  CUnsignedLongLong -> True
  CBool -> True
  CPtr _ -> True
  CArray _ _ -> True
  CNamed name -> isNamedInteger name && not (isSignedNamedInteger name)
  _ -> False
