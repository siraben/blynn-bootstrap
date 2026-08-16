module Lower
  ( registerTypeAggregates
  , registerExternGlobals
  , registerFieldAggregates
  , lowerFunction
  , completeObjectType
  , globalData
  ) where

import Base
import TypesAst
import CompileM
import TypesIr
import LowerBuiltins
import LowerDataValues
import LowerImplicit
import Literal
import LowerLiterals
import LowerParams
import LowerSwitchHelpers
import TypesLower
import LowerTypeInfo

lowerFunction :: String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunction name params body =
  withErrorContext ("function " ++ name)
    (withFunctionScope (withCurrentFunction name (lowerFunctionBody name params body)))

lowerFunctionBody :: String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunctionBody name params body = do
  bid <- freshBlock
  retTy <- currentReturnType
  aggregateReturn <- maybe (pure False) isAggregateTypeM retTy
  if aggregateReturn
    then do
      retSlot <- freshTemp
      paramInstrs <- lowerParams 1 params
      defaultTerm <- defaultReturnTerm
      blocks <- withCurrentParamCount (length params + 1)
        (withCurrentReturnSlot (Just retSlot)
          (lowerStatementsFrom bid (IParam retSlot 0:paramInstrs) body defaultTerm))
      pure (FunctionIr name blocks)
    else do
      paramInstrs <- lowerParams 0 params
      defaultTerm <- defaultReturnTerm
      blocks <- withCurrentParamCount (length params)
        (lowerStatementsFrom bid paramInstrs body defaultTerm)
      pure (FunctionIr name blocks)

defaultReturnTerm :: CompileM Terminator
defaultReturnTerm = do
  mty <- currentReturnType
  case mty of
    Just CVoid -> pure (TRet Nothing)
    Just ty -> do
      aggregateReturn <- isAggregateTypeM ty
      pure (if aggregateReturn then TRet Nothing else TRet (Just (OImm 0)))
    Nothing -> pure (TRet (Just (OImm 0)))

coerceReturnOperand :: Maybe CType -> Operand -> CompileM ([Instr], Operand)
coerceReturnOperand sourceTy op = do
  mty <- currentReturnType
  case mty of
    Just CVoid -> pure ([], op)
    Just ty -> case sourceTy of
      Just source -> convertScalarValue source ty op
      Nothing -> coerceScalar ty op
    Nothing -> pure ([], op)

lowerStatementsFrom :: BlockId -> [Instr] -> [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerStatementsFrom bid instrs stmts defaultTerm = case stmts of
  [] -> pure [BasicBlock bid instrs defaultTerm]
  SReturn value:rest -> case value of
    Nothing -> do
      tailBlocks <- lowerUnreachableLabels rest defaultTerm
      pure (BasicBlock bid instrs (TRet Nothing) : tailBlocks)
    Just expr ->
      lowerReturnBlocks bid instrs expr rest defaultTerm
  SBlock body:rest -> do
    if null rest
      then withVarScope (lowerStatementsFrom bid instrs body defaultTerm)
      else do
        restId <- freshBlock
        bodyBlocks <- withVarScope (lowerStatementsFrom bid instrs body (TJump restId))
        restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
        pure (bodyBlocks ++ restBlocks)
  SDecl storage ty name initExpr:rest -> do
    declInstrs <- lowerStoredDecl storage ty name initExpr
    lowerStatementsFrom bid (instrs ++ declInstrs) rest defaultTerm
  SDecls storage decls:rest -> do
    declInstrs <- lowerStoredDecls storage decls
    lowerStatementsFrom bid (instrs ++ declInstrs) rest defaultTerm
  STypedef types:rest -> do
    registerTypesAggregates types
    lowerStatementsFrom bid instrs rest defaultTerm
  SExpr expr:rest -> do
    exprInstrs <- lowerSideEffect expr
    lowerStatementsFrom bid (instrs ++ exprInstrs) rest defaultTerm
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
    condBlocks <- lowerConditionBlock condId [] cond bodyId restId
    bodyBlocks <- withLoopTargets restId condId (lowerStatementsFrom bodyId [] body (TJump condId))
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure ( BasicBlock bid instrs (TJump bodyId)
         : bodyBlocks ++
           condBlocks ++ restBlocks)
  SFor initClause condExpr stepExpr body:rest -> do
    restId <- freshBlock
    loopBlocks <- case initClause of
      ForDecls _ _ -> withVarScope (lowerForLoop bid instrs initClause condExpr stepExpr body restId)
      _ -> lowerForLoop bid instrs initClause condExpr stepExpr body restId
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure (loopBlocks ++ restBlocks)
  SSwitch value body:rest -> do
    (valueInstrs, valueOp) <- lowerExpr value
    dispatchId <- freshBlock
    restId <- freshBlock
    switchBlocks <- lowerSwitch dispatchId restId valueOp body
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure (BasicBlock bid (instrs ++ valueInstrs) (TJump dispatchId) : switchBlocks ++ restBlocks)
  SCase expr:rest ->
    lowerSwitchLabelBlocks bid instrs (Just expr) rest defaultTerm
  SDefault:rest ->
    lowerSwitchLabelBlocks bid instrs Nothing rest defaultTerm
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
    (restId, restBlocks) <- lowerIfRestTarget rest defaultTerm
    let noTarget = if null no then restId else noId
    yesBlocks <- lowerStatementsFrom yesId [] yes (TJump restId)
    noBlocks <- lowerIfNoBlocks no noId restId
    condBlocks <- lowerConditionBlock bid instrs cond yesId noTarget
    pure (condBlocks ++ yesBlocks ++ noBlocks ++ restBlocks)
  SBreak:rest -> do
    target <- requireBreakTarget
    tailBlocks <- lowerUnreachableLabels rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : tailBlocks)
  SContinue:rest -> do
    target <- requireContinueTarget
    tailBlocks <- lowerUnreachableLabels rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : tailBlocks)

lowerSwitchLabelBlocks :: BlockId -> [Instr] -> Maybe Expr -> [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerSwitchLabelBlocks bid instrs label rest defaultTerm = do
  target <- nextSwitchCaseTarget label
  blocks <- lowerStatementsFrom target [] rest defaultTerm
  pure (BasicBlock bid instrs (TJump target) : blocks)

lowerReturnBlocks :: BlockId -> [Instr] -> Expr -> [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerReturnBlocks bid instrs expr rest defaultTerm = do
  mty <- currentReturnType
  aggregateReturn <- maybe (pure False) isAggregateTypeM mty
  if aggregateReturn
    then lowerAggregateReturnBlocks bid instrs expr rest defaultTerm
    else lowerScalarReturnBlocks bid instrs expr rest defaultTerm

lowerScalarReturnBlocks :: BlockId -> [Instr] -> Expr -> [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerScalarReturnBlocks bid instrs expr rest defaultTerm =
  if exprIsShortCircuitBoolean expr
    then do
      yesId <- freshBlock
      noId <- freshBlock
      condBlocks <- lowerConditionBlock bid instrs expr yesId noId
      (yesInstrs, yesOp) <- coerceReturnOperand (Just CInt) (OImm 1)
      (noInstrs, noOp) <- coerceReturnOperand (Just CInt) (OImm 0)
      tailBlocks <- lowerUnreachableLabels rest defaultTerm
      pure ( condBlocks ++
             [ BasicBlock yesId yesInstrs (TRet (Just yesOp))
             , BasicBlock noId noInstrs (TRet (Just noOp))
             ] ++ tailBlocks)
    else do
      (retInstrs, op) <- lowerExpr expr
      sourceTy <- exprType expr
      (coerceInstrs, retOp) <- coerceReturnOperand sourceTy op
      tailBlocks <- lowerUnreachableLabels rest defaultTerm
      pure (BasicBlock bid (instrs ++ retInstrs ++ coerceInstrs) (TRet (Just retOp)) : tailBlocks)

lowerAggregateReturnBlocks :: BlockId -> [Instr] -> Expr -> [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerAggregateReturnBlocks bid instrs expr rest defaultTerm = do
  slot <- currentReturnSlot
  retSlot <- requireReturnSlot slot
  mty <- currentReturnType
  retTy <- requireMaybeType "aggregate return has unknown type" mty
  (retInstrs, op) <- lowerExpr expr
  copyInstrs <- copyObject (OTemp retSlot) op retTy
  tailBlocks <- lowerUnreachableLabels rest defaultTerm
  pure (BasicBlock bid (instrs ++ retInstrs ++ copyInstrs) (TRet Nothing) : tailBlocks)

requireReturnSlot :: Maybe Temp -> CompileM Temp
requireReturnSlot slot = case slot of
  Just temp -> pure temp
  Nothing -> throwC "aggregate return slot is unavailable"

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
  ForDecls storage decls -> lowerStoredDecls storage decls

lowerIfRestTarget :: [Stmt] -> Terminator -> CompileM (BlockId, [BasicBlock])
lowerIfRestTarget rest defaultTerm = case rest of
  [] -> case defaultTerm of
    TJump target -> pure (target, [])
    _ -> lowerIfJoinTarget rest defaultTerm
  _ -> lowerIfJoinTarget rest defaultTerm

lowerIfJoinTarget :: [Stmt] -> Terminator -> CompileM (BlockId, [BasicBlock])
lowerIfJoinTarget rest defaultTerm = do
  joinId <- freshBlock
  blocks <- lowerStatementsFrom joinId [] rest defaultTerm
  pure (joinId, blocks)

lowerIfNoBlocks :: [Stmt] -> BlockId -> BlockId -> CompileM [BasicBlock]
lowerIfNoBlocks no noId restId = case no of
  [] -> pure []
  _ -> lowerStatementsFrom noId [] no (TJump restId)

lowerUnreachableLabels :: [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerUnreachableLabels stmts defaultTerm =
  if statementsContainLabel stmts
    then do
      unreachableId <- freshBlock
      lowerStatementsFrom unreachableId [] stmts defaultTerm
    else pure []

statementsContainLabel :: [Stmt] -> Bool
statementsContainLabel stmts = case stmts of
  [] -> False
  stmt:rest -> statementContainsLabel stmt || statementsContainLabel rest

statementContainsLabel :: Stmt -> Bool
statementContainsLabel stmt = case stmt of
  SLabel _ -> True
  SCase _ -> True
  SDefault -> True
  SBlock body -> statementsContainLabel body
  SWhile _ body -> statementsContainLabel body
  SDoWhile body _ -> statementsContainLabel body
  SFor _ _ _ body -> statementsContainLabel body
  SSwitch _ body -> statementsContainLabel body
  SIf _ yes no -> statementsContainLabel yes || statementsContainLabel no
  _ -> False

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
  EBinary op left right -> do
    leftTy <- exprType left
    rightTy <- exprType right
    softFloatRuntime <- useSoftFloatRuntime
    let floating = softFloatRuntime &&
          (maybe False isFloatingType leftTy || maybe False isFloatingType rightTy)
    if isBranchComparisonOpString op && not floating
      then do
        (condInstrs, iop, leftOp, rightOp) <- lowerBranchComparison op left right
        pure [BasicBlock bid (instrs ++ condInstrs) (TBranchCmp iop leftOp rightOp trueId falseId)]
      else lowerValueConditionBlock bid instrs cond trueId falseId
  _ ->
    lowerValueConditionBlock bid instrs cond trueId falseId

lowerValueConditionBlock :: BlockId -> [Instr] -> Expr -> BlockId -> BlockId -> CompileM [BasicBlock]
lowerValueConditionBlock bid instrs cond trueId falseId = do
  (condInstrs, condOp) <- lowerTruthExpr cond
  pure [BasicBlock bid (instrs ++ condInstrs) (TBranch condOp trueId falseId)]

isBranchComparisonOpString :: String -> Bool
isBranchComparisonOpString op =
  op `elem` ["==", "!=", "<", "<=", ">", ">="]

lowerBranchComparison :: String -> Expr -> Expr -> CompileM ([Instr], BinOp, Operand, Operand)
lowerBranchComparison op a b = do
  (instrs, ao, bo) <- lowerComparisonOperands a b
  iop <- if op == "==" then pure IEq else if op == "!=" then pure INe else comparisonOp op a b
  pure (instrs, iop, ao, bo)

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

lowerSwitch :: BlockId -> BlockId -> Operand -> [Stmt] -> CompileM [BasicBlock]
lowerSwitch dispatchId restId valueOp body = do
  let bodyStmts = switchBodyStatements body
  let labels = collectSwitchLabels bodyStmts
  caseIds <- freshBlocks (length labels)
  let caseTargets = zip labels caseIds
  let defaultTarget = switchDefaultTarget restId caseTargets
  let switchCasePairs = switchCases caseTargets
  bodyBlocks <- case bodyStmts of
    [] -> pure []
    _ -> do
      bodyId <- freshBlock
      withBreakTarget restId
        (withSwitchCaseTargets caseIds
          (lowerStatementsFrom bodyId [] bodyStmts (TJump restId)))
  dispatchBlocks <- lowerSwitchDispatch dispatchId valueOp defaultTarget switchCasePairs
  pure (dispatchBlocks ++ bodyBlocks)

lowerSwitchDispatch :: BlockId -> Operand -> BlockId -> [(Expr, BlockId)] -> CompileM [BasicBlock]
lowerSwitchDispatch bid valueOp defaultTarget switchCasePairs = case switchCasePairs of
  [] -> pure [BasicBlock bid [] (TJump defaultTarget)]
  (caseExpr, target):tailCases -> do
    nextId <- case tailCases of
      [] -> pure defaultTarget
      _ -> freshBlock
    (caseInstrs, caseOp) <- lowerExpr caseExpr
    let block = BasicBlock bid caseInstrs (TBranchCmp IEq valueOp caseOp target nextId)
    case tailCases of
      [] -> pure [block]
      _ -> do
        restBlocks <- lowerSwitchDispatch nextId valueOp defaultTarget tailCases
        pure (block:restBlocks)

lowerSideEffect :: Expr -> CompileM [Instr]
lowerSideEffect expr = case expr of
  ECall (EVar "__builtin_va_start") args ->
    lowerVaStart args
  ECall (EVar "__builtin_va_end") _ ->
    pure []
  ECall (EVar "__builtin_va_copy") args ->
    lowerVaCopy args
  ECall (EVar "asm") args ->
    if noOpInlineAsmArgs args
      then pure []
      else throwC "unsupported inline assembly"
  ECall (EUnary "*" (EVar name)) args ->
    if isIgnoredSideEffectCall name
      then pure []
      else do
        direct <- lookupFunction name
        if direct
          then lowerDirectSideEffect name args
          else lowerIndirectSideEffect (EUnary "*" (EVar name)) args
  ECall (EVar name) args ->
    if isIgnoredSideEffectCall name
      then pure []
      else do
        direct <- lookupFunction name
        if direct
          then lowerDirectSideEffect name args
          else lowerIndirectSideEffect (EVar name) args
  ECall callee args ->
    lowerIndirectSideEffect callee args
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
  [EString text] -> stringBytes text == [110, 111, 112, 0]
  _ -> False

lowerResultInstrs :: CompileM ([Instr], Operand) -> CompileM [Instr]
lowerResultInstrs action = do
  (instrs, _) <- action
  pure instrs

lowerIncDecSideEffect :: BinOp -> Expr -> CompileM [Instr]
lowerIncDecSideEffect op target =
  lowerResultInstrs (lowerIncDec True op target)

lowerDirectSideEffect :: String -> [Expr] -> CompileM [Instr]
lowerDirectSideEffect name args = do
  paramTys <- directCallParamTypes name
  lowered <- lowerCallArgs paramTys args
  retTy <- directCallReturnType name
  lowerDirectCallInstrs Nothing name retTy lowered

lowerIndirectSideEffect :: Expr -> [Expr] -> CompileM [Instr]
lowerIndirectSideEffect callee args = do
  (calleeInstrs, calleeOp) <- lowerCallDesignator callee
  paramTys <- indirectCallParamTypes callee
  lowered <- lowerCallArgs paramTys args
  retTy <- indirectCallReturnType callee
  callInstrs <- lowerIndirectCallInstrs Nothing calleeOp retTy lowered
  pure (calleeInstrs ++ callInstrs)

lowerExprResultsInstrs :: [([Instr], Operand)] -> [Instr]
lowerExprResultsInstrs = concatMap fst

lowerExprResultsOps :: [([Instr], Operand)] -> [Operand]
lowerExprResultsOps = map snd

lowerStoredDecls :: LocalStorage -> [(CType, String, Maybe Expr)] -> CompileM [Instr]
lowerStoredDecls storage decls = do
  lowered <- mapM (\(ty, name, initExpr) -> lowerStoredDecl storage ty name initExpr) decls
  pure (concat lowered)

lowerStoredDecl :: LocalStorage -> CType -> String -> Maybe Expr -> CompileM [Instr]
lowerStoredDecl storage ty name initExpr = case storage of
  AutomaticStorage -> lowerDecl ty name initExpr
  StaticStorage -> lowerStaticDecl ty name initExpr
  ExternalStorage -> lowerExternalDecl ty name initExpr

lowerStaticDecl :: CType -> String -> Maybe Expr -> CompileM [Instr]
lowerStaticDecl declaredTy name initExpr = do
  let ty = completeObjectType declaredTy initExpr
  label <- freshDataLabel
  bindStaticLocal name label ty
  values <- globalData ty initExpr
  addDataItem (DataItem label values)
  pure []

lowerExternalDecl :: CType -> String -> Maybe Expr -> CompileM [Instr]
lowerExternalDecl ty name initExpr = case initExpr of
  Nothing -> bindGlobal name ty >> pure []
  Just _ -> throwC ("block-scope extern " ++ name ++ " cannot have an initializer")

lowerDecl :: CType -> String -> Maybe Expr -> CompileM [Instr]
lowerDecl declaredTy name initExpr = do
  let ty = completeObjectType declaredTy initExpr
  registerTypeAggregates ty
  aggregateStorage <- isAggregateTypeM ty
  temp <- freshTemp
  bindVar name temp ty
  if aggregateStorage
    then lowerAggregateDecl ty temp initExpr
    else lowerScalarDecl ty temp initExpr

completeObjectType :: CType -> Maybe Expr -> CType
completeObjectType ty initExpr = case (ty, initExpr) of
  (CArray inner Nothing, Just (EInitList exprs)) ->
    CArray inner (Just (EInt (show (length exprs))))
  (CArray CChar Nothing, Just (EString text)) ->
    CArray CChar (Just (EInt (show (length (stringBytes text)))))
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
    sourceTy <- exprType expr
    (coerceInstrs, coerceOp) <- case sourceTy of
      Just source -> convertScalarValue source ty op
      Nothing -> coerceScalar ty op
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

staticInitializerExpr :: Expr -> Bool
staticInitializerExpr expr = case expr of
  EInitList exprs -> allStaticInitializerExprs exprs
  EString _ -> True
  EInt _ -> True
  EChar _ -> True
  ECast _ value -> staticInitializerExpr value
  EUnary "-" value -> staticInitializerExpr value
  EUnary "+" value -> staticInitializerExpr value
  EUnary "~" value -> staticInitializerExpr value
  EUnary "!" value -> staticInitializerExpr value
  EUnary "&" _ -> True
  EVar _ -> True
  EBinary op left right ->
    op /= "," && staticInitializerExpr left && staticInitializerExpr right
  ECond cond yes no ->
    staticInitializerExpr cond && staticInitializerExpr yes && staticInitializerExpr no
  _ -> False

allStaticInitializerExprs :: [Expr] -> Bool
allStaticInitializerExprs exprs = case exprs of
  [] -> True
  expr:rest -> staticInitializerExpr expr && allStaticInitializerExprs rest

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
  CArray inner _ -> lowerArrayInitWrites dst inner 0 exprs
  _ -> do
    aggregate <- aggregateFields ty
    case aggregate of
      Just aggregateInfo -> case aggregateInfo of
        (False, fields) -> lowerStructInitWrites dst 0 fields exprs
        (True, fields) -> lowerUnionInitWrites dst fields exprs
      _ -> pure []

lowerUnionInitWrites :: Operand -> [Field] -> [Expr] -> CompileM [Instr]
lowerUnionInitWrites dst fields exprs = do
  layouts <- aggregateFieldLayouts True fields
  lowerUnionLayoutInitWrites dst layouts exprs

lowerUnionLayoutInitWrites :: Operand -> [FieldLayout] -> [Expr] -> CompileM [Instr]
lowerUnionLayoutInitWrites dst layouts exprs = case layouts of
  [] -> pure []
  FieldLayout fieldTy name offset bitRange:rest ->
    if name == "" && hasBitRange bitRange
      then lowerUnionLayoutInitWrites dst rest exprs
      else case exprs of
        expr:_ -> lowerFieldLayoutWrite dst fieldTy offset bitRange expr
        [] -> pure []

lowerArrayInitWrites :: Operand -> CType -> Int -> [Expr] -> CompileM [Instr]
lowerArrayInitWrites dst inner index exprs = case exprs of
  [] -> pure []
  expr:rest -> do
    elemSize <- typeSize inner
    current <- lowerAggregateElementWrite dst (index * elemSize) inner expr
    tailInstrs <- lowerArrayInitWrites dst inner (index + 1) rest
    pure (current ++ tailInstrs)

lowerStructInitWrites :: Operand -> Int -> [Field] -> [Expr] -> CompileM [Instr]
lowerStructInitWrites dst _ fields exprs = do
  layouts <- aggregateFieldLayouts False fields
  lowerStructLayoutInitWrites dst layouts exprs

lowerStructLayoutInitWrites :: Operand -> [FieldLayout] -> [Expr] -> CompileM [Instr]
lowerStructLayoutInitWrites dst layouts exprs = case layouts of
  [] -> pure []
  FieldLayout fieldTy name offset bitRange:rest ->
    if name == "" && hasBitRange bitRange
      then lowerStructLayoutInitWrites dst rest exprs
      else case exprs of
        [] -> pure []
        expr:exprRest -> do
          current <- lowerFieldLayoutWrite dst fieldTy offset bitRange expr
          tailInstrs <- lowerStructLayoutInitWrites dst rest exprRest
          pure (current ++ tailInstrs)

hasBitRange :: Maybe (Int, Int) -> Bool
hasBitRange bitRange = case bitRange of
  Just _ -> True
  Nothing -> False

lowerFieldLayoutWrite :: Operand -> CType -> Int -> Maybe (Int, Int) -> Expr -> CompileM [Instr]
lowerFieldLayoutWrite dst fieldTy offset bitRange expr = case bitRange of
  Nothing -> lowerAggregateElementWrite dst offset fieldTy expr
  Just (bitOffset, width) -> do
    (addrInstrs, addr) <- offsetAddress dst offset
    (exprInstrs, value) <- lowerExpr expr
    sourceTy <- exprType expr
    (coerceInstrs, coerced) <- case sourceTy of
      Just source -> convertScalarValue source fieldTy value
      Nothing -> coerceScalar fieldTy value
    writeInstrs <- writeBitField addr fieldTy bitOffset width coerced
    pure (addrInstrs ++ exprInstrs ++ coerceInstrs ++ writeInstrs)

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
  _ -> do
    (exprInstrs, op) <- lowerExpr expr
    copyInstrs <- copyObject addr op fieldTy
    pure (exprInstrs ++ copyInstrs)

lowerAggregateElementScalarWrite :: Operand -> CType -> Expr -> CompileM [Instr]
lowerAggregateElementScalarWrite addr fieldTy expr = do
  (exprInstrs, op) <- lowerExpr expr
  sourceTy <- exprType expr
  (coerceInstrs, coerceOp) <- case sourceTy of
    Just source -> convertScalarValue source fieldTy op
    Nothing -> coerceScalar fieldTy op
  store <- storeInstr fieldTy addr coerceOp
  pure (exprInstrs ++ coerceInstrs ++ [store])

registerExternGlobals :: [(CType, String)] -> CompileM ()
registerExternGlobals = mapM_ $ \(ty, name) -> do
    registerTypeAggregates ty
    bindGlobal name ty

registerConstants :: [(String, Int)] -> CompileM ()
registerConstants = mapM_ (uncurry bindConstant)

registerFieldAggregates :: [Field] -> CompileM ()
registerFieldAggregates = mapM_ $ \(Field ty _ _) -> registerTypeAggregates ty

registerTypeAggregates :: CType -> CompileM ()
registerTypeAggregates ty = case ty of
  CPtr inner -> registerTypeAggregates inner
  CArray inner _ -> registerTypeAggregates inner
  CFunc ret params -> do
    registerTypeAggregates ret
    mapM_ registerTypeAggregates params
  CStructNamed name fields -> do
    registerFieldAggregates fields
    bindStruct name False fields
  CUnionNamed name fields -> do
    registerFieldAggregates fields
    bindStruct name True fields
  CStructDef fields ->
    registerFieldAggregates fields
  CUnionDef fields ->
    registerFieldAggregates fields
  CEnum _ constants ->
    registerConstants constants
  _ -> pure ()

registerTypesAggregates :: [CType] -> CompileM ()
registerTypesAggregates = mapM_ registerTypeAggregates

lowerCastExpr :: CType -> Expr -> CompileM ([Instr], Operand)
lowerCastExpr ty value = do
  aggregate <- aggregateFields ty
  case aggregate of
    Just (True, _) -> lowerUnionCast ty value
    _ -> do
      (instrs, op) <- lowerExpr value
      sourceTy <- exprType value
      (coerceInstrs, coerceOp) <- case sourceTy of
        Just source -> convertScalarValue source ty op
        Nothing -> coerceScalar ty op
      pure (instrs ++ coerceInstrs, coerceOp)

-- GNU C defines a cast to a union when the source type is compatible with a
-- union member.  Every union member starts at offset zero, so materializing
-- the source value in union-sized local storage preserves the representation
-- without depending on a particular member name.
lowerUnionCast :: CType -> Expr -> CompileM ([Instr], Operand)
lowerUnionCast ty value = do
  sourceTy <- exprType value >>= requireMaybeType "union cast source has unknown type"
  (valueInstrs, valueOp) <- lowerExpr value
  temp <- freshTemp
  size <- typeSize ty
  sourceAggregate <- isAggregateTypeM sourceTy
  writeInstrs <- if sourceAggregate
    then copyObject (OTemp temp) valueOp sourceTy
    else do
      store <- storeInstr sourceTy (OTemp temp) valueOp
      pure [store]
  pure (IAlloca temp size : valueInstrs ++ writeInstrs, OTemp temp)

lowerExpr :: Expr -> CompileM ([Instr], Operand)
lowerExpr expr = case expr of
  EInt text ->
    pure ([], intConstOperand text)
  EFloat text ->
    do
      softFloatRuntime <- useSoftFloatRuntime
      if softFloatRuntime
        then lowerFloatingLiteral text
        else pure ([], OImmBytes (floatLiteralBytes (floatLiteralSize text) text))
  EChar text ->
    pure ([], OImm (charValue text))
  EString text -> do
    dataLabel <- freshDataLabel
    addDataItem (DataItem dataLabel (map DByte (stringBytes text)))
    pure ([], OGlobal dataLabel)
  EVar name -> lowerVarExpr name
  EUnary "+" x -> lowerExpr x
  EUnary "-" x -> do
    (a, op) <- lowerExpr x
    mty <- exprType x
    softFloatRuntime <- useSoftFloatRuntime
    case mty of
      Just ty | softFloatRuntime && isFloatingType ty -> do
        (negInstrs, negOp) <- lowerFloatingUnary "neg" ty op
        pure (a ++ negInstrs, negOp)
      _ -> do
        zero <- freshTemp
        out <- freshTemp
        pure (a ++ [IConst zero 0, IBin out ISub (OTemp zero) op], OTemp out)
  EUnary "!" x -> do
    (a, truth) <- lowerTruthExpr x
    out <- freshTemp
    pure (a ++ [IBin out IEq truth (OImm 0)], OTemp out)
  EUnary "~" x -> do
    (a, op) <- lowerExpr x
    zero <- freshTemp
    neg <- freshTemp
    out <- freshTemp
    pure (a ++ [IConst zero 0, IBin neg ISub (OTemp zero) op, IBin out ISub (OTemp neg) (OImm 1)], OTemp out)
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
  ECast ty x ->
    lowerCastExpr ty x
  ESizeofType ty -> do
    size <- typeSize ty
    temp <- freshTemp
    pure ([IConst temp size], OTemp temp)
  ESizeofExpr value -> do
    size <- sizeofExprValue value
    temp <- freshTemp
    pure ([IConst temp size], OTemp temp)
  EAlignofType ty -> do
    align <- typeAlign ty
    temp <- freshTemp
    pure ([IConst temp align], OTemp temp)
  EAlignofExpr value -> do
    align <- alignofExprValue value
    temp <- freshTemp
    pure ([IConst temp align], OTemp temp)
  EVaArg list ty ->
    lowerVaArg list ty
  EStmtExpr body ->
    lowerStmtExpr body
  ECond cond yes no -> do
    (ci, co) <- lowerTruthExpr cond
    (yi, yo) <- lowerExpr yes
    (ni, noOp) <- lowerExpr no
    resultTy <- exprType expr
    yesTy <- exprType yes
    noTy <- exprType no
    (yesCoerceInstrs, yesOp) <- convertMaybeScalarValue yesTy resultTy yo
    (noCoerceInstrs, convertedNoOp) <- convertMaybeScalarValue noTy resultTy noOp
    out <- freshTemp
    pure ([ICond out ci co (yi ++ yesCoerceInstrs) yesOp
                         (ni ++ noCoerceInstrs) convertedNoOp], OTemp out)
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
  ECall (EVar "__builtin_expect") args -> case args of
    value:_ -> lowerExpr value
    _ -> throwC "__builtin_expect requires an expression"
  ECall (EVar "__builtin_constant_p") _ ->
    pure ([], OImm 0)
  ECall (EVar "__builtin_va_start") args -> do
    instrs <- lowerVaStart args
    pure (instrs, OImm 0)
  ECall (EVar "__builtin_va_end") _ ->
    pure ([], OImm 0)
  ECall (EVar "__builtin_va_copy") args -> do
    instrs <- lowerVaCopy args
    pure (instrs, OImm 0)
  ECall (EUnary "*" (EVar name)) args -> do
    direct <- lookupFunction name
    if direct
      then lowerDirectCallExpr name args
      else lowerIndirectCall (EUnary "*" (EVar name)) args
  ECall (EVar name) args -> do
    direct <- lookupFunction name
    if direct
      then lowerDirectCallExpr name args
      else lowerIndirectCall (EVar name) args
  ECall callee args -> do
    lowerIndirectCall callee args
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
lowerVarExpr name =
  if isFunctionNameMacro name
    then lowerFunctionNameMacro
    else if name == "__FILE__"
      then lowerExpr (EString "")
    else case builtinConstant name of
      Just value -> pure ([], OImm value)
      Nothing -> lowerNonBuiltinVarExpr name

lowerFunctionNameMacro :: CompileM ([Instr], Operand)
lowerFunctionNameMacro = do
  mname <- currentFunctionName
  case mname of
    Just name -> lowerExpr (EString name)
    Nothing -> pure ([], OImm 0)

lowerNonBuiltinVarExpr :: String -> CompileM ([Instr], Operand)
lowerNonBuiltinVarExpr name = do
  local <- lookupVarMaybe name
  case local of
    Just temp -> do
      mty <- lookupVarType name
      ty <- requireMaybeType ("unknown local type: " ++ name) mty
      coerceScalar ty (OTemp temp)
    Nothing -> lowerNonLocalOrConstantVarExpr name

lowerNonLocalOrConstantVarExpr :: String -> CompileM ([Instr], Operand)
lowerNonLocalOrConstantVarExpr name = do
  constant <- lookupConstant name
  case constant of
    Just value -> pure ([], OImm value)
    Nothing -> lowerNonLocalVarExpr name

lowerNonLocalVarExpr :: String -> CompileM ([Instr], Operand)
lowerNonLocalVarExpr name = do
  function <- lookupFunction name
  if function
    then do
      resolved <- resolveSymbolName name
      pure ([], OFunction resolved)
    else lowerGlobalVarExpr name

lowerGlobalVarExpr :: String -> CompileM ([Instr], Operand)
lowerGlobalVarExpr name = do
  globalTy <- lookupGlobalType name
  case globalTy of
    Just ty -> lowerTypedGlobalVarExpr name ty
    Nothing -> throwC ("unknown identifier: " ++ name)

lowerTypedGlobalVarExpr :: String -> CType -> CompileM ([Instr], Operand)
lowerTypedGlobalVarExpr name ty = do
  resolved <- resolveSymbolName name
  case ty of
    CArray _ _ -> pure ([], OGlobal resolved)
    _ -> do
      aggregateStorage <- isAggregateTypeM ty
      if aggregateStorage
        then pure ([], OGlobal resolved)
        else do
          out <- freshTemp
          load <- loadInstr out ty (OGlobal resolved)
          pure ([load], OTemp out)

lowerBinaryExpr :: String -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerBinaryExpr op a b = do
  aty <- exprType a
  bty <- exprType b
  softFloatRuntime <- useSoftFloatRuntime
  if softFloatRuntime &&
       (maybe False isFloatingType aty || maybe False isFloatingType bty)
    then lowerFloatingBinary op a b
    else lowerNonFloatingBinary op a b

lowerNonFloatingBinary :: String -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerNonFloatingBinary op a b
  | isComparisonOpString op = lowerComparisonExpr op a b
  | op == "/" || op == "%" = do
      commonTy <- usualArithmeticType a b
      let iop
            | isUnsignedType commonTy = if op == "/" then IUDiv else IUMod
            | op == "/" = IDiv
            | otherwise = IMod
      lowerPlainBin iop a b
  | otherwise = case lowerBinOp op of
      Just iop ->
        if op == "<<"
          then lowerShiftExpr op a b
          else lowerPlainBin iop a b
      Nothing -> throwC ("unsupported binary operator in lowering: " ++ op)

lowerFloatingBinary :: String -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerFloatingBinary op a b = do
  commonTy <- usualArithmeticType a b
  aty <- exprType a >>= requireMaybeType "floating left operand has unknown type"
  bty <- exprType b >>= requireMaybeType "floating right operand has unknown type"
  (ai, ao) <- lowerExpr a
  (bi, bo) <- lowerExpr b
  (acoerceInstrs, acoerceOp) <- convertScalarValue aty commonTy ao
  (bcoerceInstrs, bcoerceOp) <- convertScalarValue bty commonTy bo
  helperOp <- floatingBinaryHelper op
  (callInstrs, resultOp) <- lowerFloatingRuntimeCall
    (floatingRuntimePrefix commonTy ++ helperOp) [acoerceOp, bcoerceOp]
  pure (ai ++ bi ++ acoerceInstrs ++ bcoerceInstrs ++ callInstrs, resultOp)

floatingBinaryHelper :: String -> CompileM String
floatingBinaryHelper op = case op of
  "+" -> pure "_add"
  "-" -> pure "_sub"
  "*" -> pure "_mul"
  "/" -> pure "_div"
  "==" -> pure "_eq"
  "!=" -> pure "_ne"
  "<" -> pure "_lt"
  "<=" -> pure "_le"
  ">" -> pure "_gt"
  ">=" -> pure "_ge"
  _ -> throwC ("unsupported floating binary operator: " ++ op)

isComparisonOpString :: String -> Bool
isComparisonOpString op =
  op `elem` ["<", "<=", ">", ">="]

lowerComparisonExpr :: String -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerComparisonExpr op a b = do
  (instrs, ao, bo) <- lowerComparisonOperands a b
  out <- freshTemp
  iop <- comparisonOp op a b
  pure (instrs ++ [IBin out iop ao bo], OTemp out)

lowerComparisonOperands :: Expr -> Expr -> CompileM ([Instr], Operand, Operand)
lowerComparisonOperands a b = do
  (ai, ao) <- lowerExpr a
  (bi, bo) <- lowerExpr b
  commonTy <- usualArithmeticType a b
  (acoerceInstrs, acoerceOp) <- coerceBinOperand commonTy a ao
  (bcoerceInstrs, bcoerceOp) <- coerceBinOperand commonTy b bo
  pure (ai ++ bi ++ acoerceInstrs ++ bcoerceInstrs, acoerceOp, bcoerceOp)

lowerDirectCallExpr :: String -> [Expr] -> CompileM ([Instr], Operand)
lowerDirectCallExpr name args = do
  paramTys <- directCallParamTypes name
  lowered <- lowerCallArgs paramTys args
  retTy <- directCallReturnType name
  aggregate <- maybe (pure False) isAggregateTypeM retTy
  if aggregate
    then do
      ty <- requireMaybeType ("unknown aggregate return type for " ++ name) retTy
      lowerAggregateDirectCall name ty lowered
    else do
      out <- freshTemp
      instrs <- lowerDirectCallInstrs (Just out) name retTy lowered
      pure (instrs, OTemp out)

lowerCallArgs :: Maybe [CType] -> [Expr] -> CompileM [([Instr], Operand)]
lowerCallArgs mParamTys args = case (mParamTys, args) of
  (_, []) -> pure []
  (Just (paramTy:restTys), arg:restArgs) -> do
    lowered <- lowerCallArg (Just paramTy) arg
    rest <- lowerCallArgs (Just restTys) restArgs
    pure (lowered:rest)
  (_, arg:restArgs) -> do
    lowered <- lowerCallArg Nothing arg
    rest <- lowerCallArgs Nothing restArgs
    pure (lowered:rest)

-- HCC's internal aggregate convention passes an address, but C parameters
-- still have value semantics.  Give every aggregate argument its own object
-- so mutation in the callee cannot alias the caller's object.  This also
-- covers calls without a prototype by falling back to the expression type.
lowerCallArg :: Maybe CType -> Expr -> CompileM ([Instr], Operand)
lowerCallArg mParamTy arg = do
  (instrs, op) <- lowerExpr arg
  sourceTy <- exprType arg
  aggregateTy <- case mParamTy of
    Just ty -> pure (Just ty)
    Nothing -> pure sourceTy
  aggregate <- maybe (pure False) isRecordTypeM aggregateTy
  if aggregate
    then do
      ty <- requireMaybeType "aggregate argument has unknown type" aggregateTy
      temp <- freshTemp
      size <- typeSize ty
      copyInstrs <- copyObject (OTemp temp) op ty
      pure (IAlloca temp size : instrs ++ copyInstrs, OTemp temp)
    else case (sourceTy, mParamTy) of
      (Just source, Just target) -> do
        (coerceInstrs, coerced) <- convertScalarValue source target op
        pure (instrs ++ coerceInstrs, coerced)
      _ -> pure (instrs, op)

lowerIndirectCall :: Expr -> [Expr] -> CompileM ([Instr], Operand)
lowerIndirectCall callee args = do
  (calleeInstrs, calleeOp) <- lowerCallDesignator callee
  paramTys <- indirectCallParamTypes callee
  lowered <- lowerCallArgs paramTys args
  retTy <- indirectCallReturnType callee
  aggregate <- maybe (pure False) isAggregateTypeM retTy
  if aggregate
    then do
      ty <- requireMaybeType "unknown aggregate return type for indirect call" retTy
      (callInstrs, op) <- lowerAggregateIndirectCall calleeOp ty lowered
      pure (calleeInstrs ++ callInstrs, op)
    else do
      out <- freshTemp
      callInstrs <- lowerIndirectCallInstrs (Just out) calleeOp retTy lowered
      pure (calleeInstrs ++ callInstrs, OTemp out)

-- Applying unary * to a pointer-to-function produces a function designator;
-- the call operator converts that designator back to the same function
-- pointer.  Avoid treating the * as an ordinary object load.  This also
-- handles redundant forms such as (**callback)().
lowerCallDesignator :: Expr -> CompileM ([Instr], Operand)
lowerCallDesignator callee = case callee of
  EUnary "*" value -> do
    mty <- exprType callee
    case mty of
      Just (CFunc _ _) -> lowerCallDesignator value
      _ -> lowerExpr callee
  _ -> lowerExpr callee

directCallReturnType :: String -> CompileM (Maybe CType)
directCallReturnType name = do
  functionTy <- lookupFunctionType name
  case functionResultType =<< functionTy of
    Just ty -> pure (Just ty)
    Nothing -> do
      globalTy <- lookupGlobalType name
      pure (functionResultType =<< globalTy)

directCallParamTypes :: String -> CompileM (Maybe [CType])
directCallParamTypes name = do
  functionTy <- lookupFunctionType name
  case functionParamTypes =<< functionTy of
    Just tys -> pure (Just tys)
    Nothing -> do
      globalTy <- lookupGlobalType name
      pure (functionParamTypes =<< globalTy)

indirectCallReturnType :: Expr -> CompileM (Maybe CType)
indirectCallReturnType callee = do
  calleeTy <- exprType callee
  pure (functionResultType =<< calleeTy)

indirectCallParamTypes :: Expr -> CompileM (Maybe [CType])
indirectCallParamTypes callee = do
  calleeTy <- exprType callee
  pure (functionParamTypes =<< calleeTy)

lowerDirectCallInstrs :: Maybe Temp -> String -> Maybe CType -> [([Instr], Operand)] -> CompileM [Instr]
lowerDirectCallInstrs result name retTy lowered = do
  resolved <- resolveSymbolName name
  aggregate <- maybe (pure False) isAggregateTypeM retTy
  if aggregate
    then do
      ty <- requireMaybeType ("unknown aggregate return type for " ++ name) retTy
      temp <- freshTemp
      size <- typeSize ty
      let ops = OTemp temp : lowerExprResultsOps lowered
      pure (IAlloca temp size : lowerExprResultsInstrs lowered ++ [ICall Nothing resolved ops])
    else pure (lowerExprResultsInstrs lowered ++ [ICall result resolved (lowerExprResultsOps lowered)])

lowerIndirectCallInstrs :: Maybe Temp -> Operand -> Maybe CType -> [([Instr], Operand)] -> CompileM [Instr]
lowerIndirectCallInstrs result calleeOp retTy lowered = do
  aggregate <- maybe (pure False) isAggregateTypeM retTy
  if aggregate
    then do
      ty <- requireMaybeType "unknown aggregate return type for indirect call" retTy
      temp <- freshTemp
      size <- typeSize ty
      let ops = OTemp temp : lowerExprResultsOps lowered
      pure (IAlloca temp size : lowerExprResultsInstrs lowered ++ [ICallIndirect Nothing calleeOp ops])
    else pure (lowerExprResultsInstrs lowered ++ [ICallIndirect result calleeOp (lowerExprResultsOps lowered)])

lowerAggregateDirectCall :: String -> CType -> [([Instr], Operand)] -> CompileM ([Instr], Operand)
lowerAggregateDirectCall name ty lowered = do
  resolved <- resolveSymbolName name
  temp <- freshTemp
  size <- typeSize ty
  let ops = OTemp temp : lowerExprResultsOps lowered
  pure (IAlloca temp size : lowerExprResultsInstrs lowered ++ [ICall Nothing resolved ops], OTemp temp)

lowerAggregateIndirectCall :: Operand -> CType -> [([Instr], Operand)] -> CompileM ([Instr], Operand)
lowerAggregateIndirectCall calleeOp ty lowered = do
  temp <- freshTemp
  size <- typeSize ty
  let ops = OTemp temp : lowerExprResultsOps lowered
  pure (IAlloca temp size : lowerExprResultsInstrs lowered ++ [ICallIndirect Nothing calleeOp ops], OTemp temp)

lowerVaArg :: Expr -> CType -> CompileM ([Instr], Operand)
lowerVaArg list ty = do
  listTy <- exprType list
  sysv <- maybe (pure False) isSysvVaListType listTy
  if sysv
    then lowerSysvVaArg list ty
    else lowerPointerVaArg list ty

lowerPointerVaArg :: Expr -> CType -> CompileM ([Instr], Operand)
lowerPointerVaArg list ty = do
  (listInstrs, listLValue) <- lowerLValue list
  (readInstrs, currentOp) <- readLValue listLValue
  regEnd <- freshTemp
  overflow <- freshTemp
  isEnd <- freshTemp
  current <- freshTemp
  value <- lowerVaValue ty (OTemp current)
  step <- vaArgSlotSize ty
  next <- freshTemp
  writeInstrs <- writeLValue listLValue (OTemp next)
  case value of
    (valueInstrs, valueOp) ->
      pure ( listInstrs ++ readInstrs ++
             [ IVaEnd regEnd
             , IVaOverflow overflow
             , ICond current
                 [IBin isEnd IEq currentOp (OTemp regEnd)] (OTemp isEnd)
                 [] (OTemp overflow)
                 [] currentOp
             ] ++ valueInstrs ++
             [IBin next IAdd (OTemp current) (OImm step)] ++ writeInstrs
           , valueOp)

lowerVaStart :: [Expr] -> CompileM [Instr]
lowerVaStart args = case args of
  list:_ -> do
    count <- currentParamCount
    fixed <- case count of
      Just value -> pure value
      Nothing -> throwC "__builtin_va_start outside a function"
    listTy <- exprType list
    sysv <- maybe (pure False) isSysvVaListType listTy
    if sysv
      then lowerSysvVaStart list fixed
      else do
        (listInstrs, listLValue) <- lowerLValue list
        start <- freshTemp
        writeInstrs <- writeLValue listLValue (OTemp start)
        pure (listInstrs ++ IVaStart start fixed : writeInstrs)
  _ -> throwC "__builtin_va_start requires a va_list and final named parameter"

lowerVaCopy :: [Expr] -> CompileM [Instr]
lowerVaCopy args = case args of
  [dest, source] -> do
    destTy <- exprType dest
    case destTy of
      Just (CArray elemTy _) -> do
        (destInstrs, destOp) <- lowerExpr dest
        (sourceInstrs, sourceOp) <- lowerExpr source
        copyInstrs <- copyObject destOp sourceOp elemTy
        pure (destInstrs ++ sourceInstrs ++ copyInstrs)
      _ -> do
        (destInstrs, destLValue) <- lowerLValue dest
        (sourceInstrs, sourceOp) <- lowerExpr source
        writeInstrs <- writeLValue destLValue sourceOp
        pure (destInstrs ++ sourceInstrs ++ writeInstrs)
  _ -> throwC "__builtin_va_copy requires two va_list arguments"

-- On SysV targets va_list is an array of one four-field state structure.
-- C adjusts an array parameter to a pointer, so checking only for CArray
-- misclassifies a va_list forwarded to a helper as HCC's legacy pointer-style
-- list.  Recognize the ABI structure itself so local arrays and adjusted
-- parameters follow the same lowering without depending on a typedef or tag
-- spelling.
isSysvVaListType :: CType -> CompileM Bool
isSysvVaListType ty = case ty of
  CArray elemTy _ -> isSysvVaStateType elemTy
  CPtr elemTy -> isSysvVaStateType elemTy
  _ -> pure False

isSysvVaStateType :: CType -> CompileM Bool
isSysvVaStateType ty = do
  aggregate <- aggregateFields ty
  pure (case aggregate of
    Just (False,
      [ Field CUnsigned "gp_offset" Nothing
      , Field CUnsigned "fp_offset" Nothing
      , Field (CPtr _) "overflow_arg_area" Nothing
      , Field (CPtr _) "reg_save_area" Nothing
      ]) -> True
    _ -> False)

-- The faithful amd64 bootstrap header uses the native SysV va_list layout so
-- a list can cross from HCC-generated code into libc's vfprintf family.  HCC
-- currently has no floating-point call ABI, so fp_offset starts exhausted.
lowerSysvVaStart :: Expr -> Int -> CompileM [Instr]
lowerSysvVaStart list fixed = do
  (listInstrs, listOp) <- lowerExpr list
  regEnd <- freshTemp
  regSave <- freshTemp
  overflowBase <- freshTemp
  overflow <- freshTemp
  gpAddr <- freshTemp
  fpAddr <- freshTemp
  overflowAddr <- freshTemp
  regSaveAddr <- freshTemp
  let gpBytes = min fixed 6 * 8
      stackBytes = max 0 (fixed - 6) * 8
  pure (listInstrs ++
    [ IVaEnd regEnd
    , IBin regSave ISub (OTemp regEnd) (OImm 48)
    , IVaOverflow overflowBase
    , IBin overflow IAdd (OTemp overflowBase) (OImm stackBytes)
    , ICopy gpAddr listOp
    , IBin fpAddr IAdd listOp (OImm 4)
    , IBin overflowAddr IAdd listOp (OImm 8)
    , IBin regSaveAddr IAdd listOp (OImm 16)
    , IStore32 (OTemp gpAddr) (OImm gpBytes)
    , IStore32 (OTemp fpAddr) (OImm 304)
    , IStore64 (OTemp overflowAddr) (OTemp overflow)
    , IStore64 (OTemp regSaveAddr) (OTemp regSave)
    ])

lowerSysvVaArg :: Expr -> CType -> CompileM ([Instr], Operand)
lowerSysvVaArg list ty = do
  (listInstrs, listOp) <- lowerExpr list
  gpAddr <- freshTemp
  gpOffset <- freshTemp
  gpLimit <- freshTemp
  inRegs <- freshTemp
  regSaveAddr <- freshTemp
  regSave <- freshTemp
  regValueAddr <- freshTemp
  nextGp <- freshTemp
  overflowAddr <- freshTemp
  overflow <- freshTemp
  nextOverflow <- freshTemp
  current <- freshTemp
  step <- vaArgSlotSize ty
  let regInstrs =
        [ IBin regSaveAddr IAdd listOp (OImm 16)
        , ILoad64 regSave (OTemp regSaveAddr)
        , IBin regValueAddr IAdd (OTemp regSave) (OTemp gpOffset)
        , IBin nextGp IAdd (OTemp gpOffset) (OImm step)
        , IStore32 (OTemp gpAddr) (OTemp nextGp)
        ]
      stackInstrs =
        [ IBin overflowAddr IAdd listOp (OImm 8)
        , ILoad64 overflow (OTemp overflowAddr)
        , IBin nextOverflow IAdd (OTemp overflow) (OImm step)
        , IStore64 (OTemp overflowAddr) (OTemp nextOverflow)
        ]
  value <- lowerVaValue ty (OTemp current)
  case value of
    (valueInstrs, valueOp) ->
      pure ( listInstrs ++
             [ ICopy gpAddr listOp
             , ILoad32 gpOffset (OTemp gpAddr)
             , IBin gpLimit IAdd (OTemp gpOffset) (OImm step)
             , IBin inRegs IULe (OTemp gpLimit) (OImm 48)
             , ICond current [] (OTemp inRegs)
                 regInstrs (OTemp regValueAddr)
                 stackInstrs (OTemp overflow)
             ] ++ valueInstrs
           , valueOp)

lowerVaValue :: CType -> Operand -> CompileM ([Instr], Operand)
lowerVaValue ty currentOp = do
  aggregate <- isAggregateTypeM ty
  if aggregate
    then do
      temp <- freshTemp
      size <- typeSize ty
      copyInstrs <- copyObject (OTemp temp) currentOp ty
      pure (IAlloca temp size : copyInstrs, OTemp temp)
    else do
      out <- freshTemp
      load <- loadInstr out ty currentOp
      (coerceInstrs, coerceOp) <- coerceScalar ty (OTemp out)
      pure ([load] ++ coerceInstrs, coerceOp)

vaArgSlotSize :: CType -> CompileM Int
vaArgSlotSize ty = do
  size <- typeSize ty
  word <- targetWordSize
  pure (alignUp (max size word) word)

lowerStmtExpr :: [Stmt] -> CompileM ([Instr], Operand)
lowerStmtExpr body =
  withVarScope (lowerStmtExprBody body)

lowerStmtExprBody :: [Stmt] -> CompileM ([Instr], Operand)
lowerStmtExprBody body = case body of
  [] -> pure ([], OImm 0)
  [SExpr expr] -> lowerExpr expr
  stmt:rest -> do
    instrs <- lowerStmtExprSideEffect stmt
    (restInstrs, op) <- lowerStmtExprBody rest
    pure (instrs ++ restInstrs, op)

lowerStmtExprSideEffect :: Stmt -> CompileM [Instr]
lowerStmtExprSideEffect stmt = case stmt of
  SDecl storage ty name initExpr -> lowerStoredDecl storage ty name initExpr
  SDecls storage decls -> lowerStoredDecls storage decls
  STypedef types -> registerTypesAggregates types >> pure []
  SExpr expr -> lowerSideEffect expr
  SIf cond yes no -> lowerStmtExprIfSideEffect cond yes no
  SBlock body -> withVarScope (lowerStmtExprSideEffects body)
  _ -> throwC ("unsupported statement in statement expression: " ++ renderStmtTag stmt)

lowerStmtExprIfSideEffect :: Expr -> [Stmt] -> [Stmt] -> CompileM [Instr]
lowerStmtExprIfSideEffect cond yes no = do
  (condInstrs, condOp) <- lowerTruthExpr cond
  yesInstrs <- lowerStmtExprSideEffects yes
  noInstrs <- lowerStmtExprSideEffects no
  out <- freshTemp
  pure [ICond out condInstrs condOp yesInstrs (OImm 0) noInstrs (OImm 0)]

lowerStmtExprSideEffects :: [Stmt] -> CompileM [Instr]
lowerStmtExprSideEffects body = case body of
  [] -> pure []
  stmt:rest -> do
    instrs <- lowerStmtExprSideEffect stmt
    restInstrs <- lowerStmtExprSideEffects rest
    pure (instrs ++ restInstrs)

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
      mty <- exprType expr
      softFloatRuntime <- useSoftFloatRuntime
      case mty of
        Just ty | softFloatRuntime && isFloatingType ty -> do
          (truthInstrs, truthOp) <- lowerFloatingTruth ty op
          pure (instrs ++ truthInstrs, truthOp)
        _ -> do
          out <- freshTemp
          pure (instrs ++ [IBin out INe op (OImm 0)], OTemp out)

exprIsBoolean :: Expr -> Bool
exprIsBoolean expr = case expr of
  EUnary "!" _ -> True
  EBinary op _ _ -> op `elem` ["==", "!=", "<", "<=", ">", ">=", "&&", "||"]
  _ -> False

exprIsShortCircuitBoolean :: Expr -> Bool
exprIsShortCircuitBoolean expr = case expr of
  EBinary "&&" _ _ -> True
  EBinary "||" _ _ -> True
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
  aty <- exprType a
  bty <- exprType b
  softFloatRuntime <- useSoftFloatRuntime
  if softFloatRuntime &&
       (maybe False isFloatingType aty || maybe False isFloatingType bty)
    then lowerFloatingBinary "+" a b
    else case pointerElementType aty of
      Just elemTy -> lowerPointerOffset IAdd a b elemTy
      Nothing -> case pointerElementType bty of
        Just elemTy -> lowerPointerOffset IAdd b a elemTy
        Nothing -> lowerPlainBin IAdd a b

lowerSubExpr :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerSubExpr a b = do
  aty <- exprType a
  bty <- exprType b
  softFloatRuntime <- useSoftFloatRuntime
  if softFloatRuntime &&
       (maybe False isFloatingType aty || maybe False isFloatingType bty)
    then lowerFloatingBinary "-" a b
    else case pointerElementType aty of
      Just elemTy -> case pointerElementType bty of
        Just _ -> lowerPointerDiff a b elemTy
        Nothing -> lowerPointerOffset ISub a b elemTy
      Nothing -> lowerPlainBin ISub a b

lowerPointerDiff :: Expr -> Expr -> CType -> CompileM ([Instr], Operand)
lowerPointerDiff a b elemTy = do
  (ai, ao) <- lowerExpr a
  (bi, bo) <- lowerExpr b
  diff <- freshTemp
  out <- freshTemp
  size <- typeSize elemTy
  pure (ai ++ bi ++ [IBin diff ISub ao bo, IBin out IDiv (OTemp diff) (OImm size)], OTemp out)

lowerPointerOffset :: BinOp -> Expr -> Expr -> CType -> CompileM ([Instr], Operand)
lowerPointerOffset op ptr offset elemTy = do
  (ptrInstrs, po) <- lowerExpr ptr
  (oi, oo) <- lowerExpr offset
  size <- typeSize elemTy
  (scaledInstrs, scaledOp) <- scaledOffset oo size
  out <- freshTemp
  pure (ptrInstrs ++ oi ++ scaledInstrs ++ [IBin out op po scaledOp], OTemp out)

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
  (acoerceInstrs, acoerceOp) <- coerceBinOperand commonTy a ao
  (bcoerceInstrs, bcoerceOp) <- coerceBinOperand commonTy b bo
  out <- freshTemp
  (coerceInstrs, coerceOp) <-
    if isComparisonBinOp op
    then pure ([], OTemp out)
    else coerceScalar commonTy (OTemp out)
  pure ( ai ++ bi ++ acoerceInstrs ++ bcoerceInstrs ++
         [IBin out op acoerceOp bcoerceOp] ++ coerceInstrs
       , coerceOp)

coerceBinOperand :: CType -> Expr -> Operand -> CompileM ([Instr], Operand)
coerceBinOperand commonTy expr op = case expr of
  EVar name -> do
    local <- lookupVarMaybe name
    case local of
      Just _ -> pure ([], op)
      Nothing -> do
        constant <- lookupConstant name
        case (constant, builtinConstant name) of
          (Nothing, Nothing) -> pure ([], op)
          _ -> coerceScalar commonTy op
  _ -> coerceScalar commonTy op

isComparisonBinOp :: BinOp -> Bool
isComparisonBinOp op = case op of
  IEq -> True
  INe -> True
  ILt -> True
  ILe -> True
  IGt -> True
  IGe -> True
  IULt -> True
  IULe -> True
  IUGt -> True
  IUGe -> True
  _ -> False

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
  sourceTy <- exprType rhs
  (coerceInstrs, coerceOp) <- case sourceTy of
    Just source -> convertScalarValue source targetTy rhsOp
    Nothing -> coerceScalar targetTy rhsOp
  writeInstrs <- writeLValue lvalue coerceOp
  pure (lhsInstrs ++ rhsInstrs ++ coerceInstrs ++ writeInstrs, coerceOp)

lowerCompoundAssignment :: String -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerCompoundAssignment op lhs rhs = do
  (lhsInstrs, lvalue) <- lowerLValue lhs
  (readInstrs, currentOp) <- readLValue lvalue
  targetTy <- lValueType lvalue
  (rhsInstrs, rhsOp) <- lowerExpr rhs
  rhsTy <- exprType rhs
  (rhsCoerceInstrs, coercedRhs) <- case rhsTy of
    Just source -> convertScalarValue source targetTy rhsOp
    Nothing -> coerceScalar targetTy rhsOp
  (opInstrs, resultOp) <- compoundBinOp op targetTy currentOp coercedRhs
  (coerceInstrs, coerceOp) <- coerceScalar targetTy resultOp
  writeInstrs <- writeLValue lvalue coerceOp
  pure ( lhsInstrs ++ readInstrs ++ rhsInstrs ++ rhsCoerceInstrs ++
         opInstrs ++ coerceInstrs ++ writeInstrs
       , coerceOp)

compoundBinOp :: String -> CType -> Operand -> Operand -> CompileM ([Instr], Operand)
compoundBinOp op targetTy lhsOp rhsOp = do
  softFloatRuntime <- useSoftFloatRuntime
  case targetTy of
    CPtr elemTy | op == "+" || op == "-" ->
      pointerCompoundOffset (if op == "+" then IAdd else ISub) lhsOp rhsOp elemTy
    _ | softFloatRuntime && isFloatingType targetTy -> do
      helperOp <- floatingBinaryHelper op
      lowerFloatingRuntimeCall (floatingRuntimePrefix targetTy ++ helperOp) [lhsOp, rhsOp]
    _ -> do
      iop <- case op of
        "/" -> pure (if isUnsignedType targetTy then IUDiv else IDiv)
        "%" -> pure (if isUnsignedType targetTy then IUMod else IMod)
        ">>" -> shiftRightOpForType targetTy
        _ -> case lowerBinOp op of
          Just o -> pure o
          Nothing -> throwC ("unsupported compound assignment operator: " ++ op)
      out <- freshTemp
      pure ([IBin out iop lhsOp rhsOp], OTemp out)

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
  targetTy <- lValueType lvalue
  softFloatRuntime <- useSoftFloatRuntime
  if softFloatRuntime && isFloatingType targetTy
    then do
      (literalInstrs, one) <- lowerFloatingLiteral
        (case targetTy of CFloat -> "1.0f"; CLongDouble -> "1.0L"; _ -> "1.0")
      let helperOp = case op of ISub -> "_sub"; _ -> "_add"
      (opInstrs, result) <- lowerFloatingRuntimeCall
        (floatingRuntimePrefix targetTy ++ helperOp) [current, one]
      writeInstrs <- writeLValue lvalue result
      pure (lvInstrs ++ readInstrs ++ literalInstrs ++ opInstrs ++ writeInstrs,
            if prefix then result else current)
    else do
      out <- freshTemp
      step <- incDecStep target
      if prefix
        then do
          writeInstrs <- writeLValue lvalue (OTemp out)
          pure (lvInstrs ++ readInstrs ++ [IBin out op current (OImm step)] ++ writeInstrs, OTemp out)
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
    _ -> do
      aggregateStorage <- isAggregateTypeM ty
      if aggregateStorage
        then pure ([], addr)
        else do
          out <- freshTemp
          load <- loadInstr out ty addr
          pure ([load], OTemp out)
  LBitField addr ty bitOffset width ->
    readBitField addr ty bitOffset width

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
      else do
        store <- storeInstr ty addr value
        pure [store]
  LBitField addr ty bitOffset width ->
    writeBitField addr ty bitOffset width value

lValueType :: LValue -> CompileM CType
lValueType lvalue = case lvalue of
  LLocal _ ty -> pure ty
  LAddress _ ty -> pure ty
  LBitField _ ty _ _ -> pure ty

readBitField :: Operand -> CType -> Int -> Int -> CompileM ([Instr], Operand)
readBitField addr ty bitOffset width = do
  size <- typeSize ty
  loaded <- freshTemp
  if bitOffset == 0 && width == size * 8
    then do
      load <- loadInstr loaded ty addr
      pure ([load], OTemp loaded)
    else do
      word <- targetWordSize
      let load = unsignedLoadAt size loaded addr
      (shiftInstrs, shifted) <- if bitOffset == 0
        then pure ([], OTemp loaded)
        else do
          shiftedTemp <- freshTemp
          pure ([IBin shiftedTemp IShr (OTemp loaded) (OImm bitOffset)], OTemp shiftedTemp)
      if isSignedIntegerType ty
        then do
          left <- freshTemp
          out <- freshTemp
          let shift = word * 8 - width
          pure (load : shiftInstrs ++
                [ IBin left IShl shifted (OImm shift)
                , IBin out ISar (OTemp left) (OImm shift)
                ], OTemp out)
        else do
          left <- freshTemp
          out <- freshTemp
          let shift = word * 8 - width
          pure (load : shiftInstrs ++
                [ IBin left IShl shifted (OImm shift)
                , IBin out IShr (OTemp left) (OImm shift)
                ], OTemp out)

writeBitField :: Operand -> CType -> Int -> Int -> Operand -> CompileM [Instr]
writeBitField addr ty bitOffset width value = do
  size <- typeSize ty
  if bitOffset == 0 && width == size * 8
    then pure [unsignedStoreAt size addr value]
    else do
      word <- targetWordSize
      loaded <- freshTemp
      valueLeft <- freshTemp
      valueBits <- freshTemp
      mask <- freshTemp
      inverseMask <- freshTemp
      cleared <- freshTemp
      combined <- freshTemp
      let shift = word * 8 - width
      let load = unsignedLoadAt size loaded addr
      let store = unsignedStoreAt size addr (OTemp combined)
      if bitOffset == 0
        then pure
          [ load
          , IBin valueLeft IShl value (OImm shift)
          , IBin valueBits IShr (OTemp valueLeft) (OImm shift)
          , IBin mask IShr (OImm (-1)) (OImm shift)
          , IBin inverseMask IXor (OTemp mask) (OImm (-1))
          , IBin cleared IAnd (OTemp loaded) (OTemp inverseMask)
          , IBin combined IOr (OTemp cleared) (OTemp valueBits)
          , store
          ]
        else do
          positioned <- freshTemp
          positionedMask <- freshTemp
          pure
            [ load
            , IBin valueLeft IShl value (OImm shift)
            , IBin valueBits IShr (OTemp valueLeft) (OImm shift)
            , IBin positioned IShl (OTemp valueBits) (OImm bitOffset)
            , IBin mask IShr (OImm (-1)) (OImm shift)
            , IBin positionedMask IShl (OTemp mask) (OImm bitOffset)
            , IBin inverseMask IXor (OTemp positionedMask) (OImm (-1))
            , IBin cleared IAnd (OTemp loaded) (OTemp inverseMask)
            , IBin combined IOr (OTemp cleared) (OTemp positioned)
            , store
            ]

coerceMaybeScalar :: Maybe CType -> Operand -> CompileM ([Instr], Operand)
coerceMaybeScalar mty op = case mty of
  Just ty -> coerceScalar ty op
  Nothing -> pure ([], op)

convertMaybeScalarValue :: Maybe CType -> Maybe CType -> Operand -> CompileM ([Instr], Operand)
convertMaybeScalarValue sourceTy targetTy op = case (sourceTy, targetTy) of
  (Just source, Just target) -> convertScalarValue source target op
  (_, Just target) -> coerceScalar target op
  _ -> pure ([], op)

-- M1 deliberately has no target floating-point instruction set.  Keep its
-- internal value convention as IEEE bits in a general-purpose register and
-- delegate operations to a tiny C runtime.  This is independent of the host
-- C ABI for float arguments: every helper accepts and returns integer bits.
convertScalarValue :: CType -> CType -> Operand -> CompileM ([Instr], Operand)
convertScalarValue sourceTy targetTy op = do
  softFloatRuntime <- useSoftFloatRuntime
  if softFloatRuntime
    then convertScalarValueSoft sourceTy targetTy op
    else coerceScalar targetTy op

convertScalarValueSoft :: CType -> CType -> Operand -> CompileM ([Instr], Operand)
convertScalarValueSoft sourceTy targetTy op
  | isFloatingType sourceTy && isFloatingType targetTy =
      convertFloatingWidth sourceTy targetTy op
  | isFloatingType targetTy = do
      sourceInteger <- isIntegerTypeM sourceTy
      if sourceInteger
        then do
          canonicalSource <- canonicalIntegerType sourceTy
          let suffix = if isUnsignedType canonicalSource then "_from_u64" else "_from_i64"
          lowerFloatingRuntimeCall (floatingRuntimePrefix targetTy ++ suffix) [op]
        else pure ([], op)
  | isFloatingType sourceTy = do
      targetInteger <- isIntegerTypeM targetTy
      if targetInteger
        then case targetTy of
          CBool -> lowerFloatingTruth sourceTy op
          _ -> do
              canonicalTarget <- canonicalIntegerType targetTy
              let suffix = if isUnsignedType canonicalTarget then "_to_u64" else "_to_i64"
              (instrs, converted) <- lowerFloatingRuntimeCall
                (floatingRuntimePrefix sourceTy ++ suffix) [op]
              (coerceInstrs, coerced) <- coerceScalar targetTy converted
              pure (instrs ++ coerceInstrs, coerced)
        else pure ([], op)
  | otherwise = coerceScalar targetTy op

convertFloatingWidth :: CType -> CType -> Operand -> CompileM ([Instr], Operand)
convertFloatingWidth sourceTy targetTy op =
  let sourcePrefix = floatingRuntimePrefix sourceTy
      targetPrefix = floatingRuntimePrefix targetTy
  in if sourcePrefix == targetPrefix
      then pure ([], op)
      else lowerFloatingRuntimeCall (sourcePrefix ++ "_to_" ++ floatingRuntimeKind targetTy) [op]

floatingRuntimePrefix :: CType -> String
floatingRuntimePrefix ty = "hcc_soft_" ++ floatingRuntimeKind ty

floatingRuntimeKind :: CType -> String
floatingRuntimeKind ty = case ty of
  CFloat -> "f32"
  -- M1 has one 64-bit floating representation.  Long-double precision is a
  -- separate backend capability, not a GCC-specific special case here.
  _ -> "f64"

lowerFloatingLiteral :: String -> CompileM ([Instr], Operand)
lowerFloatingLiteral literal = do
  label <- freshDataLabel
  addDataItem (DataItem label (map DByte (stringBytes literal)))
  lowerFloatingRuntimeCall
    (floatingRuntimePrefix (floatLiteralType literal) ++ "_from_string")
    [OGlobal label]

lowerFloatingUnary :: String -> CType -> Operand -> CompileM ([Instr], Operand)
lowerFloatingUnary op ty value =
  lowerFloatingRuntimeCall (floatingRuntimePrefix ty ++ "_" ++ op) [value]

lowerFloatingTruth :: CType -> Operand -> CompileM ([Instr], Operand)
lowerFloatingTruth ty value =
  lowerFloatingRuntimeCall (floatingRuntimePrefix ty ++ "_truth") [value]

lowerFloatingRuntimeCall :: String -> [Operand] -> CompileM ([Instr], Operand)
lowerFloatingRuntimeCall name args = do
  out <- freshTemp
  pure ([ICall (Just out) name args], OTemp out)

coerceScalar :: CType -> Operand -> CompileM ([Instr], Operand)
coerceScalar ty op = case ty of
  CBool -> coerceBool op
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
  | width == 2 = ILoad16 dst addr
  | otherwise  = ILoad8 dst addr

unsignedStoreAt :: Int -> Operand -> Operand -> Instr
unsignedStoreAt width addr value
  | width == 8 = IStore64 addr value
  | width == 4 = IStore32 addr value
  | width == 2 = IStore16 addr value
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
  local <- lookupVarMaybe name
  case local of
    Nothing -> do
      function <- lookupFunction name
      if function
        then do
          resolved <- resolveSymbolName name
          pure ([], OFunction resolved)
        else lowerNonFunctionAddress (EVar name)
    Just _ ->
      lowerNonFunctionAddress (EVar name)

lowerNonFunctionAddress :: Expr -> CompileM ([Instr], Operand)
lowerNonFunctionAddress target = do
  (instrs, lvalue) <- lowerLValue target
  case lvalue of
    LAddress addr _ -> pure (instrs, addr)
    LBitField _ _ _ _ -> throwC "cannot take the address of a bit-field"
    LLocal temp ty -> do
      aggregateStorage <- isAggregateTypeM ty
      if aggregateStorage
        then pure (instrs, OTemp temp)
        else do
          out <- freshTemp
          pure (instrs ++ [IAddrOf out temp], OTemp out)

lowerLValue :: Expr -> CompileM ([Instr], LValue)
lowerLValue target = case target of
  EVar name -> do
    local <- lookupVarMaybe name
    case local of
      Just temp -> do
        ty <- lookupVarType name
        knownTy <- requireMaybeType ("unknown local type: " ++ name) ty
        pure ([], LLocal temp knownTy)
      Nothing -> do
        ty <- lookupGlobalType name
        knownTy <- requireMaybeType ("unknown global type: " ++ name) ty
        resolved <- resolveSymbolName name
        pure ([], LAddress (OGlobal resolved) knownTy)
  EUnary "*" ptr -> do
    (instrs, op) <- lowerExpr ptr
    ty <- exprType target
    knownTy <- requireMaybeType ("dereference has unknown pointed-to type: " ++ renderExprForDiagnostic ptr) ty
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
    (fieldTy, offset, bitRange) <- memberInfoForExpr baseTy field base
    (addrInstrs, addrOp) <- offsetAddress baseOp offset
    pure (baseInstrs ++ addrInstrs, memberLValue addrOp fieldTy bitRange)
  EMember base field -> do
    (baseInstrs, baseAddr) <- lowerAggregateBaseAddress base
    baseTy <- exprType base
    knownBaseTy <- requireMaybeType "member base has unknown type" baseTy
    (fieldTy, offset, bitRange) <- memberInfoForExpr (Just (CPtr knownBaseTy)) field base
    (addrInstrs, addrOp) <- offsetAddress baseAddr offset
    pure (baseInstrs ++ addrInstrs, memberLValue addrOp fieldTy bitRange)
  _ -> throwC ("unsupported lvalue: " ++ renderExprForDiagnostic target)

memberLValue :: Operand -> CType -> Maybe (Int, Int) -> LValue
memberLValue addr ty bitRange = case bitRange of
  Nothing -> LAddress addr ty
  Just (bitOffset, width) -> LBitField addr ty bitOffset width

lowerAggregateBaseAddress :: Expr -> CompileM ([Instr], Operand)
lowerAggregateBaseAddress base = case base of
  EVar _ -> lowerLValueAddress base
  EUnary "*" _ -> lowerLValueAddress base
  EIndex _ _ -> lowerLValueAddress base
  EPtrMember _ _ -> lowerLValueAddress base
  EMember _ _ -> lowerLValueAddress base
  _ -> do
    mty <- exprType base
    ty <- requireMaybeType "member base has unknown type" mty
    aggregate <- isAggregateTypeM ty
    if aggregate
      then lowerExpr base
      else lowerLValueAddress base

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
  ESizeofType _ -> pure (Just CInt)
  ESizeofExpr _ -> pure (Just CInt)
  EAlignofType _ -> pure (Just CInt)
  EAlignofExpr _ -> pure (Just CInt)
  EVaArg _ ty -> pure (Just ty)
  EStmtExpr body -> stmtExprType body
  EVar name -> do
    if isFunctionNameMacro name
      then pure (Just (CPtr CChar))
      else do
        local <- lookupVarType name
        case local of
          Just ty -> pure (Just ty)
          Nothing -> do
            functionTy <- lookupFunctionType name
            case functionTy of
              Just ty -> pure (Just ty)
              Nothing -> do
                globalTy <- lookupGlobalType name
                case globalTy of
                  Just ty -> pure (Just ty)
                  Nothing -> do
                    constant <- lookupConstant name
                    case constant of
                      Just _ -> pure (Just CInt)
                      Nothing -> pure Nothing
  ECast ty _ -> pure (Just ty)
  EUnary "+" value -> do
    mty <- exprType value
    promoteMaybeIntegerType mty
  EUnary "-" value -> do
    mty <- exprType value
    promoteMaybeIntegerType mty
  EUnary "~" value -> do
    mty <- exprType value
    promoteMaybeIntegerType mty
  EUnary "!" _ -> pure (Just CInt)
  EUnary "*" value -> do
    mty <- exprType value
    pure (case mty of
      Just (CFunc ret params) -> Just (CFunc ret params)
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
    info <- memberInfoMaybeForExpr baseTy field base
    pure (case info of
      Just (fieldTy, _, _) -> Just fieldTy
      Nothing -> Nothing)
  EMember base field -> do
    baseTy <- exprType base
    knownBaseTy <- requireMaybeType "member base has unknown type" baseTy
    info <- memberInfoMaybeForExpr (Just (CPtr knownBaseTy)) field base
    pure (case info of
      Just (fieldTy, _, _) -> Just fieldTy
      Nothing -> Nothing)
  EBinary "+" left right -> do
    leftTy <- exprType left
    rightTy <- exprType right
    arithmeticTy <- usualArithmeticType left right
    pure (addExprResultType leftTy rightTy arithmeticTy)
  EBinary "-" left right -> do
    leftTy <- exprType left
    rightTy <- exprType right
    arithmeticTy <- usualArithmeticType left right
    pure (subExprResultType leftTy rightTy arithmeticTy)
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
    if isComparisonOpString op || op `elem` ["==", "!="]
      then pure (Just CInt)
      else do
        leftTy <- exprType left
        rightTy <- exprType right
        arithmeticTy <- usualArithmeticType left right
        pure (case op of
          "*" -> Just arithmeticTy
          "/" -> Just arithmeticTy
          "%" -> Just arithmeticTy
          "&" -> Just arithmeticTy
          "|" -> Just arithmeticTy
          "^" -> Just arithmeticTy
          _ -> case (leftTy, rightTy) of
            (Just _, Just _) -> Just arithmeticTy
            _ -> Nothing)
  ECond _ yes no -> do
    yesTy <- exprType yes
    noTy <- exprType no
    conditionalExprType yes yesTy no noTy
  EAssign lhs _ -> exprType lhs
  ECompoundAssign _ lhs _ -> exprType lhs
  EPostfix _ value -> exprType value
  EUnary "++" value -> exprType value
  EUnary "--" value -> exprType value
  ECall (EVar name) _ -> do
    localTy <- lookupVarType name
    case localTy of
      Just ty -> pure (functionResultType ty)
      Nothing -> do
        functionTy <- lookupFunctionType name
        case functionResultType =<< functionTy of
          Just retTy -> pure (Just retTy)
          Nothing -> do
            globalTy <- lookupGlobalType name
            case functionResultType =<< globalTy of
              Just retTy -> pure (Just retTy)
              Nothing -> do
                function <- lookupFunction name
                pure (if function then Just CLong else Nothing)
  ECall callee _ -> do
    calleeTy <- exprType callee
    pure (functionResultType =<< calleeTy)
  _ -> pure Nothing

-- String literals decay to pointers in ordinary expressions, but sizeof and
-- alignof observe their original array type, including the terminating NUL.
sizeofExprValue :: Expr -> CompileM Int
sizeofExprValue value = case value of
  EString text -> pure (length (stringBytes text))
  _ -> do
    mty <- exprType value
    ty <- requireMaybeType "sizeof expression has unknown type" mty
    typeSize ty

alignofExprValue :: Expr -> CompileM Int
alignofExprValue value = case value of
  EString _ -> typeAlign CChar
  _ -> do
    mty <- exprType value
    ty <- requireMaybeType "alignof expression has unknown type" mty
    typeAlign ty

promoteMaybeIntegerType :: Maybe CType -> CompileM (Maybe CType)
promoteMaybeIntegerType mty = case mty of
  Nothing -> pure Nothing
  Just ty -> do
    promoted <- promoteIntegerType ty
    pure (Just promoted)

functionResultType :: CType -> Maybe CType
functionResultType ty = case ty of
  CFunc ret _ -> Just ret
  CPtr inner -> functionResultType inner
  _ -> Nothing

functionParamTypes :: CType -> Maybe [CType]
functionParamTypes ty = case ty of
  CFunc _ params -> Just params
  CPtr inner -> functionParamTypes inner
  _ -> Nothing

stmtExprType :: [Stmt] -> CompileM (Maybe CType)
stmtExprType body = case body of
  [] -> pure (Just CInt)
  [SExpr expr] -> exprType expr
  _:rest -> stmtExprType rest

isFunctionNameMacro :: String -> Bool
isFunctionNameMacro name =
  name `elem` ["__func__", "__FUNCTION__", "__PRETTY_FUNCTION__"]

addExprResultType :: Maybe CType -> Maybe CType -> CType -> Maybe CType
addExprResultType leftTy rightTy arithmeticTy = case pointerElementType leftTy of
  Just _ -> leftTy
  Nothing -> case pointerElementType rightTy of
    Just _ -> rightTy
    Nothing -> Just arithmeticTy

subExprResultType :: Maybe CType -> Maybe CType -> CType -> Maybe CType
subExprResultType leftTy rightTy arithmeticTy = case pointerElementType leftTy of
  Just _ -> case pointerElementType rightTy of
    Just _ -> Just CLong
    Nothing -> leftTy
  Nothing -> Just arithmeticTy

conditionalExprType :: Expr -> Maybe CType -> Expr -> Maybe CType -> CompileM (Maybe CType)
conditionalExprType yes yesTy no noTy = case (yesTy, noTy) of
  (Just ty, Nothing) -> pure (Just ty)
  (Nothing, Just ty) -> pure (Just ty)
  (Just yesKnown, Just noKnown) ->
    if isPointerType yesKnown && isNullPointerConstant no
      then pure (Just yesKnown)
      else if isNullPointerConstant yes && isPointerType noKnown
        then pure (Just noKnown)
        else if isPointerType yesKnown && isPointerType noKnown
          then pure (Just (conditionalPointerType yesKnown noKnown))
          else do
            yesArithmetic <- isArithmeticTypeM yesKnown
            noArithmetic <- isArithmeticTypeM noKnown
            if yesArithmetic && noArithmetic
              then Just <$> usualArithmeticType yes no
              else pure (Just yesKnown)
  _ -> pure Nothing

conditionalPointerType :: CType -> CType -> CType
conditionalPointerType yesTy noTy =
  if isVoidPointerType yesTy then yesTy else if isVoidPointerType noTy then noTy else yesTy

isVoidPointerType :: CType -> Bool
isVoidPointerType ty = case ty of
  CPtr CVoid -> True
  _ -> False

isNullPointerConstant :: Expr -> Bool
isNullPointerConstant expr = case expr of
  EInt text -> parseInt text == 0
  EChar text -> charValue text == 0
  EUnary "+" value -> isNullPointerConstant value
  ECast _ value -> isNullPointerConstant value
  _ -> False

isArithmeticTypeM :: CType -> CompileM Bool
isArithmeticTypeM ty =
  if isFloatingType ty
    then pure True
    else isIntegerTypeM ty

memberInfo :: Maybe CType -> String -> CompileM (CType, Int, Maybe (Int, Int))
memberInfo mty field = do
  found <- memberInfoMaybe mty field
  case found of
    Just info -> pure info
    Nothing -> throwC ("unknown struct member: " ++ field ++ " on aggregate " ++ memberBaseTypeLabel mty)

memberInfoForExpr :: Maybe CType -> String -> Expr -> CompileM (CType, Int, Maybe (Int, Int))
memberInfoForExpr mty field base = do
  found <- memberInfoMaybe mty field
  case found of
    Just info -> pure info
    Nothing -> throwC ("unknown struct member: " ++ field ++ " on aggregate " ++ memberBaseTypeLabel mty ++ " in " ++ renderExprForDiagnostic base)

memberBaseTypeLabel :: Maybe CType -> String
memberBaseTypeLabel mty = case mty of
  Nothing -> "<unknown>"
  Just ty -> ctypeLabel ty

ctypeLabel :: CType -> String
ctypeLabel ty = case ty of
  CVoid -> "void"
  CInt -> "int"
  CShort -> "short"
  CChar -> "char"
  CUnsigned -> "unsigned"
  CUnsignedShort -> "unsigned short"
  CUnsignedChar -> "unsigned char"
  CLong -> "long"
  CUnsignedLong -> "unsigned long"
  CLongLong -> "long long"
  CUnsignedLongLong -> "unsigned long long"
  CBool -> "_Bool"
  CFloat -> "float"
  CDouble -> "double"
  CLongDouble -> "long double"
  CStruct name -> "struct " ++ name
  CUnion name -> "union " ++ name
  CStructNamed name _ -> "struct " ++ name
  CUnionNamed name _ -> "union " ++ name
  CStructDef _ -> "anonymous struct"
  CUnionDef _ -> "anonymous union"
  CEnum name _ -> "enum " ++ name
  CNamed name -> name
  CArray inner _ -> ctypeLabel inner ++ "[]"
  CFunc ret _ -> ctypeLabel ret ++ "()"
  CPtr inner -> ctypeLabel inner ++ " *"

memberInfoMaybe :: Maybe CType -> String -> CompileM (Maybe (CType, Int, Maybe (Int, Int)))
memberInfoMaybe mty field = case mty of
  Just (CPtr ty) -> memberInfoForAggregate ty field
  Just (CArray ty _) -> memberInfoForAggregate ty field
  _ -> pure Nothing

memberInfoMaybeForExpr :: Maybe CType -> String -> Expr -> CompileM (Maybe (CType, Int, Maybe (Int, Int)))
memberInfoMaybeForExpr mty field base = do
  info <- memberInfoMaybe mty field
  case info of
    Just _ -> pure info
    Nothing -> throwC ("unknown struct member: " ++ field ++ " on aggregate " ++ memberBaseTypeLabel mty ++ " in " ++ renderExprForDiagnostic base)

memberInfoForAggregate :: CType -> String -> CompileM (Maybe (CType, Int, Maybe (Int, Int)))
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

memberInfoForAggregateUncached :: CType -> String -> CompileM (Maybe (CType, Int, Maybe (Int, Int)))
memberInfoForAggregateUncached ty field = do
  aggregate <- aggregateFields ty
  case aggregate of
    Nothing -> pure Nothing
    Just aggregateInfo -> case aggregateInfo of
      (isUnion, fields) -> fieldOffset isUnion field 0 fields

aggregateCacheName :: CType -> Maybe String
aggregateCacheName ty = case ty of
  CStruct name -> Just name
  CUnion name -> Just name
  CStructNamed name _ -> Just name
  CUnionNamed name _ -> Just name
  CNamed name -> Just name
  _ -> Nothing

data FieldLayout = FieldLayout CType String Int (Maybe (Int, Int))

fieldOffset :: Bool -> String -> Int -> [Field] -> CompileM (Maybe (CType, Int, Maybe (Int, Int)))
fieldOffset isUnion field baseOffset fields = do
  layouts <- aggregateFieldLayouts isUnion fields
  memberInfoFromLayouts baseOffset field layouts

memberInfoFromLayouts :: Int -> String -> [FieldLayout] -> CompileM (Maybe (CType, Int, Maybe (Int, Int)))
memberInfoFromLayouts baseOffset field layouts = case layouts of
  [] -> pure Nothing
  FieldLayout ty name offset bitRange:rest -> do
    let memberOffset = baseOffset + offset
    if name == field
      then pure (Just (ty, memberOffset, bitRange))
      else do
        nested <- case bitRange of
          Nothing -> anonymousMemberInfoForName False memberOffset ty name field
          Just _ -> pure Nothing
        case nested of
          Just info -> pure (Just info)
          Nothing -> memberInfoFromLayouts baseOffset field rest

unionOffset :: Bool -> Int -> Int
unionOffset isUnion aligned =
  if isUnion then 0 else aligned

anonymousMemberInfoForName :: Bool -> Int -> CType -> String -> String -> CompileM (Maybe (CType, Int, Maybe (Int, Int)))
anonymousMemberInfoForName isUnion aligned ty name field =
  if name == ""
    then anonymousMemberInfo (unionOffset isUnion aligned) ty field
    else pure Nothing

anonymousMemberInfo :: Int -> CType -> String -> CompileM (Maybe (CType, Int, Maybe (Int, Int)))
anonymousMemberInfo baseOffset ty field = do
  aggregate <- aggregateFields ty
  case aggregate of
    Nothing -> pure Nothing
    Just aggregateInfo -> case aggregateInfo of
      (isUnion, fields) -> nestedFieldOffset baseOffset isUnion field 0 fields

nestedFieldOffset :: Int -> Bool -> String -> Int -> [Field] -> CompileM (Maybe (CType, Int, Maybe (Int, Int)))
nestedFieldOffset baseOffset isUnion field _ fields =
  fieldOffset isUnion field baseOffset fields

loadInstr :: Temp -> CType -> Operand -> CompileM Instr
loadInstr out ty addr = do
  size <- typeSize ty
  let signed = isSignedIntegerType ty
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
  -- GCC selects an unsigned compatible integer type when every enumerator is
  -- nonnegative.  This matters especially for narrow enum bit-fields: reading
  -- a two-bit value of 2 must produce 2, not the sign-extended value -2.
  -- An enum whose definition has not been seen remains conservatively signed.
  CEnum _ constants -> null constants || any ((< 0) . snd) constants
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
  CEnum _ _ -> pure True
  CNamed name -> pure (maybe False (const True) (namedIntegerSize name))
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

promotedExprType :: Expr -> CompileM CType
promotedExprType expr = case expr of
  EInt text -> integerLiteralType text
  EFloat text ->
    pure (floatLiteralType text)
  _ -> do
    mty <- exprType expr
    ty <- requireMaybeType ("expression has unknown type: " ++ renderExprForDiagnostic expr) mty
    promoteIntegerType ty

integerLiteralType :: String -> CompileM CType
integerLiteralType text = do
  word <- targetWordSize
  let candidates = integerLiteralCandidates (intLiteralIsDecimal text) (intLiteralSuffix text)
  case find (integerLiteralFitsType word text) candidates of
    Just ty -> pure ty
    Nothing -> throwC ("integer literal is too large for its suffix: " ++ text)

integerLiteralValue :: String -> CompileM Int
integerLiteralValue text = do
  _ <- integerLiteralType text
  pure (parseInt text)

integerLiteralCandidates :: Bool -> (Bool, Int) -> [CType]
integerLiteralCandidates decimal suffix = case suffix of
  (False, 0) ->
    if decimal
      then [CInt, CLong, CLongLong]
      else [CInt, CUnsigned, CLong, CUnsignedLong, CLongLong, CUnsignedLongLong]
  (True, 0) -> [CUnsigned, CUnsignedLong, CUnsignedLongLong]
  (False, 1) ->
    if decimal
      then [CLong, CLongLong]
      else [CLong, CUnsignedLong, CLongLong, CUnsignedLongLong]
  (True, 1) -> [CUnsignedLong, CUnsignedLongLong]
  (False, _) -> [CLongLong, CUnsignedLongLong]
  (True, _) -> [CUnsignedLongLong]

integerLiteralFitsType :: Int -> String -> CType -> Bool
integerLiteralFitsType word text ty = case ty of
  CInt -> intLiteralFitsSigned 32 text
  CUnsigned -> intLiteralFitsUnsigned 32 text
  CLong -> intLiteralFitsSigned (word * 8) text
  CUnsignedLong -> intLiteralFitsUnsigned (word * 8) text
  CLongLong -> intLiteralFitsSigned 64 text
  CUnsignedLongLong -> intLiteralFitsUnsigned 64 text
  _ -> False

renderExprForDiagnostic :: Expr -> String
renderExprForDiagnostic expr = case expr of
  EVar name -> "EVar " ++ name
  ECast ty value -> "ECast " ++ ctypeLabel ty ++ " (" ++ renderExprForDiagnostic value ++ ")"
  ECall callee _ -> "ECall (" ++ renderExprForDiagnostic callee ++ ")"
  EUnary op value -> "EUnary " ++ op ++ " (" ++ renderExprForDiagnostic value ++ ")"
  EPtrMember base field -> "EPtrMember (" ++ renderExprForDiagnostic base ++ ") " ++ field
  EMember base field -> "EMember (" ++ renderExprForDiagnostic base ++ ") " ++ field
  EIndex base _ -> "EIndex (" ++ renderExprForDiagnostic base ++ ")"
  _ -> renderExprTag expr

floatLiteralType :: String -> CType
floatLiteralType text =
  case floatLiteralSize text of
    4 -> CFloat
    16 -> CLongDouble
    _ -> CDouble

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
    pure (size * bound)
  CStruct name -> structSize name
  CUnion name -> structSize name
  CStructNamed name fields -> do
    bindStruct name False fields
    aggregateSize False fields
  CUnionNamed name fields -> do
    bindStruct name True fields
    aggregateSize True fields
  CStructDef fields -> aggregateSize False fields
  CUnionDef fields -> aggregateSize True fields
  CEnum _ _ -> pure 4
  CNamed name -> namedTypeSize name

namedTypeSize :: String -> CompileM Int
namedTypeSize name = case namedIntegerSize name of
  Just size -> targetNamedTypeSize name size
  Nothing -> do
      fields <- lookupStruct name
      case fields of
        Just _ -> structSize name
        Nothing -> throwC ("unknown type: " ++ name)

targetNamedTypeSize :: String -> Int -> CompileM Int
targetNamedTypeSize name size =
  if name `elem` targetWordSizedNames
    then targetWordSize
    else pure size

targetWordSizedNames :: [String]
targetWordSizedNames =
  [ "unsigned_long"
  , "size_t"
  , "ssize_t"
  , "time_t"
  , "ptrdiff_t"
  , "intptr_t"
  , "uintptr_t"
  , "addr_t"
  ]

typeAlign :: CType -> CompileM Int
typeAlign ty = case ty of
  CArray inner _ -> typeAlign inner
  _ -> do
    size <- typeSize ty
    pure (if size >= 8 then 8 else if size >= 4 then 4 else if size >= 2 then 2 else 1)

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
aggregateSize isUnion fields = do
  layouts <- aggregateFieldLayouts isUnion fields
  aggregateLayoutSize isUnion fields layouts

-- SysV/GNU aggregates allocate bit-fields from a bit cursor.  A field may use
-- the remainder of its declared type's allocation unit, even when that unit
-- also contains a smaller preceding field.  It moves to the next unit only
-- when the value would cross that unit's boundary.  This is why a plain
-- byte followed by an unsigned one-bit field can occupy byte 0 and bit 8 of
-- the same four-byte allocation unit without overlapping.
aggregateFieldLayouts :: Bool -> [Field] -> CompileM [FieldLayout]
aggregateFieldLayouts isUnion fields =
  if isUnion then unionFieldLayouts fields else structFieldLayouts 0 fields

structFieldLayouts :: Int -> [Field] -> CompileM [FieldLayout]
structFieldLayouts bitCursor fields = case fields of
  [] -> pure []
  Field ty name bitWidthExpr:rest -> case bitWidthExpr of
    Nothing -> do
      align <- typeAlign ty
      size <- typeSize ty
      let offset = alignUp (bitsToBytes bitCursor) align
      tailLayouts <- structFieldLayouts ((offset + size) * 8) rest
      pure (FieldLayout ty name offset Nothing : tailLayouts)
    Just widthExpr -> do
      width <- checkedBitFieldWidth ty name widthExpr
      unitSize <- typeSize ty
      let unitBits = unitSize * 8
      if width == 0
        then structFieldLayouts (alignUp bitCursor unitBits) rest
        else do
          let currentUnit = (bitCursor `div` unitBits) * unitBits
          let fieldBit = if bitCursor + width <= currentUnit + unitBits
                         then bitCursor
                         else alignUp bitCursor unitBits
          let unitStart = (fieldBit `div` unitBits) * unitBits
          tailLayouts <- structFieldLayouts (fieldBit + width) rest
          pure (FieldLayout ty name (unitStart `div` 8)
                  (Just (fieldBit - unitStart, width)) : tailLayouts)

unionFieldLayouts :: [Field] -> CompileM [FieldLayout]
unionFieldLayouts fields = case fields of
  [] -> pure []
  Field ty name bitWidthExpr:rest -> do
    bitRange <- case bitWidthExpr of
      Nothing -> pure Nothing
      Just widthExpr -> do
        width <- checkedBitFieldWidth ty name widthExpr
        -- Preserve zero-width fields as bit-fields so they neither occupy
        -- union storage nor consume an initializer expression.
        pure (Just (0, width))
    tailLayouts <- unionFieldLayouts rest
    pure (FieldLayout ty name 0 bitRange : tailLayouts)

checkedBitFieldWidth :: CType -> String -> Expr -> CompileM Int
checkedBitFieldWidth ty name widthExpr = do
  integer <- isIntegerTypeM ty
  unless integer (throwC "bit-field has non-integer type")
  width <- constExprValue widthExpr
  size <- typeSize ty
  when (width < 0 || width > size * 8)
    (throwC "bit-field width exceeds its declared type")
  when (width == 0 && name /= "")
    (throwC "named bit-field has zero width")
  pure width

bitsToBytes :: Int -> Int
bitsToBytes bits = (bits + 7) `div` 8

aggregateLayoutSize :: Bool -> [Field] -> [FieldLayout] -> CompileM Int
aggregateLayoutSize isUnion fields layouts = do
  maxAlign <- aggregateAlignment fields
  used <- if isUnion then unionLayoutExtent layouts else structLayoutExtent layouts
  pure (alignUp used maxAlign)

aggregateAlignment :: [Field] -> CompileM Int
aggregateAlignment fields = case fields of
  [] -> pure 1
  Field ty _ bitWidthExpr:rest -> do
    restAlign <- aggregateAlignment rest
    align <- case bitWidthExpr of
      Just widthExpr -> do
        width <- checkedBitFieldWidth ty "" widthExpr
        if width == 0 then pure 1 else typeAlign ty
      Nothing -> typeAlign ty
    pure (max align restAlign)

structLayoutExtent :: [FieldLayout] -> CompileM Int
structLayoutExtent layouts = case layouts of
  [] -> pure 0
  FieldLayout ty _ offset bitRange:rest -> do
    fieldEnd <- case bitRange of
      Nothing -> do
        size <- typeSize ty
        pure (offset + size)
      Just (shift, width) -> pure (offset + bitsToBytes (shift + width))
    restEnd <- structLayoutExtent rest
    pure (max fieldEnd restEnd)

unionLayoutExtent :: [FieldLayout] -> CompileM Int
unionLayoutExtent layouts = case layouts of
  [] -> pure 0
  FieldLayout ty _ _ bitRange:rest -> do
    fieldSize <- case bitRange of
      Nothing -> typeSize ty
      Just (_, width) -> if width == 0 then pure 0 else typeSize ty
    restSize <- unionLayoutExtent rest
    pure (max fieldSize restSize)

alignUp :: Int -> Int -> Int
alignUp offset align =
  let remnant = offset `mod` align
  in if remnant == 0 then offset else offset + align - remnant

globalData :: CType -> Maybe Expr -> CompileM [DataValue]
globalData ty initExpr = do
  values <- globalDataValue ty initExpr
  size <- initializedSize ty values initExpr
  padDataTarget size values

initializedSize :: CType -> [DataValue] -> Maybe Expr -> CompileM Int
initializedSize ty values initExpr = case ty of
  CArray inner count -> case count of
    Nothing -> initializedUnboundedArraySize inner values initExpr
    Just _ -> typeSize ty
  _ -> typeSize ty

initializedUnboundedArraySize :: CType -> [DataValue] -> Maybe Expr -> CompileM Int
initializedUnboundedArraySize inner values initExpr = case initExpr of
  Just expr -> case expr of
    EInitList _ -> dataSizeTarget values
    EString _ -> case inner of
      CChar -> dataSizeTarget values
      _ -> typeSize (CArray inner Nothing)
    _ -> typeSize (CArray inner Nothing)
  Nothing -> typeSize (CArray inner Nothing)

globalDataValue :: CType -> Maybe Expr -> CompileM [DataValue]
globalDataValue ty initExpr = case initExpr of
  Nothing -> zeroDataForType ty
  Just expr -> globalDataExpr ty expr

zeroDataForType :: CType -> CompileM [DataValue]
zeroDataForType ty = do
  size <- typeSize ty
  pure (zeroData size)

globalDataExpr :: CType -> Expr -> CompileM [DataValue]
globalDataExpr ty expr = case expr of
  EInitList exprs -> globalInitListData ty exprs
  EString text -> globalStringData ty text
  EInt text -> do
    value <- integerLiteralValue text
    scalarData ty value
  EFloat text -> scalarFloatData ty text
  EChar text -> scalarData ty (charValue text)
  ECast _ value -> globalDataValue ty (Just value)
  EUnary "&" value -> globalAddressExprData ty value
  EUnary "*" value -> globalFunctionDesignatorData ty value
  EVar name -> globalVarData ty name
  _ -> do
    value <- constExprValue expr
    scalarData ty value

globalFunctionDesignatorData :: CType -> Expr -> CompileM [DataValue]
globalFunctionDesignatorData ty value = do
  mty <- exprType value
  case mty of
    Just (CFunc _ _) -> globalDataValue ty (Just value)
    _ -> do
      n <- constExprValue (EUnary "*" value)
      scalarData ty n

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
      n <- constExprValue bound
      elemSize <- typeSize inner
      padDataTarget (n * elemSize) items

globalAggregateInitData :: CType -> [Expr] -> CompileM [DataValue]
globalAggregateInitData ty exprs = do
  aggregate <- aggregateFields ty
  case aggregate of
    Just aggregateInfo -> case aggregateInfo of
      (False, fields) -> globalStructData fields exprs
      (True, fields) -> globalUnionData fields exprs
    Nothing -> zeroDataForType ty

globalStringData :: CType -> String -> CompileM [DataValue]
globalStringData ty text = case ty of
  CArray CChar count -> do
    size <- stringDataSize count text
    padDataTarget size (map DByte (stringBytes text))
  _ -> if isPointerType ty
    then do
      dataLabel <- freshDataLabel
      addDataItem (DataItem dataLabel (map DByte (stringBytes text)))
      pure [DAddress dataLabel 0]
    else do
      value <- constExprValue (EString text)
      scalarData ty value

stringDataSize :: Maybe Expr -> String -> CompileM Int
stringDataSize count text = case count of
  Nothing -> pure (length (stringBytes text))
  Just bound -> constExprValue bound

globalAddressExprData :: CType -> Expr -> CompileM [DataValue]
globalAddressExprData ty value = do
  resolved <- resolveGlobalAddressExpr value
  case resolved of
    Just address -> case address of
      GlobalAddress label offset -> pure [DAddress label offset]
    Nothing -> do
      n <- constExprValue (EUnary "&" value)
      scalarData ty n

data GlobalAddress = GlobalAddress String Int

resolveGlobalAddressExpr :: Expr -> CompileM (Maybe GlobalAddress)
resolveGlobalAddressExpr expr = case expr of
  EVar name -> do
    label <- globalAddressLabel name
    pure (Just (GlobalAddress label 0))
  ECast _ value ->
    resolveGlobalAddressExpr value
  EIndex base index -> do
    baseAddress <- resolveGlobalAddressExpr base
    case baseAddress of
      Nothing -> pure Nothing
      Just address -> do
        elemTy <- indexedElementType base
        elemSize <- typeSize elemTy
        indexValue <- constExprValue index
        pure (Just (addGlobalAddressOffset (indexValue * elemSize) address))
  EMember base field -> do
    baseAddress <- resolveGlobalAddressExpr base
    case baseAddress of
      Nothing -> pure Nothing
      Just address -> do
        baseTy <- exprType base
        knownBaseTy <- requireMaybeType "member base has unknown type" baseTy
        (_, fieldOffsetBytes, bitRange) <- memberInfo (Just (CPtr knownBaseTy)) field
        case bitRange of
          Just _ -> throwC "cannot take the address of a bit-field"
          Nothing -> pure ()
        pure (Just (addGlobalAddressOffset fieldOffsetBytes address))
  _ -> pure Nothing

addGlobalAddressOffset :: Int -> GlobalAddress -> GlobalAddress
addGlobalAddressOffset extra address = case address of
  GlobalAddress label offset -> GlobalAddress label (offset + extra)

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
  layouts <- aggregateFieldLayouts False fields
  size <- aggregateLayoutSize False fields layouts
  globalLayoutsData size layouts exprs

data DataChunk = DataChunk Int [DataValue]

globalLayoutsData :: Int -> [FieldLayout] -> [Expr] -> CompileM [DataValue]
globalLayoutsData size layouts exprs = do
  (chunks, patches) <- globalLayoutInitializers layouts exprs
  renderAggregateData size 0 chunks patches

globalLayoutInitializers :: [FieldLayout] -> [Expr] -> CompileM ([DataChunk], [(Int, Int)])
globalLayoutInitializers layouts exprs = case layouts of
  [] -> pure ([], [])
  FieldLayout fieldTy name offset bitRange:rest ->
    if name == "" && hasBitRange bitRange
      then globalLayoutInitializers rest exprs
      else case exprs of
        [] -> pure ([], [])
        expr:exprRest -> do
          (restChunks, restPatches) <- globalLayoutInitializers rest exprRest
          case bitRange of
            Nothing -> do
              fieldSize <- typeSize fieldTy
              fieldData <- globalDataValue fieldTy (Just expr)
              padded <- padDataTarget fieldSize fieldData
              pure (DataChunk offset padded : restChunks, restPatches)
            Just (bitOffset, width) -> do
              value <- constExprValue expr
              let patches = addBitFieldPatches offset bitOffset width value restPatches
              pure (restChunks, patches)

addBitFieldPatches :: Int -> Int -> Int -> Int -> [(Int, Int)] -> [(Int, Int)]
addBitFieldPatches byteOffset bitOffset width value patches =
  addBits 0 negative magnitude patches
  where
    negative = value < 0
    -- Extract only from a nonnegative magnitude so the generated compiler
    -- does not depend on whether its C runtime rounds negative division and
    -- remainder like Haskell.  For a negative value, -(value + 1) is the
    -- bitwise complement magnitude and also avoids overflowing at minBound.
    magnitude = if negative then negate (value + 1) else value
    addBits bit complementBits remaining current =
      if bit >= width
        then current
        else
          let absoluteBit = byteOffset * 8 + bitOffset + bit
              byte = absoluteBit `div` 8
              bitInByte = absoluteBit `mod` 8
              magnitudeBit = remaining `mod` 2
              bitIsSet = if complementBits
                         then magnitudeBit == 0
                         else magnitudeBit == 1
              bitValue = if bitIsSet then 2 ^ bitInByte else 0
          in addBits (bit + 1) complementBits (remaining `div` 2)
               (mergeBytePatch byte bitValue current)

mergeBytePatch :: Int -> Int -> [(Int, Int)] -> [(Int, Int)]
mergeBytePatch offset value patches = case patches of
  [] -> [(offset, value)]
  (existingOffset, existingValue):rest ->
    if offset == existingOffset
      then (offset, existingValue + value):rest
      else (existingOffset, existingValue):mergeBytePatch offset value rest

renderAggregateData :: Int -> Int -> [DataChunk] -> [(Int, Int)] -> CompileM [DataValue]
renderAggregateData size offset chunks patches =
  if offset >= size
    then pure []
    else case chunks of
      DataChunk chunkOffset values:rest | chunkOffset == offset -> do
        used <- dataSizeTarget values
        tailValues <- renderAggregateData size (offset + used) rest patches
        pure (values ++ tailValues)
      _ -> do
        let value = lookupBytePatch offset patches
        tailValues <- renderAggregateData size (offset + 1) chunks patches
        pure (DByte value : tailValues)

lookupBytePatch :: Int -> [(Int, Int)] -> Int
lookupBytePatch offset patches = case patches of
  [] -> 0
  (candidate, value):rest ->
    if candidate == offset then value else lookupBytePatch offset rest

globalUnionData :: [Field] -> [Expr] -> CompileM [DataValue]
globalUnionData fields exprs = do
  layouts <- aggregateFieldLayouts True fields
  size <- aggregateLayoutSize True fields layouts
  case exprs of
    [] -> pure (zeroData size)
    _ -> globalUnionLayoutsData size layouts exprs

globalUnionLayoutsData :: Int -> [FieldLayout] -> [Expr] -> CompileM [DataValue]
globalUnionLayoutsData size layouts exprs = case layouts of
  [] -> pure (zeroData size)
  layout@(FieldLayout _ name _ bitRange):rest ->
    if name == "" && hasBitRange bitRange
      then globalUnionLayoutsData size rest exprs
      else globalLayoutsData size [layout] exprs

isAggregateTypeM :: CType -> CompileM Bool
isAggregateTypeM ty = case ty of
  CArray _ _ -> pure True
  CNamed _ -> do
    aggregate <- aggregateFields ty
    pure (maybe False (const True) aggregate)
  _ -> pure (isAggregateType ty)

-- Arrays are aggregate objects for storage, but decay to pointers when used
-- as call arguments.  Only structs and unions require a by-value call copy.
isRecordTypeM :: CType -> CompileM Bool
isRecordTypeM ty = case ty of
  CStruct _ -> pure True
  CUnion _ -> pure True
  CStructNamed _ _ -> pure True
  CUnionNamed _ _ -> pure True
  CStructDef _ -> pure True
  CUnionDef _ -> pure True
  CNamed _ -> do
    aggregate <- aggregateFields ty
    pure (maybe False (const True) aggregate)
  _ -> pure False

scalarData :: CType -> Int -> CompileM [DataValue]
scalarData ty value = do
  size <- typeSize ty
  pure (map DByte (intBytes size value))

scalarFloatData :: CType -> String -> CompileM [DataValue]
scalarFloatData ty text = do
  size <- typeSize ty
  pure (map DByte (floatLiteralBytes size text))

padDataTarget :: Int -> [DataValue] -> CompileM [DataValue]
padDataTarget size values = do
  used <- dataSizeTarget values
  if used >= size
    then takeDataTarget size values
    else pure (values ++ zeroData (size - used))

takeDataTarget :: Int -> [DataValue] -> CompileM [DataValue]
takeDataTarget size values =
  if size <= 0 then pure [] else case values of
    [] -> pure []
    DByte byte:rest -> do
      tailValues <- takeDataTarget (size - 1) rest
      pure (DByte byte : tailValues)
    DAddress label offset:rest -> do
      word <- targetWordSize
      if size >= word
        then do
          tailValues <- takeDataTarget (size - word) rest
          pure (DAddress label offset : tailValues)
        else pure (zeroData size)
    DLabel _:rest ->
      takeDataTarget size rest

dataSizeTarget :: [DataValue] -> CompileM Int
dataSizeTarget values = case values of
  [] -> pure 0
  DByte _:rest -> do
    n <- dataSizeTarget rest
    pure (n + 1)
  DAddress _ _:rest -> do
    word <- targetWordSize
    n <- dataSizeTarget rest
    pure (n + word)
  DLabel _:rest ->
    dataSizeTarget rest

globalAddressData :: String -> CompileM [DataValue]
globalAddressData name = do
  label <- globalAddressLabel name
  pure [DAddress label 0]

globalAddressLabel :: String -> CompileM String
globalAddressLabel name = do
  resolved <- resolveSymbolName name
  function <- lookupFunction name
  pure (if function then "FUNCTION_" ++ resolved else resolved)

constExprValue :: Expr -> CompileM Int
constExprValue expr = case expr of
  EInt text -> integerLiteralValue text
  EFloat _ -> pure 0
  EChar text -> pure (charValue text)
  ESizeofType ty -> typeSize ty
  ESizeofExpr value -> sizeofExprValue value
  EAlignofType ty -> typeAlign ty
  EAlignofExpr value -> alignofExprValue value
  ECast _ (EUnary "&" (EPtrMember (ECast (CPtr ty) (EInt "0")) field)) -> do
    (_, offset, bitRange) <- memberInfo (Just (CPtr ty)) field
    case bitRange of
      Just _ -> throwC "cannot take the address of a bit-field"
      Nothing -> pure offset
  EUnary "&" (EPtrMember (ECast (CPtr ty) (EInt "0")) field) -> do
    (_, offset, bitRange) <- memberInfo (Just (CPtr ty)) field
    case bitRange of
      Just _ -> throwC "cannot take the address of a bit-field"
      Nothing -> pure offset
  EVar name -> do
    constant <- lookupConstant name
    case constant of
      Just value -> pure value
      Nothing -> case builtinConstant name of
        Just value -> pure value
        Nothing -> throwC ("unknown constant: " ++ name)
  ECast _ value -> constExprValue value
  EUnary "-" value -> do
    n <- constExprValue value
    pure (negate n)
  EUnary "+" value -> constExprValue value
  EUnary "~" value -> do
    n <- constExprValue value
    pure (negate n - 1)
  EUnary "!" value -> do
    n <- constExprValue value
    pure (if n == 0 then 1 else 0)
  EBinary "&&" left right -> do
    a <- constExprValue left
    if a == 0 then pure 0 else do
      b <- constExprValue right
      pure (boolToInt (b /= 0))
  EBinary "||" left right -> do
    a <- constExprValue left
    if a /= 0 then pure 1 else do
      b <- constExprValue right
      pure (boolToInt (b /= 0))
  EBinary op left right -> do
    a <- constExprValue left
    b <- constExprValue right
    case evalConstBinOp op a b of
      Just value -> pure value
      Nothing -> throwC ("invalid constant expression: " ++ op)
  ECond cond yes no -> do
    c <- constExprValue cond
    constExprValue (if c /= 0 then yes else no)
  EUnary op _ -> throwC ("unsupported constant expression: unary " ++ op)
  _ -> throwC ("unsupported constant expression: " ++ renderExprTag expr)

arrayBoundSize :: Maybe Expr -> CompileM Int
arrayBoundSize bound = case bound of
  Nothing -> pure 1
  Just expr -> constExprValue expr

shiftRightOp :: Expr -> CompileM BinOp
shiftRightOp expr = do
  ty <- promotedExprType expr
  pure (shiftRightOpForPromotedType ty)

shiftRightOpForType :: CType -> CompileM BinOp
shiftRightOpForType ty = do
  promoted <- promoteIntegerType ty
  pure (shiftRightOpForPromotedType promoted)

shiftRightOpForPromotedType :: CType -> BinOp
shiftRightOpForPromotedType ty = if isUnsignedType ty then IShr else ISar

comparisonOp :: String -> Expr -> Expr -> CompileM BinOp
comparisonOp op a b = do
  commonTy <- usualArithmeticType a b
  let unsigned = isUnsignedType commonTy
  pure (case (unsigned, op) of
    (False, "<") -> ILt
    (False, "<=") -> ILe
    (False, ">") -> IGt
    (False, ">=") -> IGe
    (True, "<") -> IULt
    (True, "<=") -> IULe
    (True, ">") -> IUGt
    (True, ">=") -> IUGe
    _ -> IEq)

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
  CNamed name -> case namedIntegerSize name of
    Just _ -> not (isSignedNamedInteger name)
    Nothing -> False
  _ -> False
