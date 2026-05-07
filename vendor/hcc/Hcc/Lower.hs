module Hcc.Lower
  ( lowerProgram
  , lowerProgramWithDataPrefix
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
lowerProgram = lowerProgramWithDataPrefix "HCC_DATA"

lowerProgramWithDataPrefix :: String -> Program -> Either CompileError ModuleIr
lowerProgramWithDataPrefix prefix (Program decls) = runCompileMWithDataPrefix prefix $ do
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
  let fileFields =
        [ Field CInt "fd"
        , Field CInt "bufmode"
        , Field CInt "bufpos"
        , Field CInt "file_pos"
        , Field CInt "buflen"
        , Field (CPtr CChar) "buffer"
        , Field (CPtr (CStruct "__IO_FILE")) "next"
        , Field (CPtr (CStruct "__IO_FILE")) "prev"
        ]
  bindStruct "__IO_FILE" False fileFields
  bindStruct "FILE" False fileFields

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
  Prototype{}:rest -> lowerTopDecls rest
  Global{}:rest -> lowerTopDecls rest
  ExternGlobals{}:rest -> lowerTopDecls rest
  Globals{}:rest -> lowerTopDecls rest
  StructDecl{}:rest -> lowerTopDecls rest
  EnumConstants{}:rest -> lowerTopDecls rest
  TypeDecl:rest -> lowerTopDecls rest

lowerFunction :: String -> [Param] -> [Stmt] -> CompileM FunctionIr
lowerFunction name params body = withErrorContext ("function " ++ name) $ withFunctionScope $ do
  bid <- freshBlock
  (names, paramInstrs) <- lowerParams 0 params
  blocks <- lowerStatementsFrom bid paramInstrs body (TRet (Just (OImm 0)))
  pure (FunctionIr name names blocks)

lowerParams :: Int -> [Param] -> CompileM ([String], [Instr])
lowerParams index params = case params of
  [] -> pure ([], [])
  Param ty name:rest -> do
    temp <- freshTemp
    bindVar name temp ty
    (names, instrs) <- lowerParams (index + 1) rest
    pure (name:names, IParam temp index:instrs)

paramNames :: [Param] -> [String]
paramNames params = case params of
  [] -> []
  Param _ name:rest -> name : paramNames rest

registerImplicitCalls :: [String] -> [Stmt] -> CompileM ()
registerImplicitCalls locals stmts = case stmts of
  [] -> pure ()
  stmt:rest -> do
    locals' <- registerImplicitCallsStmt locals stmt
    registerImplicitCalls locals' rest

registerImplicitCallsStmt :: [String] -> Stmt -> CompileM [String]
registerImplicitCallsStmt locals stmt = case stmt of
  SDecl _ name initExpr -> do
    maybeRegisterImplicitCallsExpr locals initExpr
    pure (name:locals)
  SDecls decls ->
    registerImplicitCallsDecls locals decls
  SReturn expr -> maybeRegisterImplicitCallsExpr locals expr >> pure locals
  SExpr expr -> registerImplicitCallsExpr locals expr >> pure locals
  SIf cond yes no -> do
    registerImplicitCallsExpr locals cond
    registerImplicitCalls locals yes
    registerImplicitCalls locals no
    pure locals
  SWhile cond body -> do
    registerImplicitCallsExpr locals cond
    registerImplicitCalls locals body
    pure locals
  SDoWhile body cond -> do
    registerImplicitCalls locals body
    registerImplicitCallsExpr locals cond
    pure locals
  SFor initExpr condExpr stepExpr body -> do
    maybeRegisterImplicitCallsExpr locals initExpr
    maybeRegisterImplicitCallsExpr locals condExpr
    maybeRegisterImplicitCallsExpr locals stepExpr
    registerImplicitCalls locals body
    pure locals
  SSwitch value body -> do
    registerImplicitCallsExpr locals value
    registerImplicitCalls locals (switchBodyStatements body)
    pure locals
  SCase expr -> registerImplicitCallsExpr locals expr >> pure locals
  SBlock body -> registerImplicitCalls locals body >> pure locals
  _ -> pure locals

registerImplicitCallsDecls :: [String] -> [(CType, String, Maybe Expr)] -> CompileM [String]
registerImplicitCallsDecls locals decls = case decls of
  [] -> pure locals
  (_, name, initExpr):rest -> do
    maybeRegisterImplicitCallsExpr locals initExpr
    registerImplicitCallsDecls (name:locals) rest

maybeRegisterImplicitCallsExpr :: [String] -> Maybe Expr -> CompileM ()
maybeRegisterImplicitCallsExpr locals expr = case expr of
  Nothing -> pure ()
  Just value -> registerImplicitCallsExpr locals value

registerImplicitCallsExpr :: [String] -> Expr -> CompileM ()
registerImplicitCallsExpr locals expr = case expr of
  ECall (EVar name) args -> do
    if name `elem` locals || name `elem` ignoredSideEffectCalls
      then pure ()
      else do
        global <- lookupGlobalType name
        case global of
          Just _ -> pure ()
          Nothing -> bindFunction name
    registerImplicitCallsExprs locals args
  ECall callee args -> do
    registerImplicitCallsExpr locals callee
    registerImplicitCallsExprs locals args
  EIndex base ix -> registerImplicitCallsExprs locals [base, ix]
  EMember base _ -> registerImplicitCallsExpr locals base
  EPtrMember base _ -> registerImplicitCallsExpr locals base
  EUnary _ value -> registerImplicitCallsExpr locals value
  ESizeofExpr value -> registerImplicitCallsExpr locals value
  ECast _ value -> registerImplicitCallsExpr locals value
  EPostfix _ value -> registerImplicitCallsExpr locals value
  EBinary _ left right -> registerImplicitCallsExprs locals [left, right]
  ECond cond yes no -> registerImplicitCallsExprs locals [cond, yes, no]
  EAssign left right -> registerImplicitCallsExprs locals [left, right]
  _ -> pure ()

registerImplicitCallsExprs :: [String] -> [Expr] -> CompileM ()
registerImplicitCallsExprs locals exprs = case exprs of
  [] -> pure ()
  expr:rest -> do
    registerImplicitCallsExpr locals expr
    registerImplicitCallsExprs locals rest

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
    (restId, restBlocks) <- if null rest
      then case defaultTerm of
        TJump target -> pure (target, [])
        _ -> do
          joinId <- freshBlock
          blocks <- lowerStatementsFrom joinId [] rest defaultTerm
          pure (joinId, blocks)
      else do
        joinId <- freshBlock
        blocks <- lowerStatementsFrom joinId [] rest defaultTerm
        pure (joinId, blocks)
    let noTarget = if null no then restId else noId
    yesBlocks <- lowerStatementsFrom yesId [] yes (TJump restId)
    noBlocks <- if null no
      then pure []
      else lowerStatementsFrom noId [] no (TJump restId)
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
    (condInstrs, condOp) <- lowerExpr cond
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
  let clauses = collectSwitchClauses (switchBodyStatements body)
  clauseIds <- freshBlocks (length clauses)
  let clausePairs = zip clauses clauseIds
  let defaultTarget = switchDefaultTarget restId clausePairs
  dispatchBlocks <- lowerSwitchDispatch dispatchId valueOp defaultTarget (switchCases clausePairs)
  bodyBlocks <- withBreakTarget restId (lowerSwitchClauses restId clausePairs)
  pure (dispatchBlocks ++ bodyBlocks)

switchBodyStatements :: [Stmt] -> [Stmt]
switchBodyStatements body = case body of
  [SBlock stmts] -> stmts
  _ -> body

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
    direct <- lookupFunction name
    if direct
      then do
        lowered <- lowerExprs args
        let instrs = concatMap fst lowered
        let ops = map snd lowered
        pure (instrs ++ [ICall Nothing name ops])
      else lowerIndirectSideEffect (EVar name) args
  ECall callee args -> do
    lowerIndirectSideEffect callee args
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

lowerIndirectSideEffect :: Expr -> [Expr] -> CompileM [Instr]
lowerIndirectSideEffect callee args = do
  (calleeInstrs, calleeOp) <- lowerExpr callee
  lowered <- lowerExprs args
  let instrs = concatMap fst lowered
  let ops = map snd lowered
  pure (calleeInstrs ++ instrs ++ [ICallIndirect Nothing calleeOp ops])

builtinConstant :: String -> Maybe Int
builtinConstant name = case name of
  "NULL" -> Just 0
  "__null" -> Just 0
  "__LINE__" -> Just 0
  "CH_EOB" -> Just 92
  "EINTR" -> Just 4
  "char" -> Just 1
  "short" -> Just 2
  "int" -> Just 4
  "long" -> Just 8
  "TOKSYM_TAL_LIMIT" -> Just 256
  "TOKSTR_TAL_LIMIT" -> Just 1024
  "TOKSYM_TAL_SIZE" -> Just (768 * 1024)
  "TOKSTR_TAL_SIZE" -> Just (768 * 1024)
  "TOK_ALLOC_INCR" -> Just 512
  "TOK_IDENT" -> Just 256
  "SYM_FIRST_ANOM" -> Just 268435456
  _ -> Nothing

lowerDecls :: [(CType, String, Maybe Expr)] -> CompileM [Instr]
lowerDecls decls = case decls of
  [] -> pure []
  (ty, name, initExpr):rest -> do
    instrs <- lowerDecl ty name initExpr
    tailInstrs <- lowerDecls rest
    pure (instrs ++ tailInstrs)

lowerDecl :: CType -> String -> Maybe Expr -> CompileM [Instr]
lowerDecl ty name initExpr = do
  staticData <- localStaticData ty initExpr
  aggregateStorage <- isAggregateTypeM ty
  temp <- freshTemp
  bindVar name temp ty
  case staticData of
    Just label -> do
      pure [ICopy temp (OGlobal label)]
    Nothing | aggregateStorage -> do
      size <- typeSize ty
      initInstrs <- case initExpr of
        Just expr -> do
          (exprInstrs, op) <- lowerExpr expr
          copyInstrs <- copyObject (OTemp temp) op ty
          pure (exprInstrs ++ copyInstrs)
        Nothing -> pure []
      pure (IAlloca temp size : initInstrs)
    Nothing -> case initExpr of
      Nothing -> do
        pure [IConst temp 0]
      Just expr -> do
        (exprInstrs, op) <- lowerExpr expr
        (coerceInstrs, coerceOp) <- coerceScalar ty op
        pure (exprInstrs ++ coerceInstrs ++ [ICopy temp coerceOp])

localStaticData :: CType -> Maybe Expr -> CompileM (Maybe String)
localStaticData ty initExpr = case (ty, initExpr) of
  (CArray{}, Just EInitList{}) -> localDataItem ty initExpr
  (CArray{}, Just EString{}) -> localDataItem ty initExpr
  (_, Just EInitList{}) -> do
    aggregateStorage <- isAggregateTypeM ty
    if aggregateStorage then localDataItem ty initExpr else pure Nothing
  _ -> pure Nothing

localDataItem :: CType -> Maybe Expr -> CompileM (Maybe String)
localDataItem ty initExpr = do
  dataLabel <- freshDataLabel
  values <- globalData ty initExpr
  addDataItem (DataItem dataLabel values)
  pure (Just dataLabel)

registerGlobals :: [(CType, String, Maybe Expr)] -> CompileM ()
registerGlobals globals = case globals of
  [] -> pure ()
  (ty, name, initExpr):rest -> do
    registerTypeAggregates ty
    bindGlobal name ty
    values <- globalData ty initExpr
    addDataItem (DataItem name values)
    registerGlobals rest

registerExternGlobals :: [(CType, String)] -> CompileM ()
registerExternGlobals globals = case globals of
  [] -> pure ()
  (ty, name):rest -> do
    registerTypeAggregates ty
    bindGlobal name ty
    registerExternGlobals rest

registerConstants :: [(String, Int)] -> CompileM ()
registerConstants constants = case constants of
  [] -> pure ()
  (name, value):rest -> do
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
    pure ([IConst temp (parseInt text)], OTemp temp)
  EChar text -> do
    temp <- freshTemp
    pure ([IConst temp (charValue text)], OTemp temp)
  EString text -> do
    dataLabel <- freshDataLabel
    addDataItem (DataItem dataLabel (bytesData (stringBytes text)))
    pure ([], OGlobal dataLabel)
  EVar name | Just value <- builtinConstant name ->
    pure ([], OImm value)
  EVar name -> do
    constant <- lookupConstant name
    case constant of
      Just value -> pure ([], OImm value)
      Nothing -> do
        local <- lookupVarMaybe name
        case local of
          Just temp -> pure ([], OTemp temp)
          Nothing -> do
            function <- lookupFunction name
            if function
              then pure ([], OFunction name)
              else do
                globalTy <- lookupGlobalType name
                case globalTy of
                  Just CArray{} -> pure ([], OGlobal name)
                  Just ty -> do
                    aggregateStorage <- isAggregateTypeM ty
                    if aggregateStorage
                      then pure ([], OGlobal name)
                      else do
                        out <- freshTemp
                        load <- loadInstr out ty (OGlobal name)
                        pure ([load], OTemp out)
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
  ECast CUnsignedChar x -> do
    (a, op) <- lowerExpr x
    (coerceInstrs, coerceOp) <- coerceScalar CUnsignedChar op
    pure (a ++ coerceInstrs, coerceOp)
  ECast _ x -> lowerExpr x
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
  EBinary op a b | op `elem` ["<", "<=", ">", ">="] -> do
    (ai, ao) <- lowerExpr a
    (bi, bo) <- lowerExpr b
    out <- freshTemp
    iop <- comparisonOp op a b
    pure (ai ++ bi ++ [IBin out iop ao bo], OTemp out)
  EBinary op a b | Just iop <- lowerBinOp op -> do
    if op == "<<"
      then lowerShiftExpr op a b
      else lowerPlainBin iop a b
  EIndex{} ->
    readLValueExpr expr
  EPtrMember{} ->
    readLValueExpr expr
  EMember{} ->
    readLValueExpr expr
  ECall (EVar name) args -> do
    direct <- lookupFunction name
    if direct
      then do
        lowered <- lowerExprs args
        out <- freshTemp
        let instrs = concatMap fst lowered
        let ops = map snd lowered
        pure (instrs ++ [ICall (Just out) name ops], OTemp out)
      else lowerIndirectCall (EVar name) args
  ECall callee args -> do
    lowerIndirectCall callee args
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

lowerIndirectCall :: Expr -> [Expr] -> CompileM ([Instr], Operand)
lowerIndirectCall callee args = do
  (calleeInstrs, calleeOp) <- lowerExpr callee
  lowered <- lowerExprs args
  out <- freshTemp
  let instrs = concatMap fst lowered
  let ops = map snd lowered
  pure (calleeInstrs ++ instrs ++ [ICallIndirect (Just out) calleeOp ops], OTemp out)

lowerLogicalAnd :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerLogicalAnd left right = do
  (leftInstrs, leftOp) <- lowerExpr left
  (rightInstrs, rightBool) <- lowerTruthExpr right
  out <- freshTemp
  pure ([ICond out leftInstrs leftOp rightInstrs rightBool [] (OImm 0)], OTemp out)

lowerLogicalOr :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerLogicalOr left right = do
  (leftInstrs, leftOp) <- lowerExpr left
  (rightInstrs, rightBool) <- lowerTruthExpr right
  out <- freshTemp
  pure ([ICond out leftInstrs leftOp [] (OImm 1) rightInstrs rightBool], OTemp out)

lowerTruthExpr :: Expr -> CompileM ([Instr], Operand)
lowerTruthExpr expr = do
  (instrs, op) <- lowerExpr expr
  out <- freshTemp
  pure (instrs ++ [IBin out INe op (OImm 0)], OTemp out)

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
  case (pointerElementType aty, pointerElementType bty) of
    (Just elemTy, _) -> lowerPointerOffset IAdd a b elemTy
    (_, Just elemTy) -> lowerPointerOffset IAdd b a elemTy
    _ -> lowerPlainBin IAdd a b

lowerSubExpr :: Expr -> Expr -> CompileM ([Instr], Operand)
lowerSubExpr a b = do
  aty <- exprType a
  bty <- exprType b
  case (pointerElementType aty, pointerElementType bty) of
    (Just elemTy, Just _) -> do
      (ai, ao) <- lowerExpr a
      (bi, bo) <- lowerExpr b
      diff <- freshTemp
      out <- freshTemp
      size <- typeSize elemTy
      pure (ai ++ bi ++ [IBin diff ISub ao bo, IBin out IDiv (OTemp diff) (OImm size)], OTemp out)
    (Just elemTy, Nothing) -> lowerPointerOffset ISub a b elemTy
    _ -> lowerPlainBin ISub a b

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
  (acoerceInstrs, acoerceOp) <- coerceScalar commonTy ao
  (bcoerceInstrs, bcoerceOp) <- coerceScalar commonTy bo
  out <- freshTemp
  let resultTy = if isComparisonBinOp op then CInt else commonTy
  (coerceInstrs, coerceOp) <- coerceScalar resultTy (OTemp out)
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
  LLocal temp _ ->
    pure ([], OTemp temp)
  LAddress addr ty -> case ty of
    CArray{} -> pure ([], addr)
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
  pure ([IBin out IAnd op (OImm (byteMask size))], OTemp out)

signExtendScalar :: Int -> Operand -> CompileM ([Instr], Operand)
signExtendScalar size op = do
  masked <- freshTemp
  flipped <- freshTemp
  out <- freshTemp
  let signBit = pow2 (size * 8 - 1)
  pure ( [ IBin masked IAnd op (OImm (byteMask size))
         , IBin flipped IXor (OTemp masked) (OImm signBit)
         , IBin out ISub (OTemp flipped) (OImm signBit)
         ]
       , OTemp out)

byteMask :: Int -> Int
byteMask size = pow2 (size * 8) - 1

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
      (dstInstrs, dstAddr) <- offsetAddress dst offset
      (srcInstrs, srcAddr) <- offsetAddress src offset
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
lowerLValueAddress (EVar name) = do
  local <- lookupVarMaybe name
  case local of
    Nothing -> do
      function <- lookupFunction name
      if function
        then pure ([], OFunction name)
        else lowerNonFunctionAddress
    Just _ ->
      lowerNonFunctionAddress
  where
    lowerNonFunctionAddress = do
      (instrs, lvalue) <- lowerLValue (EVar name)
      case lvalue of
        LAddress addr _ -> pure (instrs, addr)
        LLocal temp ty -> do
          aggregateStorage <- isAggregateTypeM ty
          if aggregateStorage
            then pure (instrs, OTemp temp)
            else do
              out <- freshTemp
              pure (instrs ++ [IAddrOf out temp], OTemp out)
lowerLValueAddress target = do
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
  ESizeofType{} -> pure (Just CInt)
  ESizeofExpr{} -> pure (Just CInt)
  EVar name -> do
    local <- lookupVarType name
    case local of
      Just ty -> pure (Just ty)
      Nothing -> lookupGlobalType name
  ECast ty _ -> pure (Just ty)
  EUnary "+" value -> do
    mty <- exprType value
    maybe (pure Nothing) (fmap Just . promoteIntegerType) mty
  EUnary "-" value -> do
    mty <- exprType value
    maybe (pure Nothing) (fmap Just . promoteIntegerType) mty
  EUnary "~" value -> do
    mty <- exprType value
    maybe (pure Nothing) (fmap Just . promoteIntegerType) mty
  EUnary "!" _ -> pure (Just CInt)
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
  EBinary "+" left right -> do
    leftTy <- exprType left
    rightTy <- exprType right
    arithmeticTy <- usualArithmeticType left right
    pure (case (pointerElementType leftTy, pointerElementType rightTy) of
      (Just{}, _) -> leftTy
      (_, Just{}) -> rightTy
      _ -> Just arithmeticTy)
  EBinary "-" left right -> do
    leftTy <- exprType left
    rightTy <- exprType right
    arithmeticTy <- usualArithmeticType left right
    pure (case (pointerElementType leftTy, pointerElementType rightTy) of
      (Just{}, Just{}) -> Just CLong
      (Just{}, Nothing) -> leftTy
      _ -> Just arithmeticTy)
  EBinary "<<" left _ -> do
    leftTy <- exprType left
    maybe (pure Nothing) (fmap Just . promoteIntegerType) leftTy
  EBinary ">>" left _ -> do
    leftTy <- exprType left
    maybe (pure Nothing) (fmap Just . promoteIntegerType) leftTy
  EBinary "," _ right -> exprType right
  EBinary "&&" _ _ -> pure (Just CInt)
  EBinary "||" _ _ -> pure (Just CInt)
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
  CEnum{} -> True
  CNamed name -> isSignedNamedInteger name
  _ -> False

isSignedNamedInteger :: String -> Bool
isSignedNamedInteger name
  | name `elem` signedNamedIntegerTypes = True
  | otherwise = False

isIntegerTypeM :: CType -> CompileM Bool
isIntegerTypeM ty = case ty of
  CChar -> pure True
  CUnsignedChar -> pure True
  CInt -> pure True
  CUnsigned -> pure True
  CLong -> pure True
  CEnum{} -> pure True
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
  EInt text | intLiteralIsUnsigned text -> pure CUnsigned
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
namedTypeSize name = case namedIntegerSize name of
  Just size -> pure size
  Nothing -> do
      fields <- lookupStruct name
      case fields of
        Just{} -> structSize name
        Nothing -> pure 8

namedIntegerSize :: String -> Maybe Int
namedIntegerSize name
  | name `elem` ["int8_t", "uint8_t"] = Just 1
  | name `elem` ["signed_short", "unsigned_short", "int16_t", "uint16_t", "Elf32_Half", "Elf64_Half", "Elf32_Section", "Elf64_Section", "Elf32_Versym", "Elf64_Versym"] = Just 2
  | name `elem` ["int32_t", "uint32_t", "Elf32_Word", "Elf64_Word", "Elf32_Sword", "Elf64_Sword", "Elf32_Addr", "Elf32_Off"] = Just 4
  | name `elem` ["unsigned_long", "int64_t", "uint64_t", "size_t", "ssize_t", "time_t", "ptrdiff_t", "intptr_t", "uintptr_t", "addr_t", "Elf32_Xword", "Elf32_Sxword", "Elf64_Xword", "Elf64_Sxword", "Elf64_Addr", "Elf64_Off"] = Just 8
  | otherwise = Nothing

signedNamedIntegerTypes :: [String]
signedNamedIntegerTypes =
  [ "signed_short", "int8_t", "int16_t", "int32_t", "int64_t"
  , "ssize_t", "time_t", "ptrdiff_t", "intptr_t"
  , "Elf32_Sword", "Elf64_Sword", "Elf32_Sxword", "Elf64_Sxword"
  ]

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

globalData :: CType -> Maybe Expr -> CompileM [DataValue]
globalData ty initExpr = do
  values <- globalDataValue ty initExpr
  size <- initializedSize ty values initExpr
  pure (padData size values)

initializedSize :: CType -> [DataValue] -> Maybe Expr -> CompileM Int
initializedSize ty values initExpr = case (ty, initExpr) of
  (CArray _ Nothing, Just EInitList{}) -> pure (dataSize values)
  (CArray CChar Nothing, Just EString{}) -> pure (dataSize values)
  _ -> typeSize ty

globalDataValue :: CType -> Maybe Expr -> CompileM [DataValue]
globalDataValue ty initExpr = case (ty, initExpr) of
  (_, Just (EInitList [expr])) | not (isAggregateType ty) ->
    globalDataValue ty (Just expr)
  (CArray CChar count, Just (EString text)) ->
    pure (padData (maybe (length (stringBytes text)) id count) (bytesData (stringBytes text)))
  (CArray inner count, Just (EInitList exprs)) -> do
    items <- globalArrayData inner exprs
    case count of
      Nothing -> pure items
      Just n -> do
        elemSize <- typeSize inner
        pure (padData (n * elemSize) items)
  (_, Just (EInitList exprs)) -> do
    aggregate <- aggregateFields ty
    case aggregate of
      Just (False, fields) -> globalStructData fields exprs
      Just (True, fields) -> globalUnionData fields exprs
      Nothing -> zeroData <$> typeSize ty
  (_, Just (EString text)) | isPointerType ty -> do
    dataLabel <- freshDataLabel
    addDataItem (DataItem dataLabel (bytesData (stringBytes text)))
    pure [DAddress dataLabel]
  (_, Just (EInt text)) -> scalarData ty (parseInt text)
  (_, Just (EChar text)) -> scalarData ty (charValue text)
  (_, Just (ECast _ expr)) -> globalDataValue ty (Just expr)
  (_, Just (EUnary "&" (EVar name))) -> globalAddressData name
  (_, Just (EVar name)) -> do
    constant <- lookupConstant name
    case constant of
      Just value -> scalarData ty value
      Nothing -> case builtinConstant name of
        Just value -> scalarData ty value
        Nothing -> globalAddressData name
  (_, Just expr) -> do
    value <- constExprValue expr
    scalarData ty value
  _ -> zeroData <$> typeSize ty

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
  (values, used) <- structFields 0 fields exprs
  pure (padData used values)
  where
    structFields offset remaining values = case remaining of
      [] -> pure ([], offset)
      Field fieldTy _:rest -> do
        align <- typeAlign fieldTy
        let aligned = alignUp offset align
        fieldSize <- typeSize fieldTy
        let (mexpr, tailExprs) = case values of
              [] -> (Nothing, [])
              expr:xs -> (Just expr, xs)
        fieldData <- globalDataValue fieldTy mexpr
        (restData, end) <- structFields (aligned + fieldSize) rest tailExprs
        pure (zeroData (aligned - offset) ++ padData fieldSize fieldData ++ restData, end)

globalUnionData :: [Field] -> [Expr] -> CompileM [DataValue]
globalUnionData fields exprs = case (fields, exprs) of
  (Field fieldTy _:_, expr:_) -> do
    item <- globalDataValue fieldTy (Just expr)
    size <- unionSizeFromFields fields
    pure (padData size item)
  _ -> zeroData <$> unionSizeFromFields fields

unionSizeFromFields :: [Field] -> CompileM Int
unionSizeFromFields fields = case fields of
  [] -> pure 0
  Field ty _:rest -> do
    size <- typeSize ty
    tailSize <- unionSizeFromFields rest
    pure (max size tailSize)

isAggregateType :: CType -> Bool
isAggregateType ty = case ty of
  CArray{} -> True
  CStruct{} -> True
  CUnion{} -> True
  CStructNamed{} -> True
  CUnionNamed{} -> True
  CStructDef{} -> True
  CUnionDef{} -> True
  CNamed{} -> True
  _ -> False

isAggregateTypeM :: CType -> CompileM Bool
isAggregateTypeM ty = case ty of
  CArray{} -> pure True
  CNamed{} -> do
    aggregate <- aggregateFields ty
    pure (maybe False (const True) aggregate)
  _ -> pure (isAggregateType ty)

isPointerType :: CType -> Bool
isPointerType ty = case ty of
  CPtr{} -> True
  CNamed name -> name `elem` ["intptr_t", "uintptr_t"]
  _ -> False

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
  ECast _ (EUnary "&" (EPtrMember (ECast (CPtr ty) (EInt "0")) field)) -> do
    (_, offset) <- memberInfo (Just (CPtr ty)) field
    pure offset
  EUnary "&" (EPtrMember (ECast (CPtr ty) (EInt "0")) field) -> do
    (_, offset) <- memberInfo (Just (CPtr ty)) field
    pure offset
  EVar name -> do
    constant <- lookupConstant name
    pure (maybe (maybe 0 id (builtinConstant name)) id constant)
  ECast _ value -> constExprValue value
  EUnary "-" value -> negate <$> constExprValue value
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

constBinOp :: String -> Int -> Int -> Int
constBinOp op a b = case op of
  "+" -> a + b
  "-" -> a - b
  "*" -> a * b
  "/" -> if b == 0 then 0 else a `div` b
  "%" -> if b == 0 then 0 else a `mod` b
  "<<" -> a * pow2 b
  ">>" -> a `div` pow2 b
  "|" -> bitOr a b
  "&" -> bitAnd a b
  "^" -> bitXor a b
  "==" -> truthInt (a == b)
  "!=" -> truthInt (a /= b)
  "<" -> truthInt (a < b)
  "<=" -> truthInt (a <= b)
  ">" -> truthInt (a > b)
  ">=" -> truthInt (a >= b)
  "&&" -> truthInt (a /= 0 && b /= 0)
  "||" -> truthInt (a /= 0 || b /= 0)
  _ -> 0

truthInt :: Bool -> Int
truthInt value = if value then 1 else 0

pow2 :: Int -> Int
pow2 n = if n <= 0 then 1 else 2 * pow2 (n - 1)

bitAnd :: Int -> Int -> Int
bitAnd a b = bitFold 1 a b 0 (\x y -> x /= 0 && y /= 0)

bitOr :: Int -> Int -> Int
bitOr a b = bitFold 1 a b 0 (\x y -> x /= 0 || y /= 0)

bitXor :: Int -> Int -> Int
bitXor a b = bitFold 1 a b 0 (\x y -> (x /= 0) /= (y /= 0))

bitFold :: Int -> Int -> Int -> Int -> (Int -> Int -> Bool) -> Int
bitFold bit a b out f =
  if bit > 1073741824
    then out
    else
      let abit = a `mod` (bit * 2) `div` bit
          bbit = b `mod` (bit * 2) `div` bit
          out' = if f abit bbit then out + bit else out
      in bitFold (bit * 2) a b out' f

padData :: Int -> [DataValue] -> [DataValue]
padData size values =
  let used = dataSize values
  in if used >= size then takeData size values else values ++ zeroData (size - used)

takeData :: Int -> [DataValue] -> [DataValue]
takeData size values =
  if size <= 0 then [] else case values of
    [] -> []
    DByte byte:rest -> DByte byte : takeData (size - 1) rest
    DAddress label:rest ->
      if size >= 8 then DAddress label : takeData (size - 8) rest else zeroData size

dataSize :: [DataValue] -> Int
dataSize values = case values of
  [] -> 0
  DByte{}:rest -> 1 + dataSize rest
  DAddress{}:rest -> 8 + dataSize rest

zeroData :: Int -> [DataValue]
zeroData n = if n <= 0 then [] else DByte 0 : zeroData (n - 1)

bytesData :: [Int] -> [DataValue]
bytesData bytes = case bytes of
  [] -> []
  byte:rest -> DByte byte : bytesData rest

intBytes :: Int -> Int -> [Int]
intBytes size value = take size (go value) where
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
  "&" -> Just IAnd
  "|" -> Just IOr
  "^" -> Just IXor
  "&&" -> Just IAnd
  "||" -> Just IOr
  _ -> Nothing

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
  CPtr{} -> True
  CArray{} -> True
  CNamed name -> case namedIntegerSize name of
    Just{} -> not (name `elem` signedNamedIntegerTypes)
    Nothing -> False
  _ -> False

intLiteralIsUnsigned :: String -> Bool
intLiteralIsUnsigned text = case text of
  [] -> False
  c:rest -> c == 'u' || c == 'U' || intLiteralIsUnsigned rest

parseInt :: String -> Int
parseInt text =
  let clean = stripIntSuffix text
  in case clean of
    '0':'x':xs -> readHex xs
    '0':'X':xs -> readHex xs
    '0':xs -> readOctal xs
    _ -> readDecimalPrefix clean

readDecimalPrefix :: String -> Int
readDecimalPrefix text =
  let digits = takeWhile isDecimalDigit text
  in case reads digits of
    [(n, "")] -> n
    _ -> 0

isDecimalDigit :: Char -> Bool
isDecimalDigit c = c >= '0' && c <= '9'

readOctal :: String -> Int
readOctal = go 0 where
  go n xs = case xs of
    [] -> n
    c:rest | c >= '0' && c <= '7' -> go (n * 8 + fromEnum c - fromEnum '0') rest
    _ -> n

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
  '\'':'\\':'r':'\'':[] -> 13
  '\'':'\\':'f':'\'':[] -> 12
  '\'':'\\':'v':'\'':[] -> 11
  '\'':'\\':'a':'\'':[] -> 7
  '\'':'\\':'b':'\'':[] -> 8
  '\'':'\\':'\\':'\'':[] -> 92
  '\'':'\\':'\'':'\'':[] -> 39
  '\'':'\\':'"':'\'':[] -> 34
  '\'':'\\':'0':'\'':[] -> 0
  '\'':c:'\'':[] -> fromEnum c
  _ -> 0

stringBytes :: String -> [Int]
stringBytes text = go (stripQuotes text) where
  go chars = case chars of
    [] -> [0]
    '\\':'n':rest -> 10 : go rest
    '\\':'t':rest -> 9 : go rest
    '\\':'r':rest -> 13 : go rest
    '\\':'f':rest -> 12 : go rest
    '\\':'v':rest -> 11 : go rest
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
