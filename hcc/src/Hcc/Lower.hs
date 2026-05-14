module Lower
  ( registerTypeAggregates
  , registerTypesAggregates
  , registerExternGlobals
  , registerConstants
  , registerFieldAggregates
  , lowerFunction
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

lowerFunction :: CType -> String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunction retTy name params body =
  withErrorContext ("function " ++ name)
    (withFunctionScope
      (withCurrentFunction name
        (withCurrentReturnType retTy (lowerFunctionBody name params body))))

lowerFunctionBody :: String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunctionBody name params body = do
  bid <- freshBlock
  paramInstrs <- lowerParams 0 params
  defaultTerm <- defaultReturnTerm
  blocks <- lowerStatementsFrom bid paramInstrs body defaultTerm
  pure (FunctionIr name blocks)

-- The implicit "fell off the end" terminator. void returns nothing; other
-- functions get a zero of the declared type so callers see a defined value.
defaultReturnTerm :: CompileM Terminator
defaultReturnTerm = do
  mty <- currentReturnType
  case mty of
    Just CVoid -> pure (TRet Nothing)
    _ -> pure (TRet (Just (OImm 0)))

-- Coerce a return-value operand to the current function's declared return
-- type, so `char f(){return 257;}` truncates to 1 in the caller's view per
-- C11 6.8.6.4p3.
coerceReturnOperand :: Operand -> CompileM ([Instr], Operand)
coerceReturnOperand op = do
  mty <- currentReturnType
  case mty of
    Just CVoid -> pure ([], op)
    Just ty -> coerceScalar ty op
    Nothing -> pure ([], op)

lowerStatementsFrom :: BlockId -> [Instr] -> [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerStatementsFrom bid instrs stmts defaultTerm = case stmts of
  [] -> pure [BasicBlock bid instrs defaultTerm]
  SReturn value:rest -> case value of
    Nothing -> do
      tailBlocks <- lowerUnreachableLabels rest defaultTerm
      pure (BasicBlock bid instrs (TRet Nothing) : tailBlocks)
    Just expr -> do
      if exprIsShortCircuitBoolean expr
        then do
          yesId <- freshBlock
          noId <- freshBlock
          condBlocks <- lowerConditionBlock bid instrs expr yesId noId
          tailBlocks <- lowerUnreachableLabels rest defaultTerm
          (yesCoerceInstrs, yesOp) <- coerceReturnOperand (OImm 1)
          (noCoerceInstrs, noOp) <- coerceReturnOperand (OImm 0)
          pure ( condBlocks ++
                 [ BasicBlock yesId yesCoerceInstrs (TRet (Just yesOp))
                 , BasicBlock noId noCoerceInstrs (TRet (Just noOp))
                 ] ++ tailBlocks)
        else do
          (retInstrs, op) <- lowerExpr expr
          (coerceInstrs, retOp) <- coerceReturnOperand op
          tailBlocks <- lowerUnreachableLabels rest defaultTerm
          pure (BasicBlock bid (instrs ++ retInstrs ++ coerceInstrs) (TRet (Just retOp)) : tailBlocks)
  SBlock body:rest -> do
    if null rest
      then withVarScope (lowerStatementsFrom bid instrs body defaultTerm)
      else do
        restId <- freshBlock
        bodyBlocks <- withVarScope (lowerStatementsFrom bid instrs body (TJump restId))
        restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
        pure (bodyBlocks ++ restBlocks)
  SDecl ty name initExpr:rest -> do
    declInstrs <- lowerDecl ty name initExpr
    lowerStatementsFrom bid (instrs ++ declInstrs) rest defaultTerm
  SDecls decls:rest -> do
    declInstrs <- lowerDecls decls
    lowerStatementsFrom bid (instrs ++ declInstrs) rest defaultTerm
  STypedef:rest ->
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
  SFor initExpr condExpr stepExpr body:rest -> do
    initInstrs <- maybeLowerSideEffect initExpr
    condId <- freshBlock
    bodyId <- freshBlock
    stepId <- freshBlock
    restId <- freshBlock
    condBlocks <- lowerLoopConditionBlocks condExpr condId bodyId restId
    stepInstrs <- maybeLowerSideEffect stepExpr
    bodyBlocks <- withLoopTargets restId stepId (lowerStatementsFrom bodyId [] body (TJump stepId))
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure ( BasicBlock bid (instrs ++ initInstrs) (TJump condId)
         : condBlocks ++ bodyBlocks ++
           [BasicBlock stepId stepInstrs (TJump condId)] ++
           restBlocks)
  SSwitch value body:rest -> do
    (valueInstrs, valueOp) <- lowerExpr value
    dispatchId <- freshBlock
    restId <- freshBlock
    switchBlocks <- lowerSwitch dispatchId restId valueOp body
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure (BasicBlock bid (instrs ++ valueInstrs) (TJump dispatchId) : switchBlocks ++ restBlocks)
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
    let noTarget = lowerIfNoTarget no restId noId
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
  stmt:_ -> throwC ("unsupported statement in lowering: " ++ renderStmtTag stmt)

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

lowerIfNoTarget :: [Stmt] -> BlockId -> BlockId -> BlockId
lowerIfNoTarget no restId noId =
  if null no then restId else noId

lowerIfNoBlocks :: [Stmt] -> BlockId -> BlockId -> CompileM [BasicBlock]
lowerIfNoBlocks no noId restId = case no of
  [] -> pure []
  _ -> lowerStatementsFrom noId [] no (TJump restId)

lowerUnreachableLabels :: [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerUnreachableLabels stmts defaultTerm = case stmts of
  [] -> pure []
  SLabel name:rest -> do
    target <- labelBlock name
    lowerStatementsFrom target [] rest defaultTerm
  _:rest ->
    lowerUnreachableLabels rest defaultTerm

maybeLowerSideEffect :: Maybe Expr -> CompileM [Instr]
maybeLowerSideEffect value = case value of
  Nothing -> pure []
  Just expr -> lowerSideEffect expr

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
    if isBranchComparisonOpString op
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
  let clauses = collectSwitchClauses bodyStmts
  clauseIds <- freshBlocks (length clauses)
  let clausePairs = zip clauses clauseIds
  let defaultTarget = switchDefaultTarget restId clausePairs
  let switchCasePairs = switchCases clausePairs
  dispatchBlocks <- lowerSwitchDispatch dispatchId valueOp defaultTarget switchCasePairs
  bodyBlocks <- withBreakTarget restId (lowerSwitchClauses restId clausePairs)
  pure (dispatchBlocks ++ bodyBlocks)

lowerSwitchDispatch :: BlockId -> Operand -> BlockId -> [(Expr, BlockId)] -> CompileM [BasicBlock]
lowerSwitchDispatch bid valueOp defaultTarget switchCasePairs = case switchCasePairs of
  [] -> pure [BasicBlock bid [] (TJump defaultTarget)]
  (caseExpr, target):tailCases -> do
    nextId <- switchNextDispatchTarget defaultTarget tailCases
    (caseInstrs, caseOp) <- lowerExpr caseExpr
    let block = BasicBlock bid caseInstrs (TBranchCmp IEq valueOp caseOp target nextId)
    case tailCases of
      [] -> pure [block]
      _ -> do
        restBlocks <- lowerSwitchDispatch nextId valueOp defaultTarget tailCases
        pure (block:restBlocks)

lowerSwitchClauses :: BlockId -> [(SwitchClause, BlockId)] -> CompileM [BasicBlock]
lowerSwitchClauses restId clauses = case clauses of
  [] -> pure []
  pair:rest -> case pair of
    (SwitchClause _ body, bid) -> do
      let fallthrough = switchFallthroughTarget restId rest
      bodyBlocks <- lowerStatementsFrom bid [] body (TJump fallthrough)
      restBlocks <- lowerSwitchClauses restId rest
      pure (bodyBlocks ++ restBlocks)

lowerSideEffect :: Expr -> CompileM [Instr]
lowerSideEffect expr = case expr of
  ECall (EVar name) args ->
    if isIgnoredSideEffectCall name
      then pure []
      else do
        direct <- lookupFunction name
        if direct
          then lowerDirectSideEffect name args
          else lowerIndirectSideEffect (EVar name) args
  ECall callee args -> do
    lowerIndirectSideEffect callee args
  EAssign lhs rhs ->
    lowerAssignmentInstrs lhs rhs
  EPostfix "--" target ->
    lowerIncDecInstrs False ISub target
  EPostfix "++" target ->
    lowerIncDecInstrs False IAdd target
  _ -> do
    (instrs, _) <- lowerExpr expr
    pure instrs

lowerAssignmentInstrs :: Expr -> Expr -> CompileM [Instr]
lowerAssignmentInstrs lhs rhs = do
  (instrs, _) <- lowerAssignment lhs rhs
  pure instrs

lowerIncDecInstrs :: Bool -> BinOp -> Expr -> CompileM [Instr]
lowerIncDecInstrs prefix op target = do
  (instrs, _) <- lowerIncDec prefix op target
  pure instrs

lowerDirectSideEffect :: String -> [Expr] -> CompileM [Instr]
lowerDirectSideEffect name args = do
  lowered <- lowerExprs args
  pure (lowerExprResultsInstrs lowered ++ [ICall Nothing name (lowerExprResultsOps lowered)])

lowerIndirectSideEffect :: Expr -> [Expr] -> CompileM [Instr]
lowerIndirectSideEffect callee args = do
  (calleeInstrs, calleeOp) <- lowerExpr callee
  lowered <- lowerExprs args
  pure (calleeInstrs ++ lowerExprResultsInstrs lowered ++ [ICallIndirect Nothing calleeOp (lowerExprResultsOps lowered)])

lowerExprResultsInstrs :: [([Instr], Operand)] -> [Instr]
lowerExprResultsInstrs = concatMap fst

lowerExprResultsOps :: [([Instr], Operand)] -> [Operand]
lowerExprResultsOps = map snd

lowerDecls :: [(CType, String, Maybe Expr)] -> CompileM [Instr]
lowerDecls decls = case decls of
  [] -> pure []
  decl:rest -> case decl of
    (ty, name, initExpr) -> do
      instrs <- lowerDecl ty name initExpr
      tailInstrs <- lowerDecls rest
      pure (instrs ++ tailInstrs)

lowerDecl :: CType -> String -> Maybe Expr -> CompileM [Instr]
lowerDecl ty name initExpr = do
  aggregateStorage <- isAggregateTypeM ty
  temp <- freshTemp
  bindVar name temp ty
  if aggregateStorage
    then lowerAggregateDecl ty temp initExpr
    else lowerScalarDecl ty temp initExpr

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
      lowerAggregateDeclTemplate ty temp initExpr label
    Nothing ->
      lowerAggregateDeclRuntime ty temp initExpr

lowerAggregateDeclTemplate :: CType -> Temp -> Maybe Expr -> String -> CompileM [Instr]
lowerAggregateDeclTemplate ty temp initExpr label = do
  copyInstrs <- copyObject (OTemp temp) (OGlobal label) ty
  runtimeInstrs <- lowerAggregateInitWrites (OTemp temp) ty initExpr
  pure (copyInstrs ++ runtimeInstrs)

lowerAggregateDeclRuntime :: CType -> Temp -> Maybe Expr -> CompileM [Instr]
lowerAggregateDeclRuntime ty temp initExpr = case initExpr of
  -- C11 6.7.9p21: members not provided in the initializer list must be
  -- initialized as if they had static storage duration (i.e., zero). The
  -- IAlloca slot is uninitialized, so zero the whole object before
  -- overlaying the supplied field writes.
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
lowerUnionInitWrites dst fields exprs = case fields of
  [] -> pure []
  field:_ -> case field of
    Field fieldTy _ -> case exprs of
      expr:_ -> lowerAggregateElementWrite dst 0 fieldTy expr
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
lowerStructInitWrites dst offset fields exprs = case fields of
  [] -> pure []
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
  _ -> do
    (exprInstrs, op) <- lowerExpr expr
    copyInstrs <- copyObject addr op fieldTy
    pure (exprInstrs ++ copyInstrs)

lowerAggregateElementScalarWrite :: Operand -> CType -> Expr -> CompileM [Instr]
lowerAggregateElementScalarWrite addr fieldTy expr = do
  (exprInstrs, op) <- lowerExpr expr
  (coerceInstrs, coerceOp) <- coerceScalar fieldTy op
  store <- storeInstr fieldTy addr coerceOp
  pure (exprInstrs ++ coerceInstrs ++ [store])

registerExternGlobals :: [(CType, String)] -> CompileM ()
registerExternGlobals globals = case globals of
  [] -> pure ()
  global:rest -> case global of
    (ty, name) -> do
      registerTypeAggregates ty
      bindGlobal name ty
      registerExternGlobals rest

registerConstants :: [(String, Int)] -> CompileM ()
registerConstants constants = case constants of
  [] -> pure ()
  constant:rest -> case constant of
    (name, value) -> do
      bindConstant name value
      registerConstants rest

registerFieldAggregates :: [Field] -> CompileM ()
registerFieldAggregates fields = case fields of
  [] -> pure ()
  Field ty _:rest -> do
    registerTypeAggregates ty
    registerFieldAggregates rest

registerTypeAggregates :: CType -> CompileM ()
registerTypeAggregates ty = case ty of
  CPtr inner -> registerTypeAggregates inner
  CArray inner _ -> registerTypeAggregates inner
  CFunc ret params -> do
    registerTypeAggregates ret
    registerTypesAggregates params
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
  _ -> pure ()

registerTypesAggregates :: [CType] -> CompileM ()
registerTypesAggregates types = case types of
  [] -> pure ()
  ty:rest -> do
    registerTypeAggregates ty
    registerTypesAggregates rest

lowerExpr :: Expr -> CompileM ([Instr], Operand)
lowerExpr expr = case expr of
  EInt text ->
    pure ([], intConstOperand text)
  EFloat text ->
    pure ([], floatConstOperand text)
  EChar text ->
    pure ([], OImm (charValue text))
  EString text -> do
    dataLabel <- freshDataLabel
    addDataItem (DataItem dataLabel (bytesData (stringBytes text)))
    pure ([], OGlobal dataLabel)
  EVar name -> lowerVarExpr name
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
  ECast ty x -> do
    (a, op) <- lowerExpr x
    (coerceInstrs, coerceOp) <- coerceScalar ty op
    pure (a ++ coerceInstrs, coerceOp)
  ESizeofType ty -> do
    size <- typeSize ty
    temp <- freshTemp
    pure ([IConst temp size], OTemp temp)
  ESizeofExpr value -> do
    mty <- exprType value
    ty <- requireMaybeType "sizeof expression has unknown type" mty
    size <- typeSize ty
    temp <- freshTemp
    pure ([IConst temp size], OTemp temp)
  ECond cond yes no -> do
    (ci, co) <- lowerExpr cond
    (yi, yo) <- lowerExpr yes
    (ni, noOp) <- lowerExpr no
    out <- freshTemp
    pure ([ICond out ci co yi yo ni noOp], OTemp out)
  EBinary "," a b -> do
    ai <- lowerSideEffect a
    (bi, bo) <- lowerExpr b
    pure (ai ++ bi, bo)
  EBinary "&&" a b ->
    lowerLogicalAnd a b
  EBinary "||" a b ->
    lowerLogicalOr a b
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
  ECall (EVar name) args -> do
    direct <- lookupFunction name
    if direct
      then lowerDirectCallExpr name args
      else lowerIndirectCall (EVar name) args
  ECall callee args -> do
    lowerIndirectCall callee args
  EAssign lhs rhs ->
    lowerAssignment lhs rhs
  EPostfix "--" target ->
    lowerIncDec False ISub target
  EPostfix "++" target ->
    lowerIncDec False IAdd target
  _ -> throwC ("unsupported expression in lowering: " ++ renderExprTag expr)

lowerVarExpr :: String -> CompileM ([Instr], Operand)
lowerVarExpr name =
  if isFunctionNameMacro name
    then lowerFunctionNameMacro
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
  constant <- lookupConstant name
  case constant of
    Just value -> pure ([], OImm value)
    Nothing -> lowerNonConstantVarExpr name

lowerNonConstantVarExpr :: String -> CompileM ([Instr], Operand)
lowerNonConstantVarExpr name = do
  local <- lookupVarMaybe name
  case local of
    Just temp -> do
      mty <- lookupVarType name
      ty <- requireMaybeType ("unknown local type: " ++ name) mty
      coerceScalar ty (OTemp temp)
    Nothing -> lowerNonLocalVarExpr name

lowerNonLocalVarExpr :: String -> CompileM ([Instr], Operand)
lowerNonLocalVarExpr name = do
  function <- lookupFunction name
  if function
    then pure ([], OFunction name)
    else lowerGlobalVarExpr name

lowerGlobalVarExpr :: String -> CompileM ([Instr], Operand)
lowerGlobalVarExpr name = do
  globalTy <- lookupGlobalType name
  case globalTy of
    Just ty -> lowerTypedGlobalVarExpr name ty
    Nothing -> throwC ("unknown identifier: " ++ name)

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
lowerBinaryExpr op a b =
  if isComparisonOpString op
    then lowerComparisonExpr op a b
    else if op == "/" || op == "%"
      then do
        commonTy <- usualArithmeticType a b
        let iop = if isUnsignedType commonTy
              then if op == "/" then IUDiv else IUMod
              else if op == "/" then IDiv else IMod
        lowerPlainBin iop a b
      else case lowerBinOp op of
        Just iop -> do
          if op == "<<"
            then lowerShiftExpr op a b
            else lowerPlainBin iop a b
        Nothing -> throwC ("unsupported binary operator in lowering: " ++ op)

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
  lowered <- lowerExprs args
  out <- freshTemp
  let instrs = lowerExprResultsInstrs lowered
  let ops = lowerExprResultsOps lowered
  pure (instrs ++ [ICall (Just out) name ops], OTemp out)

lowerExprs :: [Expr] -> CompileM [([Instr], Operand)]
lowerExprs args = case args of
  [] -> pure []
  x:xs -> do
    first <- lowerExpr x
    rest <- lowerExprs xs
    pure (first:rest)

lowerIndirectCall :: Expr -> [Expr] -> CompileM ([Instr], Operand)
lowerIndirectCall callee args = do
  (calleeInstrs, calleeOp) <- lowerExpr callee
  lowered <- lowerExprs args
  out <- freshTemp
  pure (calleeInstrs ++ lowerExprResultsInstrs lowered ++ [ICallIndirect (Just out) calleeOp (lowerExprResultsOps lowered)], OTemp out)

lowerLogicalAnd :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerLogicalAnd = lowerShortCircuit True

lowerLogicalOr :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerLogicalOr = lowerShortCircuit False

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
  case pointerElementType aty of
    Just elemTy -> lowerPointerOffset IAdd a b elemTy
    Nothing -> case pointerElementType bty of
      Just elemTy -> lowerPointerOffset IAdd b a elemTy
      Nothing -> lowerPlainBin IAdd a b

lowerSubExpr :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerSubExpr a b = do
  aty <- exprType a
  bty <- exprType b
  case pointerElementType aty of
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
  scaled <- freshTemp
  out <- freshTemp
  pure (ptrInstrs ++ oi ++ [IBin scaled IMul oo (OImm size), IBin out op po (OTemp scaled)], OTemp out)

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
  (coerceInstrs, coerceOp) <- coerceScalar targetTy rhsOp
  writeInstrs <- writeLValue lvalue coerceOp
  pure (lhsInstrs ++ rhsInstrs ++ coerceInstrs ++ writeInstrs, coerceOp)

lowerIncDec :: Bool -> BinOp -> Expr -> CompileM ([Instr], Operand)
lowerIncDec prefix op target = do
  (lvInstrs, lvalue) <- lowerLValue target
  (readInstrs, current) <- readLValue lvalue
  old <- freshTemp
  out <- freshTemp
  step <- incDecStep target
  writeInstrs <- writeLValue lvalue (OTemp out)
  let opInstrs = [IBin old IAdd current (OImm 0), IBin out op (OTemp old) (OImm step)]
  pure (lvInstrs ++ readInstrs ++ opInstrs ++ writeInstrs, if prefix then OTemp out else OTemp old)

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

lValueType :: LValue -> CompileM CType
lValueType lvalue = case lvalue of
  LLocal _ ty -> pure ty
  LAddress _ ty -> pure ty

coerceMaybeScalar :: Maybe CType -> Operand -> CompileM ([Instr], Operand)
coerceMaybeScalar mty op = case mty of
  Just ty -> coerceScalar ty op
  Nothing -> pure ([], op)

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
      let width = if remaining >= word then word else if remaining >= 4 then 4 else 1
      dstResult <- offsetAddress dst offset
      let dstInstrs = fst dstResult
      let dstAddr = snd dstResult
      let store = if width == 8 then IStore64 dstAddr (OImm 0) else if width == 4 then IStore32 dstAddr (OImm 0) else IStore8 dstAddr (OImm 0)
      rest <- zeroObjectBytes dst (offset + width) (remaining - width)
      pure (dstInstrs ++ [store] ++ rest)

copyObjectBytes :: Operand -> Operand -> Int -> Int -> CompileM [Instr]
copyObjectBytes dst src offset remaining =
  if remaining <= 0
    then pure []
    else do
      word <- targetWordSize
      let width = if remaining >= word then word else if remaining >= 4 then 4 else 1
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
  local <- lookupVarMaybe name
  case local of
    Nothing -> do
      function <- lookupFunction name
      if function
        then pure ([], OFunction name)
        else lowerNonFunctionAddress (EVar name)
    Just _ ->
      lowerNonFunctionAddress (EVar name)

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
        pure ([], LAddress (OGlobal name) knownTy)
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
    addr <- freshTemp
    pure (baseInstrs ++ [IBin addr IAdd baseOp (OImm offset)], LAddress (OTemp addr) fieldTy)
  EMember base field -> do
    (baseInstrs, baseAddr) <- lowerLValueAddress base
    baseTy <- exprType base
    knownBaseTy <- requireMaybeType "member base has unknown type" baseTy
    (fieldTy, offset) <- memberInfo (Just (CPtr knownBaseTy)) field
    addr <- freshTemp
    pure (baseInstrs ++ [IBin addr IAdd baseAddr (OImm offset)], LAddress (OTemp addr) fieldTy)
  _ -> throwC ("unsupported lvalue: " ++ renderExprTag target)

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
  EInt _ -> pure (Just CInt)
  EFloat text -> pure (Just (floatLiteralType text))
  EChar _ -> pure (Just CInt)
  EString _ -> pure (Just (CPtr CChar))
  ESizeofType _ -> pure (Just CInt)
  ESizeofExpr _ -> pure (Just CInt)
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
              Nothing -> lookupGlobalType name
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
      Just (CPtr ty) -> Just ty
      Just (CArray ty _) -> Just ty
      _ -> Nothing)
  EUnary "&" value -> do
    mty <- exprType value
    pure (maybePtrType mty)
  EIndex base _ -> do
    mty <- exprType base
    pure (case mty of
      Just (CPtr ty) -> Just ty
      Just (CArray ty _) -> Just ty
      _ -> Nothing)
  EPtrMember base field -> do
    baseTy <- exprType base
    info <- memberInfoMaybe baseTy field
    pure (maybeMemberType info)
  EMember base field -> do
    baseTy <- exprType base
    knownBaseTy <- requireMaybeType "member base has unknown type" baseTy
    info <- memberInfoMaybe (Just (CPtr knownBaseTy)) field
    pure (maybeMemberType info)
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
    pure (case (yesTy, noTy) of
      (Just ty, Nothing) -> Just ty
      (Nothing, Just ty) -> Just ty
      (Just ty, Just _) -> Just ty
      _ -> Nothing)
  EAssign lhs _ -> exprType lhs
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

promoteMaybeIntegerType :: Maybe CType -> CompileM (Maybe CType)
promoteMaybeIntegerType mty = case mty of
  Nothing -> pure Nothing
  Just ty -> do
    promoted <- promoteIntegerType ty
    pure (Just promoted)

maybePtrType :: Maybe CType -> Maybe CType
maybePtrType mty = case mty of
  Nothing -> Nothing
  Just ty -> Just (CPtr ty)

functionResultType :: CType -> Maybe CType
functionResultType ty = case ty of
  CFunc ret _ -> Just ret
  CPtr inner -> functionResultType inner
  _ -> Nothing

isFunctionNameMacro :: String -> Bool
isFunctionNameMacro name =
  name `elem` ["__func__", "__FUNCTION__", "__PRETTY_FUNCTION__"]

maybeMemberType :: Maybe (CType, Int) -> Maybe CType
maybeMemberType info = case info of
  Nothing -> Nothing
  Just pair -> case pair of
    (ty, _) -> Just ty

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
      (isUnion, fields) -> fieldOffset isUnion field 0 fields

aggregateCacheName :: CType -> Maybe String
aggregateCacheName ty = case ty of
  CStruct name -> Just name
  CUnion name -> Just name
  CStructNamed name _ -> Just name
  CUnionNamed name _ -> Just name
  CNamed name -> Just name
  _ -> Nothing

fieldOffset :: Bool -> String -> Int -> [Field] -> CompileM (Maybe (CType, Int))
fieldOffset isUnion field offset fields = case fields of
  [] -> pure Nothing
  item:rest -> case item of
    Field ty name -> do
      align <- typeAlign ty
      let aligned = alignUp offset align
      if name == field
        then pure (Just (ty, unionOffset isUnion aligned))
        else do
          size <- typeSize ty
          nested <- anonymousMemberInfoForName isUnion aligned ty name field
          case nested of
            Just info -> pure (Just info)
            Nothing -> fieldOffset isUnion field (aligned + size) rest

unionOffset :: Bool -> Int -> Int
unionOffset isUnion aligned =
  if isUnion then 0 else aligned

anonymousMemberInfoForName :: Bool -> Int -> CType -> String -> String -> CompileM (Maybe (CType, Int))
anonymousMemberInfoForName isUnion aligned ty name field =
  if name == ""
    then anonymousMemberInfo (unionOffset isUnion aligned) ty field
    else pure Nothing

anonymousMemberInfo :: Int -> CType -> String -> CompileM (Maybe (CType, Int))
anonymousMemberInfo baseOffset ty field = do
  aggregate <- aggregateFields ty
  case aggregate of
    Nothing -> pure Nothing
    Just aggregateInfo -> case aggregateInfo of
      (isUnion, fields) -> nestedFieldOffset baseOffset isUnion field 0 fields

nestedFieldOffset :: Int -> Bool -> String -> Int -> [Field] -> CompileM (Maybe (CType, Int))
nestedFieldOffset baseOffset isUnion field offset fields = case fields of
  [] -> pure Nothing
  item:rest -> case item of
    Field fieldTy name -> do
      align <- typeAlign fieldTy
      let aligned = alignUp offset align
      let memberOffset = baseOffset + unionOffset isUnion aligned
      if name == field
        then pure (Just (fieldTy, memberOffset))
        else do
          size <- typeSize fieldTy
          nested <- anonymousMemberInfoForName False memberOffset fieldTy name field
          case nested of
            Just info -> pure (Just info)
            Nothing -> nestedFieldOffset baseOffset isUnion field (aligned + size) rest

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
  leftTy <- promotedExprType left
  rightTy <- promotedExprType right
  if isFloatingType leftTy || isFloatingType rightTy
    then pure (usualFloatingType leftTy rightTy)
    else do
      leftSize <- typeSize leftTy
      rightSize <- typeSize rightTy
      let size = max leftSize rightSize
      let unsigned = isUnsignedType leftTy || isUnsignedType rightTy
      pure (case (size >= 8, unsigned) of
        (True, True) -> CUnsignedLongLong
        (True, False) -> CLongLong
        (False, True) -> CUnsigned
        (False, False) -> CInt)

isFloatingType :: CType -> Bool
isFloatingType ty = case ty of
  CFloat -> True
  CDouble -> True
  CLongDouble -> True
  _ -> False

usualFloatingType :: CType -> CType -> CType
usualFloatingType leftTy rightTy =
  if isLongDoubleType leftTy || isLongDoubleType rightTy
    then CLongDouble
    else if isDoubleType leftTy || isDoubleType rightTy
      then CDouble
      else CFloat

isLongDoubleType :: CType -> Bool
isLongDoubleType ty = case ty of
  CLongDouble -> True
  _ -> False

isDoubleType :: CType -> Bool
isDoubleType ty = case ty of
  CDouble -> True
  _ -> False

promotedExprType :: Expr -> CompileM CType
promotedExprType expr = case expr of
  EInt text ->
    if intLiteralIsUnsigned text then pure CUnsigned else pure CInt
  EFloat text ->
    pure (floatLiteralType text)
  _ -> do
    mty <- exprType expr
    ty <- requireMaybeType ("expression has unknown type: " ++ renderExprTag expr) mty
    promoteIntegerType ty

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
  CEnum _ -> pure 4
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
  EInt text -> scalarData ty (parseInt text)
  EFloat text -> scalarFloatData ty text
  EChar text -> scalarData ty (charValue text)
  ECast _ value -> globalDataValue ty (Just value)
  EUnary "&" value -> globalAddressExprData ty value
  EVar name -> globalVarData ty name
  _ -> do
    value <- constExprValue expr
    scalarData ty value

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
    padDataTarget size (bytesData (stringBytes text))
  _ -> if isPointerType ty
    then do
      dataLabel <- freshDataLabel
      addDataItem (DataItem dataLabel (bytesData (stringBytes text)))
      pure [DAddress dataLabel]
    else do
      value <- constExprValue (EString text)
      scalarData ty value

stringDataSize :: Maybe Expr -> String -> CompileM Int
stringDataSize count text = case count of
  Nothing -> pure (length (stringBytes text))
  Just bound -> constExprValue bound

globalAddressExprData :: CType -> Expr -> CompileM [DataValue]
globalAddressExprData ty value = case value of
  EVar name -> globalAddressData name
  _ -> do
    n <- constExprValue (EUnary "&" value)
    scalarData ty n

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
  [] -> pure ([], offset)
  field:rest -> case field of
    Field fieldTy _ -> do
      align <- typeAlign fieldTy
      let aligned = alignUp offset align
      fieldSize <- typeSize fieldTy
      let valueHead = maybeExprHead values
      let valueTail = exprTail values
      fieldData <- globalDataValue fieldTy valueHead
      paddedField <- padDataTarget fieldSize fieldData
      (restData, end) <- structFields (aligned + fieldSize) rest valueTail
      pure (zeroData (aligned - offset) ++ paddedField ++ restData, end)

maybeExprHead :: [Expr] -> Maybe Expr
maybeExprHead values = case values of
  [] -> Nothing
  expr:_ -> Just expr

exprTail :: [Expr] -> [Expr]
exprTail values = case values of
  [] -> []
  _:rest -> rest

globalUnionData :: [Field] -> [Expr] -> CompileM [DataValue]
globalUnionData fields exprs = case fields of
  [] -> zeroUnionData fields
  field:_ -> case exprs of
    [] -> zeroUnionData fields
    expr:_ -> case field of
      Field fieldTy _ -> do
        item <- globalDataValue fieldTy (Just expr)
        size <- unionSizeFromFields fields
        padDataTarget size item

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
scalarData ty value = do
  size <- typeSize ty
  pure (bytesData (intBytes size value))

scalarFloatData :: CType -> String -> CompileM [DataValue]
scalarFloatData ty text = do
  size <- typeSize ty
  pure (bytesData (floatLiteralBytes size text))

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
    DAddress label:rest -> do
      word <- targetWordSize
      if size >= word
        then do
          tailValues <- takeDataTarget (size - word) rest
          pure (DAddress label : tailValues)
        else pure (zeroData size)

dataSizeTarget :: [DataValue] -> CompileM Int
dataSizeTarget values = case values of
  [] -> pure 0
  DByte _:rest -> do
    n <- dataSizeTarget rest
    pure (n + 1)
  DAddress _:rest -> do
    word <- targetWordSize
    n <- dataSizeTarget rest
    pure (n + word)

globalAddressData :: String -> CompileM [DataValue]
globalAddressData name = do
  function <- lookupFunction name
  pure [DAddress (if function then "FUNCTION_" ++ name else name)]

constExprValue :: Expr -> CompileM Int
constExprValue expr = case expr of
  EInt text -> pure (parseInt text)
  EFloat _ -> pure 0
  EChar text -> pure (charValue text)
  ESizeofType ty -> typeSize ty
  ESizeofExpr value -> do
    mty <- exprType value
    ty <- requireMaybeType "sizeof expression has unknown type" mty
    typeSize ty
  ECast _ (EUnary "&" (EPtrMember (ECast (CPtr ty) (EInt "0")) field)) -> do
    info <- memberInfo (Just (CPtr ty)) field
    pure (snd info)
  EUnary "&" (EPtrMember (ECast (CPtr ty) (EInt "0")) field) -> do
    info <- memberInfo (Just (CPtr ty)) field
    pure (snd info)
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
    pure (0 - n)
  EUnary "+" value -> constExprValue value
  EUnary "~" value -> do
    n <- constExprValue value
    pure (0 - n - 1)
  EUnary "!" value -> do
    n <- constExprValue value
    pure (if n == 0 then 1 else 0)
  EBinary op left right -> do
    a <- constExprValue left
    b <- constExprValue right
    pure (constBinOp op a b)
  ECond cond yes no -> do
    c <- constExprValue cond
    constExprValue (if c /= 0 then yes else no)
  _ -> throwC ("unsupported constant expression: " ++ renderExprTag expr)

arrayBoundSize :: Maybe Expr -> CompileM Int
arrayBoundSize bound = case bound of
  Nothing -> pure 1
  Just expr -> constExprValue expr

shiftRightOp :: Expr -> CompileM BinOp
shiftRightOp expr = do
  ty <- promotedExprType expr
  pure (if isUnsignedType ty then IShr else ISar)

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
    Just _ -> not (name `elem` signedNamedIntegerTypes)
    Nothing -> False
  _ -> False
