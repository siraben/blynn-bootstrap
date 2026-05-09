module Lower where

import Base
import TypesAst
import CompileM
import TypesIr
import LowerBootstrap
import LowerBuiltins
import LowerCommon
import LowerDataValues
import LowerImplicit
import LowerLiterals
import LowerParams
import LowerSwitchHelpers
import TypesLower
import LowerTypeInfo

lowerProgram :: Program -> Either CompileError ModuleIr
lowerProgram = lowerProgramWithDataPrefix "HCC_DATA"

lowerProgramWithDataPrefix :: String -> Program -> Either CompileError ModuleIr
lowerProgramWithDataPrefix prefix (Program decls) = runCompileMWithDataPrefix prefix (do
  registerBuiltinStructs
  registerTopDecls decls
  fns <- lowerTopDecls decls
  dataItems <- getDataItems
  pure (ModuleIr dataItems fns)
  )

registerTopDecls :: [TopDecl] -> CompileM ()
registerTopDecls decls = case decls of
  [] -> pure ()
  Function ty name params body:rest -> do
    registerTypeAggregates ty
    bindGlobal name ty
    bindFunction name
    registerImplicitCalls (paramNames params) body
    registerTopDecls rest
  Prototype ty name _:rest -> do
    registerTypeAggregates ty
    bindGlobal name ty
    bindFunction name
    registerTopDecls rest
  StructDecl isUnion name fields:rest -> do
    registerFieldAggregates fields
    bindStruct name isUnion fields
    registerTopDecls rest
  Global ty name initExpr:rest -> do
    registerTypeAggregates ty
    bindGlobal name ty
    values <- globalData ty initExpr
    addDataItem (DataItem name values)
    registerTopDecls rest
  ExternGlobals globals:rest -> do
    registerExternGlobals globals
    registerTopDecls rest
  Globals globals:rest -> do
    registerGlobals globals
    registerTopDecls rest
  EnumConstants constants:rest -> do
    registerConstants constants
    registerTopDecls rest
  _:rest -> registerTopDecls rest

lowerTopDecls :: [TopDecl] -> CompileM [FunctionIr]
lowerTopDecls decls = case decls of
  [] -> pure []
  Function _ name params body:rest -> do
    fn <- lowerFunction name params body
    fns <- lowerTopDecls rest
    pure (fn:fns)
  Prototype _ _ _:rest -> lowerTopDecls rest
  Global _ _ _:rest -> lowerTopDecls rest
  ExternGlobals _:rest -> lowerTopDecls rest
  Globals _:rest -> lowerTopDecls rest
  StructDecl _ _ _:rest -> lowerTopDecls rest
  EnumConstants _:rest -> lowerTopDecls rest
  TypeDecl:rest -> lowerTopDecls rest

lowerFunction :: String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunction name params body =
  withErrorContext ("function " ++ name) (withFunctionScope (lowerFunctionBody name params body))

lowerFunctionBody :: String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunctionBody name params body = do
  bid <- freshBlock
  paramResult <- lowerParams 0 params
  case paramResult of
    (names, paramInstrs) -> do
      blocks <- lowerStatementsFrom bid paramInstrs body (TRet (Just (OImm 0)))
      pure (FunctionIr name names blocks)

lowerStatementsFrom :: BlockId -> [Instr] -> [Stmt] -> Terminator -> CompileM [BasicBlock]
lowerStatementsFrom bid instrs stmts defaultTerm = case stmts of
  [] -> pure [BasicBlock bid instrs defaultTerm]
  SReturn value:rest -> case value of
    Nothing -> do
      tailBlocks <- lowerUnreachableLabels rest defaultTerm
      pure (BasicBlock bid instrs (TRet Nothing) : tailBlocks)
    Just expr -> do
      result <- lowerExpr expr
      case result of
        (retInstrs, op) -> do
          tailBlocks <- lowerUnreachableLabels rest defaultTerm
          pure (BasicBlock bid (instrs ++ retInstrs) (TRet (Just op)) : tailBlocks)
  SBlock body:rest -> do
    if listIsEmpty rest
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
    result <- lowerExpr value
    case result of
      (valueInstrs, valueOp) -> do
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
    restResult <- lowerIfRestTarget rest defaultTerm
    case restResult of
      (restId, restBlocks) -> do
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
  if listIsEmpty no then restId else noId

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
  _ -> do
    result <- lowerExpr cond
    case result of
      (condInstrs, condOp) ->
        pure [BasicBlock bid (instrs ++ condInstrs) (TBranch condOp trueId falseId)]

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
  let clausePairs = zipSwitchClauses clauses clauseIds
  let defaultTarget = switchDefaultTarget restId clausePairs
  let switchCasePairs = switchCases clausePairs
  dispatchBlocks <- lowerSwitchDispatch dispatchId valueOp defaultTarget switchCasePairs
  bodyBlocks <- withBreakTarget restId (lowerSwitchClauses restId clausePairs)
  pure (dispatchBlocks ++ bodyBlocks)

lowerSwitchDispatch :: BlockId -> Operand -> BlockId -> [(Expr, BlockId)] -> CompileM [BasicBlock]
lowerSwitchDispatch firstId valueOp defaultTarget switchCasePairs =
  lowerSwitchDispatchFrom firstId valueOp defaultTarget switchCasePairs

lowerSwitchDispatchFrom :: BlockId -> Operand -> BlockId -> [(Expr, BlockId)] -> CompileM [BasicBlock]
lowerSwitchDispatchFrom bid valueOp defaultTarget switchCasePairs = case switchCasePairs of
  [] -> pure [BasicBlock bid [] (TJump defaultTarget)]
  pair:tailCases -> case pair of
    (caseExpr, target) -> do
      nextId <- switchNextDispatchTarget defaultTarget tailCases
      result <- lowerExpr caseExpr
      case result of
        (caseInstrs, caseOp) -> do
          eq <- freshTemp
          let compareInstr = IBin eq IEq valueOp caseOp
          let block = BasicBlock bid (caseInstrs ++ [compareInstr]) (TBranch (OTemp eq) target nextId)
          switchDispatchTail block nextId valueOp defaultTarget tailCases

switchDispatchTail :: BasicBlock -> BlockId -> Operand -> BlockId -> [(Expr, BlockId)] -> CompileM [BasicBlock]
switchDispatchTail block nextId valueOp defaultTarget tailCases = case tailCases of
  [] -> pure [block]
  _ -> do
    restBlocks <- lowerSwitchDispatchFrom nextId valueOp defaultTarget tailCases
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
    result <- lowerExpr expr
    case result of
      (instrs, _) -> pure instrs

lowerAssignmentInstrs :: Expr -> Expr -> CompileM [Instr]
lowerAssignmentInstrs lhs rhs = do
  result <- lowerAssignment lhs rhs
  case result of
    (instrs, _) -> pure instrs

lowerIncDecInstrs :: Bool -> BinOp -> Expr -> CompileM [Instr]
lowerIncDecInstrs prefix op target = do
  result <- lowerIncDec prefix op target
  case result of
    (instrs, _) -> pure instrs

lowerDirectSideEffect :: String -> [Expr] -> CompileM [Instr]
lowerDirectSideEffect name args = do
  lowered <- lowerExprs args
  let instrs = lowerExprResultsInstrs lowered
  let ops = lowerExprResultsOps lowered
  pure (instrs ++ [ICall Nothing name ops])

lowerIndirectSideEffect :: Expr -> [Expr] -> CompileM [Instr]
lowerIndirectSideEffect callee args = do
  calleeResult <- lowerExpr callee
  case calleeResult of
    (calleeInstrs, calleeOp) -> do
      lowered <- lowerExprs args
      let instrs = lowerExprResultsInstrs lowered
      let ops = lowerExprResultsOps lowered
      pure (calleeInstrs ++ instrs ++ [ICallIndirect Nothing calleeOp ops])

lowerExprResultsInstrs :: [([Instr], Operand)] -> [Instr]
lowerExprResultsInstrs lowered = case lowered of
  [] -> []
  pair:rest -> case pair of
    (instrs, _) -> instrs ++ lowerExprResultsInstrs rest

lowerExprResultsOps :: [([Instr], Operand)] -> [Operand]
lowerExprResultsOps lowered = case lowered of
  [] -> []
  pair:rest -> case pair of
    (_, op) -> op : lowerExprResultsOps rest

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
  Just expr -> case expr of
    EInitList _ -> localDataItem ty initExpr
    EString _ -> localDataItem ty initExpr
    _ -> pure Nothing
  Nothing -> pure Nothing

localNonArrayTemplateData :: CType -> Maybe Expr -> CompileM (Maybe String)
localNonArrayTemplateData ty initExpr = case initExpr of
  Just expr -> case expr of
    EInitList _ -> do
      aggregateStorage <- isAggregateTypeM ty
      if aggregateStorage then localDataItem ty initExpr else pure Nothing
    _ -> pure Nothing
  Nothing -> pure Nothing

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
  addrResult <- offsetAddress dst offset
  let addrInstrs = pairFirst addrResult
  let addr = pairSecond addrResult
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
    result <- lowerExpr expr
    let exprInstrs = pairFirst result
    let op = pairSecond result
    copyInstrs <- copyObject addr op fieldTy
    pure (exprInstrs ++ copyInstrs)

lowerAggregateElementScalarWrite :: Operand -> CType -> Expr -> CompileM [Instr]
lowerAggregateElementScalarWrite addr fieldTy expr = do
  result <- lowerExpr expr
  let exprInstrs = pairFirst result
  let op = pairSecond result
  coerceResult <- coerceScalar fieldTy op
  let coerceInstrs = pairFirst coerceResult
  let coerceOp = pairSecond coerceResult
  store <- storeInstr fieldTy addr coerceOp
  pure (exprInstrs ++ coerceInstrs ++ [store])

registerGlobals :: [(CType, String, Maybe Expr)] -> CompileM ()
registerGlobals globals = case globals of
  [] -> pure ()
  global:rest -> case global of
    (ty, name, initExpr) -> do
      registerTypeAggregates ty
      bindGlobal name ty
      values <- globalData ty initExpr
      addDataItem (DataItem name values)
      registerGlobals rest

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

lowerExpr :: Expr -> CompileM ([Instr], Operand)
lowerExpr expr = case expr of
  EInt text -> do
    temp <- freshTemp
    pure ([intConstInstr temp text], OTemp temp)
  EChar text -> do
    temp <- freshTemp
    pure ([IConst temp (charValue text)], OTemp temp)
  EString text -> do
    dataLabel <- freshDataLabel
    addDataItem (DataItem dataLabel (bytesData (stringBytes text)))
    pure ([], OGlobal dataLabel)
  EVar name -> lowerVarExpr name
  EUnary "+" x -> lowerExpr x
  EUnary "-" x -> do
    result <- lowerExpr x
    let a = pairFirst result
    let op = pairSecond result
    zero <- freshTemp
    out <- freshTemp
    pure (a ++ [IConst zero 0, IBin out ISub (OTemp zero) op], OTemp out)
  EUnary "!" x -> do
    result <- lowerExpr x
    let a = pairFirst result
    let op = pairSecond result
    zero <- freshTemp
    out <- freshTemp
    pure (a ++ [IConst zero 0, IBin out IEq op (OTemp zero)], OTemp out)
  EUnary "~" x -> do
    result <- lowerExpr x
    let a = pairFirst result
    let op = pairSecond result
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
    result <- lowerExpr x
    let a = pairFirst result
    let op = pairSecond result
    (coerceInstrs, coerceOp) <- coerceScalar ty op
    pure (a ++ coerceInstrs, coerceOp)
  ESizeofType ty -> do
    size <- typeSize ty
    temp <- freshTemp
    pure ([IConst temp size], OTemp temp)
  ESizeofExpr value -> do
    mty <- exprType value
    size <- maybe (pure 8) typeSize mty
    temp <- freshTemp
    pure ([IConst temp size], OTemp temp)
  ECond cond yes no -> do
    condResult <- lowerExpr cond
    yesResult <- lowerExpr yes
    noResult <- lowerExpr no
    let ci = pairFirst condResult
    let co = pairSecond condResult
    let yi = pairFirst yesResult
    let yo = pairSecond yesResult
    let ni = pairFirst noResult
    let noOp = pairSecond noResult
    out <- freshTemp
    pure ([ICond out ci co yi yo ni noOp], OTemp out)
  EBinary "," a b -> do
    ai <- lowerSideEffect a
    bResult <- lowerExpr b
    let bi = pairFirst bResult
    let bo = pairSecond bResult
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
lowerVarExpr name = case builtinConstant name of
  Just value -> pure ([], OImm value)
  Nothing -> lowerNonBuiltinVarExpr name

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
      coerceScalar (maybe CLong id mty) (OTemp temp)
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
    Nothing -> do
      out <- freshTemp
      pure ([ILoad64 out (OGlobal name)], OTemp out)

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
    else case lowerBinOp op of
      Just iop -> do
        if op == "<<"
          then lowerShiftExpr op a b
          else lowerPlainBin iop a b
      Nothing -> throwC ("unsupported binary operator in lowering: " ++ op)

isComparisonOpString :: String -> Bool
isComparisonOpString op =
  stringMember op ("<" : "<=" : ">" : ">=" : [])

lowerComparisonExpr :: String -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerComparisonExpr op a b = do
  leftResult <- lowerExpr a
  rightResult <- lowerExpr b
  let ai = pairFirst leftResult
  let ao = pairSecond leftResult
  let bi = pairFirst rightResult
  let bo = pairSecond rightResult
  out <- freshTemp
  iop <- comparisonOp op a b
  pure (ai ++ bi ++ [IBin out iop ao bo], OTemp out)

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
  calleeResult <- lowerExpr callee
  case calleeResult of
    (calleeInstrs, calleeOp) -> do
      lowered <- lowerExprs args
      out <- freshTemp
      let instrs = lowerExprResultsInstrs lowered
      let ops = lowerExprResultsOps lowered
      pure (calleeInstrs ++ instrs ++ [ICallIndirect (Just out) calleeOp ops], OTemp out)

lowerLogicalAnd :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerLogicalAnd left right = do
  leftResult <- lowerExpr left
  rightResult <- lowerTruthExpr right
  let leftInstrs = pairFirst leftResult
  let leftOp = pairSecond leftResult
  let rightInstrs = pairFirst rightResult
  let rightBool = pairSecond rightResult
  out <- freshTemp
  pure ([ICond out leftInstrs leftOp rightInstrs rightBool [] (OImm 0)], OTemp out)

lowerLogicalOr :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerLogicalOr left right = do
  leftResult <- lowerExpr left
  rightResult <- lowerTruthExpr right
  let leftInstrs = pairFirst leftResult
  let leftOp = pairSecond leftResult
  let rightInstrs = pairFirst rightResult
  let rightBool = pairSecond rightResult
  out <- freshTemp
  pure ([ICond out leftInstrs leftOp [] (OImm 1) rightInstrs rightBool], OTemp out)

lowerTruthExpr :: Expr -> CompileM ([Instr], Operand)
lowerTruthExpr expr = do
  result <- lowerExpr expr
  let instrs = pairFirst result
  let op = pairSecond result
  out <- freshTemp
  pure (instrs ++ [IBin out INe op (OImm 0)], OTemp out)

lowerShiftExpr :: String -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerShiftExpr op left right = do
  leftResult <- lowerExpr left
  rightResult <- lowerExpr right
  let leftInstrs = pairFirst leftResult
  let leftOp = pairSecond leftResult
  let rightInstrs = pairFirst rightResult
  let rightOp = pairSecond rightResult
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
  leftResult <- lowerExpr a
  rightResult <- lowerExpr b
  let ai = pairFirst leftResult
  let ao = pairSecond leftResult
  let bi = pairFirst rightResult
  let bo = pairSecond rightResult
  diff <- freshTemp
  out <- freshTemp
  size <- typeSize elemTy
  pure (ai ++ bi ++ [IBin diff ISub ao bo, IBin out IDiv (OTemp diff) (OImm size)], OTemp out)

lowerPointerOffset :: BinOp -> Expr -> Expr -> CType -> CompileM ([Instr], Operand)
lowerPointerOffset op ptr offset elemTy = do
  ptrResult <- lowerExpr ptr
  offsetResult <- lowerExpr offset
  let ptrInstrs = pairFirst ptrResult
  let po = pairSecond ptrResult
  let oi = pairFirst offsetResult
  let oo = pairSecond offsetResult
  size <- typeSize elemTy
  scaled <- freshTemp
  out <- freshTemp
  pure (ptrInstrs ++ oi ++ [IBin scaled IMul oo (OImm size), IBin out op po (OTemp scaled)], OTemp out)

lowerPlainBin :: BinOp -> Expr -> Expr -> CompileM ([Instr], Operand)
lowerPlainBin op a b = do
  leftResult <- lowerExpr a
  rightResult <- lowerExpr b
  let ai = pairFirst leftResult
  let ao = pairSecond leftResult
  let bi = pairFirst rightResult
  let bo = pairSecond rightResult
  commonTy <- usualArithmeticType a b
  acoerceResult <- coerceScalar commonTy ao
  bcoerceResult <- coerceScalar commonTy bo
  let acoerceInstrs = pairFirst acoerceResult
  let acoerceOp = pairSecond acoerceResult
  let bcoerceInstrs = pairFirst bcoerceResult
  let bcoerceOp = pairSecond bcoerceResult
  out <- freshTemp
  let resultTy = if isComparisonBinOp op then CInt else commonTy
  coerceResult <- coerceScalar resultTy (OTemp out)
  let coerceInstrs = pairFirst coerceResult
  let coerceOp = pairSecond coerceResult
  pure ( ai ++ bi ++ acoerceInstrs ++ bcoerceInstrs ++
         [IBin out op acoerceOp bcoerceOp] ++ coerceInstrs
       , coerceOp)

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
  lhsResult <- lowerLValue lhs
  rhsResult <- lowerExpr rhs
  let lhsInstrs = pairFirst lhsResult
  let lvalue = pairSecond lhsResult
  let rhsInstrs = pairFirst rhsResult
  let rhsOp = pairSecond rhsResult
  targetTy <- lValueType lvalue
  coerceResult <- coerceScalar targetTy rhsOp
  let coerceInstrs = pairFirst coerceResult
  let coerceOp = pairSecond coerceResult
  writeInstrs <- writeLValue lvalue coerceOp
  pure (lhsInstrs ++ rhsInstrs ++ coerceInstrs ++ writeInstrs, coerceOp)

lowerIncDec :: Bool -> BinOp -> Expr -> CompileM ([Instr], Operand)
lowerIncDec prefix op target = do
  lvResult <- lowerLValue target
  let lvInstrs = pairFirst lvResult
  let lvalue = pairSecond lvResult
  readResult <- readLValue lvalue
  let readInstrs = pairFirst readResult
  let current = pairSecond readResult
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
  lvResult <- lowerLValue target
  let instrs = pairFirst lvResult
  let lvalue = pairSecond lvResult
  readResult <- readLValue lvalue
  let readInstrs = pairFirst readResult
  let op = pairSecond readResult
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
coerceScalar ty op = do
  integer <- isIntegerTypeM ty
  if not integer
    then pure ([], op)
    else do
      size <- typeSize ty
      if size >= 8
        then pure ([], op)
        else if isSignedIntegerType ty
          then signExtendScalar size op
          else maskScalar size op

maskScalar :: Int -> Operand -> CompileM ([Instr], Operand)
maskScalar size op = do
  out <- freshTemp
  pure ([IBin out IAnd op (byteMaskOperand size)], OTemp out)

signExtendScalar :: Int -> Operand -> CompileM ([Instr], Operand)
signExtendScalar size op = do
  masked <- freshTemp
  flipped <- freshTemp
  out <- freshTemp
  let signBit = signBitOperand size
  pure ( [ IBin masked IAnd op (byteMaskOperand size)
         , IBin flipped IXor (OTemp masked) signBit
         , IBin out ISub (OTemp flipped) signBit
         ]
       , OTemp out)

byteMask :: Int -> Int
byteMask size = pow2 (size * 8) - 1

byteMaskOperand :: Int -> Operand
byteMaskOperand size =
  if size >= 4
  then OImmBytes (byteMaskBytes size)
  else OImm (byteMask size)

signBitOperand :: Int -> Operand
signBitOperand size =
  if size >= 4
  then OImmBytes (signBitBytes size)
  else OImm (pow2 (size * 8 - 1))

byteMaskBytes :: Int -> [Int]
byteMaskBytes size = takeInts 8 (byteOnes size ++ byteZeros)

signBitBytes :: Int -> [Int]
signBitBytes size = takeInts 8 (byteZerosN (size - 1) ++ [128] ++ byteZeros)

byteOnes :: Int -> [Int]
byteOnes count = if count <= 0 then [] else 255 : byteOnes (count - 1)

byteZerosN :: Int -> [Int]
byteZerosN count = if count <= 0 then [] else 0 : byteZerosN (count - 1)

byteZeros :: [Int]
byteZeros = 0 : byteZeros

copyObject :: Operand -> Operand -> CType -> CompileM [Instr]
copyObject dst src ty = do
  size <- typeSize ty
  copyObjectBytes dst src 0 size

copyObjectBytes :: Operand -> Operand -> Int -> Int -> CompileM [Instr]
copyObjectBytes dst src offset remaining =
  if remaining <= 0
    then pure []
    else do
      let width = if remaining >= 8 then 8 else if remaining >= 4 then 4 else 1
      dstResult <- offsetAddress dst offset
      srcResult <- offsetAddress src offset
      let dstInstrs = pairFirst dstResult
      let dstAddr = pairSecond dstResult
      let srcInstrs = pairFirst srcResult
      let srcAddr = pairSecond srcResult
      val <- freshTemp
      let load = if width == 8 then ILoad64 val srcAddr else if width == 4 then ILoad32 val srcAddr else ILoad8 val srcAddr
      let store = if width == 8 then IStore64 dstAddr (OTemp val) else if width == 4 then IStore32 dstAddr (OTemp val) else IStore8 dstAddr (OTemp val)
      rest <- copyObjectBytes dst src (offset + width) (remaining - width)
      pure (dstInstrs ++ srcInstrs ++ [load, store] ++ rest)

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
  result <- lowerLValue target
  let instrs = pairFirst result
  let lvalue = pairSecond result
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
        pure ([], LLocal temp (maybe CLong id ty))
      Nothing -> do
        ty <- lookupGlobalType name
        pure ([], LAddress (OGlobal name) (maybe CLong id ty))
  EUnary "*" ptr -> do
    result <- lowerExpr ptr
    let instrs = pairFirst result
    let op = pairSecond result
    ty <- exprType target
    pure (instrs, LAddress op (maybe CLong id ty))
  EIndex base ix -> do
    baseResult <- lowerExpr base
    ixResult <- lowerExpr ix
    let baseInstrs = pairFirst baseResult
    let baseOp = pairSecond baseResult
    let ixInstrs = pairFirst ixResult
    let ixOp = pairSecond ixResult
    elemTy <- indexedElementType base
    elemSize <- typeSize elemTy
    scaleResult <- scaledIndex ixOp elemSize
    let scaleInstrs = pairFirst scaleResult
    let offsetOp = pairSecond scaleResult
    addr <- freshTemp
    pure (baseInstrs ++ ixInstrs ++ scaleInstrs ++ [IBin addr IAdd baseOp offsetOp], LAddress (OTemp addr) elemTy)
  EPtrMember base field -> do
    baseResult <- lowerExpr base
    let baseInstrs = pairFirst baseResult
    let baseOp = pairSecond baseResult
    baseTy <- exprType base
    fieldResult <- memberInfo baseTy field
    let fieldTy = pairFirst fieldResult
    let offset = pairSecond fieldResult
    addr <- freshTemp
    pure (baseInstrs ++ [IBin addr IAdd baseOp (OImm offset)], LAddress (OTemp addr) fieldTy)
  EMember base field -> do
    baseResult <- lowerLValueAddress base
    let baseInstrs = pairFirst baseResult
    let baseAddr = pairSecond baseResult
    baseTy <- exprType base
    fieldResult <- memberInfo (Just (CPtr (maybe CLong id baseTy))) field
    let fieldTy = pairFirst fieldResult
    let offset = pairSecond fieldResult
    addr <- freshTemp
    pure (baseInstrs ++ [IBin addr IAdd baseAddr (OImm offset)], LAddress (OTemp addr) fieldTy)
  _ -> throwC ("unsupported lvalue: " ++ renderExprTag target)

indexedElementType :: Expr -> CompileM CType
indexedElementType base = do
  mty <- exprType base
  pure (case mty of
    Just (CPtr ty) -> ty
    Just (CArray ty _) -> ty
    _ -> CUnsignedChar)

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
  EChar _ -> pure (Just CChar)
  EString _ -> pure (Just (CPtr CChar))
  ESizeofType _ -> pure (Just CInt)
  ESizeofExpr _ -> pure (Just CInt)
  EVar name -> do
    local <- lookupVarType name
    case local of
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
    info <- memberInfoMaybe (Just (CPtr (maybe CLong id baseTy))) field
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
  ECall (EVar name) _ ->
    lookupGlobalType name
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
  CInt -> True
  CLong -> True
  CEnum _ -> True
  CNamed name -> isSignedNamedInteger name
  _ -> False

isIntegerTypeM :: CType -> CompileM Bool
isIntegerTypeM ty = case ty of
  CChar -> pure True
  CUnsignedChar -> pure True
  CInt -> pure True
  CUnsigned -> pure True
  CLong -> pure True
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
  leftSize <- typeSize leftTy
  rightSize <- typeSize rightTy
  let size = max leftSize rightSize
  let unsigned = isUnsignedType leftTy || isUnsignedType rightTy
  pure (case (size >= 8, unsigned) of
    (True, True) -> CNamed "unsigned_long"
    (True, False) -> CLong
    (False, True) -> CUnsigned
    (False, False) -> CInt)

promotedExprType :: Expr -> CompileM CType
promotedExprType expr = case expr of
  EInt text ->
    if intLiteralIsUnsigned text then pure CUnsigned else pure CInt
  _ -> do
    mty <- exprType expr
    promoteIntegerType (maybe CLong id mty)

storeInstr :: CType -> Operand -> Operand -> CompileM Instr
storeInstr ty addr value = do
  size <- typeSize ty
  pure (if size <= 1 then IStore8 addr value else if size <= 2 then IStore16 addr value else if size <= 4 then IStore32 addr value else IStore64 addr value)

typeSize :: CType -> CompileM Int
typeSize ty = case ty of
  CVoid -> pure 1
  CChar -> pure 1
  CUnsignedChar -> pure 1
  CInt -> pure 4
  CUnsigned -> pure 4
  CFloat -> pure 4
  CLong -> pure 8
  CDouble -> pure 8
  CLongDouble -> pure 16
  CPtr _ -> pure 8
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
  Just size -> pure size
  Nothing -> do
      fields <- lookupStruct name
      case fields of
        Just _ -> structSize name
        Nothing -> pure 8

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
        Nothing -> pure 8
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
  pure (padData size values)

initializedSize :: CType -> [DataValue] -> Maybe Expr -> CompileM Int
initializedSize ty values initExpr = case ty of
  CArray inner count -> case count of
    Nothing -> initializedUnboundedArraySize inner values initExpr
    Just _ -> typeSize ty
  _ -> typeSize ty

initializedUnboundedArraySize :: CType -> [DataValue] -> Maybe Expr -> CompileM Int
initializedUnboundedArraySize inner values initExpr = case initExpr of
  Just expr -> case expr of
    EInitList _ -> pure (dataSize values)
    EString _ -> case inner of
      CChar -> pure (dataSize values)
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
      pure (padData (n * elemSize) items)

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
    pure (padData size (bytesData (stringBytes text)))
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
    pure (padData elemSize item ++ tailItems)

globalStructData :: [Field] -> [Expr] -> CompileM [DataValue]
globalStructData fields exprs = do
  result <- structFields 0 fields exprs
  let values = pairFirst result
  let used = pairSecond result
  pure (padData used values)

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
      result <- structFields (aligned + fieldSize) rest valueTail
      let restData = pairFirst result
      let end = pairSecond result
      pure (zeroData (aligned - offset) ++ padData fieldSize fieldData ++ restData, end)

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
        pure (padData size item)

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

globalAddressData :: String -> CompileM [DataValue]
globalAddressData name = do
  function <- lookupFunction name
  pure [DAddress (if function then "FUNCTION_" ++ name else name)]

constExprValue :: Expr -> CompileM Int
constExprValue expr = case expr of
  EInt text -> pure (parseInt text)
  EChar text -> pure (charValue text)
  ESizeofType ty -> typeSize ty
  ESizeofExpr value -> do
    mty <- exprType value
    maybe (pure 8) typeSize mty
  ECast _ (EUnary "&" (EPtrMember (ECast (CPtr ty) (EInt "0")) field)) -> do
    info <- memberInfo (Just (CPtr ty)) field
    pure (pairSecond info)
  EUnary "&" (EPtrMember (ECast (CPtr ty) (EInt "0")) field) -> do
    info <- memberInfo (Just (CPtr ty)) field
    pure (pairSecond info)
  EVar name -> do
    constant <- lookupConstant name
    pure (maybe (maybe 0 id (builtinConstant name)) id constant)
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
  _ -> pure 0

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
  CPtr _ -> True
  CArray _ _ -> True
  CNamed name -> case namedIntegerSize name of
    Just _ -> not (stringMember name signedNamedIntegerTypes)
    Nothing -> False
  _ -> False
