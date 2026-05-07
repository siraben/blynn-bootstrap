module Hcc.Lower
  ( lowerProgram
  ) where

import Hcc.Ast
import Hcc.CompileM
import Hcc.Ir

data LValue
  = LLocal Temp CType
  | LAddress Operand CType
  deriving (Eq, Show)

data SwitchClause = SwitchClause (Maybe Expr) [Stmt]
  deriving (Eq, Show)

lowerProgram :: Program -> Either CompileError ModuleIr
lowerProgram (Program decls) = runCompileM $ do
  registerBuiltinStructs
  registerTopDecls decls
  fns <- lowerTopDecls decls
  dataItems <- getDataItems
  pure (ModuleIr dataItems fns)

registerBuiltinStructs :: CompileM ()
registerBuiltinStructs = do
  bindStruct "tm" False
    [ Field CInt "tm_sec"
    , Field CInt "tm_min"
    , Field CInt "tm_hour"
    , Field CInt "tm_mday"
    , Field CInt "tm_mon"
    , Field CInt "tm_year"
    , Field CInt "tm_wday"
    , Field CInt "tm_yday"
    , Field CInt "tm_isdst"
    ]
  bindStruct "timeval" False
    [ Field CLong "tv_sec"
    , Field CLong "tv_usec"
    ]

registerTopDecls :: [TopDecl] -> CompileM ()
registerTopDecls decls = case decls of
  [] -> pure ()
  Function ty name _ _:rest -> do
    registerTypeAggregates ty
    bindGlobal name ty
    registerTopDecls rest
  Prototype ty name _:rest -> do
    registerTypeAggregates ty
    bindGlobal name ty
    registerTopDecls rest
  StructDecl isUnion name fields:rest -> do
    registerFieldAggregates fields
    bindStruct name isUnion fields
    registerTopDecls rest
  Global ty name initExpr:rest -> do
    registerTypeAggregates ty
    bindGlobal name ty
    addDataItem (DataItem name (globalBytes initExpr))
    registerTopDecls rest
  Globals globals:rest -> do
    registerGlobals globals
    registerTopDecls rest
  _:rest -> registerTopDecls rest

lowerTopDecls :: [TopDecl] -> CompileM [FunctionIr]
lowerTopDecls decls = case decls of
  [] -> pure []
  Function _ name params body:rest -> do
    fn <- lowerFunction name params body
    fns <- lowerTopDecls rest
    pure (fn:fns)
  Prototype{}:rest -> lowerTopDecls rest
  Global{}:rest -> lowerTopDecls rest
  Globals{}:rest -> lowerTopDecls rest
  StructDecl{}:rest -> lowerTopDecls rest
  TypeDecl:rest -> lowerTopDecls rest

lowerFunction :: String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunction name params body = withErrorContext ("function " ++ name) $ withFunctionScope $ do
  bid <- freshBlock
  (paramNames, paramInstrs) <- lowerParams 0 params
  blocks <- lowerStatementsFrom bid paramInstrs body (TRet (Just (OImm 0)))
  pure (FunctionIr name paramNames blocks)

lowerParams :: Int -> [Param] -> CompileM ([String], [Instr])
lowerParams index params = case params of
  [] -> pure ([], [])
  Param ty name:rest -> do
    temp <- freshTemp
    bindVar name temp ty
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
    (condInstrs, condOp) <- lowerExpr cond
    bodyBlocks <- withLoopTargets restId condId (lowerStatementsFrom bodyId [] body (TJump condId))
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure ( BasicBlock bid instrs (TJump condId)
         : BasicBlock condId condInstrs (TBranch condOp bodyId restId)
         : bodyBlocks ++ restBlocks)
  SDoWhile body cond:rest -> do
    bodyId <- freshBlock
    condId <- freshBlock
    restId <- freshBlock
    (condInstrs, condOp) <- lowerExpr cond
    bodyBlocks <- withLoopTargets restId condId (lowerStatementsFrom bodyId [] body (TJump condId))
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure ( BasicBlock bid instrs (TJump bodyId)
         : bodyBlocks ++
           [BasicBlock condId condInstrs (TBranch condOp bodyId restId)] ++
           restBlocks)
  SFor initExpr condExpr stepExpr body:rest -> do
    initInstrs <- maybeLowerSideEffect initExpr
    condId <- freshBlock
    bodyId <- freshBlock
    stepId <- freshBlock
    restId <- freshBlock
    (condInstrs, condTerm) <- lowerLoopCondition condExpr bodyId restId
    stepInstrs <- maybeLowerSideEffect stepExpr
    bodyBlocks <- withLoopTargets restId stepId (lowerStatementsFrom bodyId [] body (TJump stepId))
    restBlocks <- lowerStatementsFrom restId [] rest defaultTerm
    pure ( BasicBlock bid (instrs ++ initInstrs) (TJump condId)
         : BasicBlock condId condInstrs condTerm
         : bodyBlocks ++
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
  SBreak:rest -> do
    target <- requireBreakTarget
    tailBlocks <- lowerUnreachableLabels rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : tailBlocks)
  SContinue:rest -> do
    target <- requireContinueTarget
    tailBlocks <- lowerUnreachableLabels rest defaultTerm
    pure (BasicBlock bid instrs (TJump target) : tailBlocks)
  stmt:_ -> throwC ("unsupported statement in lowering: " ++ show stmt)

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

lowerLoopCondition :: Maybe Expr -> BlockId -> BlockId -> CompileM ([Instr], Terminator)
lowerLoopCondition condExpr bodyId restId = case condExpr of
  Nothing -> pure ([], TJump bodyId)
  Just cond -> do
    (condInstrs, condOp) <- lowerExpr cond
    pure (condInstrs, TBranch condOp bodyId restId)

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
  let clauses = collectSwitchClauses body
  clauseIds <- freshBlocks (length clauses)
  let clausePairs = zip clauses clauseIds
  let defaultTarget = switchDefaultTarget restId clausePairs
  dispatchBlocks <- lowerSwitchDispatch dispatchId valueOp defaultTarget (switchCases clausePairs)
  bodyBlocks <- withBreakTarget restId (lowerSwitchClauses restId clausePairs)
  pure (dispatchBlocks ++ bodyBlocks)

collectSwitchClauses :: [Stmt] -> [SwitchClause]
collectSwitchClauses stmts = finish (go Nothing [] stmts) where
  go current acc rest = case rest of
    [] -> (current, acc)
    SCase expr:xs -> go (Just (Just expr, [])) (finishOne current acc) xs
    SDefault:xs -> go (Just (Nothing, [])) (finishOne current acc) xs
    stmt:xs -> case current of
      Nothing -> go current acc xs
      Just (label, body) -> go (Just (label, body ++ [stmt])) acc xs

  finish (current, acc) = reverse (finishOne current acc)

  finishOne current acc = case current of
    Nothing -> acc
    Just (label, clauseBody) -> SwitchClause label clauseBody : acc

freshBlocks :: Int -> CompileM [BlockId]
freshBlocks count =
  if count <= 0
    then pure []
    else do
      first <- freshBlock
      rest <- freshBlocks (count - 1)
      pure (first:rest)

switchDefaultTarget :: BlockId -> [(SwitchClause, BlockId)] -> BlockId
switchDefaultTarget restId clauses = case clauses of
  [] -> restId
  (SwitchClause Nothing _, bid):_ -> bid
  _:rest -> switchDefaultTarget restId rest

switchCases :: [(SwitchClause, BlockId)] -> [(Expr, BlockId)]
switchCases clauses = case clauses of
  [] -> []
  (SwitchClause (Just value) _, bid):rest -> (value, bid) : switchCases rest
  _:rest -> switchCases rest

lowerSwitchDispatch :: BlockId -> Operand -> BlockId -> [(Expr, BlockId)] -> CompileM [BasicBlock]
lowerSwitchDispatch firstId valueOp defaultTarget cases = go firstId cases where
  go bid rest = case rest of
    [] -> pure [BasicBlock bid [] (TJump defaultTarget)]
    (caseExpr, target):tailCases -> do
      nextId <- if null tailCases then pure defaultTarget else freshBlock
      (caseInstrs, caseOp) <- lowerExpr caseExpr
      eq <- freshTemp
      let block = BasicBlock bid (caseInstrs ++ [IBin eq IEq valueOp caseOp]) (TBranch (OTemp eq) target nextId)
      if null tailCases
        then pure [block]
        else do
          restBlocks <- go nextId tailCases
          pure (block:restBlocks)

lowerSwitchClauses :: BlockId -> [(SwitchClause, BlockId)] -> CompileM [BasicBlock]
lowerSwitchClauses restId clauses = case clauses of
  [] -> pure []
  (SwitchClause _ body, bid):rest -> do
    let fallthrough = case rest of
          [] -> restId
          (_, nextId):_ -> nextId
    bodyBlocks <- lowerStatementsFrom bid [] body (TJump fallthrough)
    restBlocks <- lowerSwitchClauses restId rest
    pure (bodyBlocks ++ restBlocks)

lowerSideEffect :: Expr -> CompileM [Instr]
lowerSideEffect expr = case expr of
  ECall (EVar name) _ | name `elem` ignoredSideEffectCalls ->
    pure []
  ECall (EVar name) args -> do
    lowered <- lowerExprs args
    let instrs = concatMap fst lowered
    let ops = map snd lowered
    pure (instrs ++ [ICall Nothing name ops])
  ECall callee args -> do
    (calleeInstrs, calleeOp) <- lowerExpr callee
    lowered <- lowerExprs args
    let instrs = concatMap fst lowered
    let ops = map snd lowered
    pure (calleeInstrs ++ instrs ++ [ICallIndirect Nothing calleeOp ops])
  EAssign lhs rhs ->
    fst <$> lowerAssignment lhs rhs
  EPostfix "--" target ->
    fst <$> lowerIncDec False ISub target
  EPostfix "++" target ->
    fst <$> lowerIncDec False IAdd target
  _ -> do
    (instrs, _) <- lowerExpr expr
    pure instrs

ignoredSideEffectCalls :: [String]
ignoredSideEffectCalls = ["asm", "oputs", "eputs"]

lowerDecls :: [(CType, String, Maybe Expr)] -> CompileM [Instr]
lowerDecls decls = case decls of
  [] -> pure []
  (ty, name, initExpr):rest -> do
    instrs <- lowerDecl ty name initExpr
    tailInstrs <- lowerDecls rest
    pure (instrs ++ tailInstrs)

lowerDecl :: CType -> String -> Maybe Expr -> CompileM [Instr]
lowerDecl ty name initExpr = do
  (declInstrs, temp) <- case initExpr of
    Nothing -> do
      t <- freshTemp
      pure ([IConst t 0], t)
    Just expr -> do
      (exprInstrs, op) <- lowerExpr expr
      (copyInstrs, t) <- materialize op
      pure (exprInstrs ++ copyInstrs, t)
  bindVar name temp ty
  pure declInstrs

registerGlobals :: [(CType, String, Maybe Expr)] -> CompileM ()
registerGlobals globals = case globals of
  [] -> pure ()
  (ty, name, initExpr):rest -> do
    registerTypeAggregates ty
    bindGlobal name ty
    addDataItem (DataItem name (globalBytes initExpr))
    registerGlobals rest

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
    pure ([IConst temp (parseInt text)], OTemp temp)
  EChar text -> do
    temp <- freshTemp
    pure ([IConst temp (charValue text)], OTemp temp)
  EString text -> do
    label <- freshLabel
    addDataItem (DataItem label (stringBytes text))
    pure ([], OGlobal ("HCC_DATA_" ++ label))
  EVar name -> do
    local <- lookupVarMaybe name
    case local of
      Just temp -> pure ([], OTemp temp)
      Nothing -> do
        out <- freshTemp
        pure ([ILoad64 out (OGlobal name)], OTemp out)
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
  EUnary "&" target ->
    lowerLValueAddress target
  EUnary "*" _ ->
    readLValueExpr expr
  EUnary "++" target ->
    lowerIncDec True IAdd target
  EUnary "--" target ->
    lowerIncDec True ISub target
  ECast CUnsignedChar x -> do
    (a, op) <- lowerExpr x
    out <- freshTemp
    pure (a ++ [IBin out IAnd op (OImm 255)], OTemp out)
  ECast _ x -> lowerExpr x
  EUnary "sizeof_type" _ -> do
    temp <- freshTemp
    pure ([IConst temp 8], OTemp temp)
  EUnary "sizeof" _ -> do
    temp <- freshTemp
    pure ([IConst temp 8], OTemp temp)
  ECond cond yes no -> do
    (ci, co) <- lowerExpr cond
    (yi, yo) <- lowerExpr yes
    (ni, noOp) <- lowerExpr no
    bool <- freshTemp
    one <- freshTemp
    inv <- freshTemp
    ypart <- freshTemp
    npart <- freshTemp
    out <- freshTemp
    pure ( ci ++ yi ++ ni ++
           [ IBin bool INe co (OImm 0)
           , IConst one 1
           , IBin inv ISub (OTemp one) (OTemp bool)
           , IBin ypart IMul (OTemp bool) yo
           , IBin npart IMul (OTemp inv) noOp
           , IBin out IAdd (OTemp ypart) (OTemp npart)
           ]
         , OTemp out)
  EBinary "," a b -> do
    ai <- lowerSideEffect a
    (bi, bo) <- lowerExpr b
    pure (ai ++ bi, bo)
  EBinary op a b | Just iop <- lowerBinOp op -> do
    (ai, ao) <- lowerExpr a
    (bi, bo) <- lowerExpr b
    out <- freshTemp
    pure (ai ++ bi ++ [IBin out iop ao bo], OTemp out)
  EIndex{} ->
    readLValueExpr expr
  EPtrMember{} ->
    readLValueExpr expr
  EMember{} ->
    readLValueExpr expr
  ECall (EVar name) args -> do
    lowered <- lowerExprs args
    out <- freshTemp
    let instrs = concatMap fst lowered
    let ops = map snd lowered
    pure (instrs ++ [ICall (Just out) name ops], OTemp out)
  ECall callee args -> do
    (calleeInstrs, calleeOp) <- lowerExpr callee
    lowered <- lowerExprs args
    out <- freshTemp
    let instrs = concatMap fst lowered
    let ops = map snd lowered
    pure (calleeInstrs ++ instrs ++ [ICallIndirect (Just out) calleeOp ops], OTemp out)
  EAssign lhs rhs ->
    lowerAssignment lhs rhs
  EPostfix "--" target ->
    lowerIncDec False ISub target
  EPostfix "++" target ->
    lowerIncDec False IAdd target
  _ -> throwC ("unsupported expression in lowering: " ++ show expr)

lowerExprs :: [Expr] -> CompileM [([Instr], Operand)]
lowerExprs args = case args of
  [] -> pure []
  x:xs -> do
    first <- lowerExpr x
    rest <- lowerExprs xs
    pure (first:rest)

lowerAssignment :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerAssignment lhs rhs = do
  (lhsInstrs, lvalue) <- lowerLValue lhs
  (rhsInstrs, rhsOp) <- lowerExpr rhs
  writeInstrs <- writeLValue lvalue rhsOp
  pure (lhsInstrs ++ rhsInstrs ++ writeInstrs, rhsOp)

lowerIncDec :: Bool -> BinOp -> Expr -> CompileM ([Instr], Operand)
lowerIncDec prefix op target = do
  (lvInstrs, lvalue) <- lowerLValue target
  (readInstrs, current) <- readLValue lvalue
  old <- freshTemp
  one <- freshTemp
  out <- freshTemp
  writeInstrs <- writeLValue lvalue (OTemp out)
  let opInstrs = [IBin old IAdd current (OImm 0), IConst one 1, IBin out op (OTemp old) (OTemp one)]
  pure (lvInstrs ++ readInstrs ++ opInstrs ++ writeInstrs, if prefix then OTemp out else OTemp old)

readLValueExpr :: Expr -> CompileM ([Instr], Operand)
readLValueExpr target = do
  (instrs, lvalue) <- lowerLValue target
  (readInstrs, op) <- readLValue lvalue
  pure (instrs ++ readInstrs, op)

readLValue :: LValue -> CompileM ([Instr], Operand)
readLValue lvalue = case lvalue of
  LLocal temp _ ->
    pure ([], OTemp temp)
  LAddress addr ty -> case ty of
    CArray{} -> pure ([], addr)
    _ -> do
      out <- freshTemp
      load <- loadInstr out ty addr
      pure ([load], OTemp out)

writeLValue :: LValue -> Operand -> CompileM [Instr]
writeLValue lvalue value = case lvalue of
  LLocal temp _ ->
    pure [ICopy temp value]
  LAddress addr ty -> do
    store <- storeInstr ty addr value
    pure [store]

lowerLValueAddress :: Expr -> CompileM ([Instr], Operand)
lowerLValueAddress target = do
  (instrs, lvalue) <- lowerLValue target
  case lvalue of
    LAddress addr _ -> pure (instrs, addr)
    LLocal temp _ -> do
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
    (instrs, op) <- lowerExpr ptr
    ty <- exprType target
    pure (instrs, LAddress op (maybe CLong id ty))
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
    (fieldTy, offset) <- memberInfo (Just (CPtr (maybe CLong id baseTy))) field
    addr <- freshTemp
    pure (baseInstrs ++ [IBin addr IAdd baseAddr (OImm offset)], LAddress (OTemp addr) fieldTy)
  _ -> throwC ("unsupported lvalue: " ++ show target)

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
  EInt{} -> pure (Just CInt)
  EChar{} -> pure (Just CChar)
  EString{} -> pure (Just (CPtr CChar))
  EVar name -> do
    local <- lookupVarType name
    case local of
      Just ty -> pure (Just ty)
      Nothing -> lookupGlobalType name
  ECast ty _ -> pure (Just ty)
  EUnary "*" value -> do
    mty <- exprType value
    pure (case mty of
      Just (CPtr ty) -> Just ty
      _ -> Nothing)
  EUnary "&" value -> do
    mty <- exprType value
    pure (CPtr <$> mty)
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
    info <- memberInfoMaybe (Just (CPtr (maybe CLong id baseTy))) field
    pure (fmap fst info)
  EAssign lhs _ -> exprType lhs
  EPostfix _ value -> exprType value
  EUnary "++" value -> exprType value
  EUnary "--" value -> exprType value
  ECall (EVar name) _ ->
    lookupGlobalType name
  _ -> pure Nothing

memberInfo :: Maybe CType -> String -> CompileM (CType, Int)
memberInfo mty field = do
  found <- memberInfoMaybe mty field
  case found of
    Just info -> pure info
    Nothing -> throwC ("unknown struct member: " ++ field ++ " on " ++ show mty)

memberInfoMaybe :: Maybe CType -> String -> CompileM (Maybe (CType, Int))
memberInfoMaybe mty field = case mty of
  Just (CPtr ty) -> do
    aggregate <- aggregateFields ty
    case aggregate of
      Nothing -> pure Nothing
      Just (isUnion, fields) -> fieldOffset isUnion 0 fields
  _ -> pure Nothing
  where
    fieldOffset isUnion offset fields = case fields of
      [] -> pure Nothing
      Field ty name:rest -> do
        align <- typeAlign ty
        let aligned = alignUp offset align
        if name == field
          then pure (Just (ty, if isUnion then 0 else aligned))
          else do
            size <- typeSize ty
            nested <- if name == ""
              then anonymousMemberInfo (if isUnion then 0 else aligned) ty field
              else pure Nothing
            case nested of
              Just info -> pure (Just info)
              Nothing -> fieldOffset isUnion (aligned + size) rest

anonymousMemberInfo :: Int -> CType -> String -> CompileM (Maybe (CType, Int))
anonymousMemberInfo baseOffset ty field = do
  aggregate <- aggregateFields ty
  case aggregate of
    Nothing -> pure Nothing
    Just (isUnion, fields) -> nestedFieldOffset isUnion 0 fields
  where
    nestedFieldOffset isUnion offset fields = case fields of
      [] -> pure Nothing
      Field fieldTy name:rest -> do
        align <- typeAlign fieldTy
        let aligned = alignUp offset align
        if name == field
          then pure (Just (fieldTy, baseOffset + if isUnion then 0 else aligned))
          else do
            size <- typeSize fieldTy
            nested <- if name == ""
              then anonymousMemberInfo (baseOffset + if isUnion then 0 else aligned) fieldTy field
              else pure Nothing
            case nested of
              Just info -> pure (Just info)
              Nothing -> nestedFieldOffset isUnion (aligned + size) rest

aggregateFields :: CType -> CompileM (Maybe (Bool, [Field]))
aggregateFields ty = case ty of
  CStructDef fields -> pure (Just (False, fields))
  CUnionDef fields -> pure (Just (True, fields))
  CStructNamed name fields -> do
    bindStruct name False fields
    pure (Just (False, fields))
  CUnionNamed name fields -> do
    bindStruct name True fields
    pure (Just (True, fields))
  CStruct name -> lookupStruct name
  CUnion name -> lookupStruct name
  CNamed name -> lookupStruct name
  _ -> pure Nothing

loadInstr :: Temp -> CType -> Operand -> CompileM Instr
loadInstr out ty addr = do
  size <- typeSize ty
  pure (if size <= 1 then ILoad8 out addr else if size <= 4 then ILoad32 out addr else ILoad64 out addr)

storeInstr :: CType -> Operand -> Operand -> CompileM Instr
storeInstr ty addr value = do
  size <- typeSize ty
  pure (if size <= 1 then IStore8 addr value else if size <= 4 then IStore32 addr value else IStore64 addr value)

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
  CPtr{} -> pure 8
  CArray inner count -> do
    size <- typeSize inner
    pure (size * maybe 1 id count)
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
  CEnum{} -> pure 4
  CNamed name -> namedTypeSize name

namedTypeSize :: String -> CompileM Int
namedTypeSize name
  | name `elem` ["int8_t", "uint8_t"] = pure 1
  | name `elem` ["int16_t", "uint16_t"] = pure 2
  | name `elem` ["int32_t", "uint32_t"] = pure 4
  | name `elem` ["int64_t", "uint64_t"] = pure 8
  | name `elem` ["size_t", "ssize_t", "time_t", "ptrdiff_t", "intptr_t", "uintptr_t", "addr_t"] = pure 8
  | otherwise = do
      fields <- lookupStruct name
      case fields of
        Just{} -> structSize name
        Nothing -> pure 8

typeAlign :: CType -> CompileM Int
typeAlign ty = do
  size <- typeSize ty
  pure (if size >= 8 then 8 else if size >= 4 then 4 else if size >= 2 then 2 else 1)

structSize :: String -> CompileM Int
structSize name = do
  aggregate <- lookupStruct name
  case aggregate of
    Nothing -> pure 8
    Just (isUnion, fields) -> aggregateSize isUnion fields

aggregateSize :: Bool -> [Field] -> CompileM Int
aggregateSize isUnion fields =
  if isUnion
    then unionSize fields
    else do
      (size, maxAlign) <- foldFields 0 1 fields
      pure (alignUp size maxAlign)
  where
    foldFields offset maxAlign members = case members of
      [] -> pure (offset, maxAlign)
      Field ty _:rest -> do
        align <- typeAlign ty
        size <- typeSize ty
        let aligned = alignUp offset align
        foldFields (aligned + size) (max maxAlign align) rest

    unionSize members = do
      (size, align) <- unionFields members
      pure (alignUp size align)

    unionFields members = case members of
      [] -> pure (0, 1)
      Field ty _:rest -> do
        size <- typeSize ty
        align <- typeAlign ty
        (restSize, restAlign) <- unionFields rest
        pure (max size restSize, max align restAlign)

alignUp :: Int -> Int -> Int
alignUp offset align =
  let remnant = offset `mod` align
  in if remnant == 0 then offset else offset + align - remnant

materialize :: Operand -> CompileM ([Instr], Temp)
materialize op = case op of
  OTemp temp -> pure ([], temp)
  OImm value -> do
    temp <- freshTemp
    pure ([IConst temp value], temp)
  OGlobal _ -> do
    temp <- freshTemp
    pure ([ICopy temp op], temp)

globalBytes :: Maybe Expr -> [Int]
globalBytes initExpr = int64Bytes (globalValue initExpr)

globalValue :: Maybe Expr -> Int
globalValue initExpr = case initExpr of
  Just (EInt text) -> parseInt text
  Just (EChar text) -> charValue text
  _ -> 0

int64Bytes :: Int -> [Int]
int64Bytes value = take 8 (go value) where
  go n = (n `mod` 256) : go (n `div` 256)

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
  "&" -> Just IAnd
  "|" -> Just IOr
  "^" -> Just IXor
  "&&" -> Just IAnd
  "||" -> Just IOr
  _ -> Nothing

parseInt :: String -> Int
parseInt text =
  let clean = stripIntSuffix text
  in case clean of
    '0':'x':xs -> readHex xs
    '0':'X':xs -> readHex xs
    _ -> readDecimalPrefix clean

readDecimalPrefix :: String -> Int
readDecimalPrefix text =
  let digits = takeWhile isDecimalDigit text
  in case reads digits of
    [(n, "")] -> n
    _ -> 0

isDecimalDigit :: Char -> Bool
isDecimalDigit c = c >= '0' && c <= '9'

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
