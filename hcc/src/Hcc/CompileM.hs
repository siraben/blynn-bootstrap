module CompileM
  ( CompileError(..)
  , CompileState(..)
  , CompileM(..)
  , Step(..)
  , runCompileM
  , initialCompileState
  , initialCompileStateForTarget
  , throwC
  , withErrorContext
  , freshTemp
  , freshBlock
  , freshLabel
  , freshDataLabel
  , addDataItem
  , bindVar
  , bindStruct
  , bindGlobal
  , bindConstant
  , bindFunction
  , bindFunctionType
  , bindSymbolAlias
  , resolveSymbolName
  , lookupVarMaybe
  , lookupVarType
  , lookupGlobalType
  , lookupConstant
  , lookupFunction
  , lookupFunctionType
  , lookupStruct
  , lookupStructSizeCache
  , cacheStructSize
  , lookupStructMemberCache
  , cacheStructMember
  , targetWordSize
  , currentFunctionName
  , withCurrentFunction
  , currentReturnType
  , currentReturnSlot
  , withCurrentReturnSlot
  , withFunctionScope
  , withVarScope
  , withLoopTargets
  , withBreakTarget
  , withSwitchCaseTargets
  , currentBreakTarget
  , currentContinueTarget
  , nextSwitchCaseTarget
  , labelBlock
  ) where

import Base
import TextUtil
import TypesAst
import TypesIr
import ScopeMap
import SymbolTable

data CompileError = CompileError String

data CompileState = CompileState
  { csNextTemp :: Int
  , csNextBlock :: Int
  , csNextLabel :: Int
  , csDataPrefix :: String
  , csVars :: ScopeMap (Temp, CType)
  , csStructs :: SymbolMap (Bool, [Field])
  , csStructSizes :: SymbolMap Int
  , csStructMembers :: SymbolMap (SymbolMap (CType, Int))
  , csGlobals :: SymbolMap CType
  , csConstants :: SymbolMap Int
  , csFunctions :: SymbolSet
  , csFunctionTypes :: SymbolMap CType
  , csSymbolAliases :: SymbolMap String
  , csLabels :: SymbolMap BlockId
  , csDataItems :: [DataItem]
  , csBreakTargets :: [BlockId]
  , csContinueTargets :: [BlockId]
  , csSwitchCaseTargets :: [[(Maybe Expr, BlockId)]]
  , csTargetBits :: Int
  , csCurrentFunction :: Maybe String
  , csCurrentReturnSlot :: Maybe Temp
  }

-- | Result of one CompileM step. Uses a single constructor instead of
-- the equivalent @Either CompileError (a, CompileState)@: saves the
-- outer @Right@ + the @(,)@ tuple, i.e. ~2 cells per successful bind.
data Step a = StepOk a CompileState | StepErr CompileError

data CompileM a = CompileM
  { unCompileM :: CompileState -> Step a
  }

instance Functor CompileM where
  fmap f action = CompileM $ \st -> case unCompileM action st of
    StepErr err -> StepErr err
    StepOk x st' -> StepOk (f x) st'

instance Applicative CompileM where
  pure x = CompileM $ \st -> StepOk x st
  ff <*> fx = CompileM $ \st -> case unCompileM ff st of
    StepErr err -> StepErr err
    StepOk f st' -> case unCompileM fx st' of
      StepErr err -> StepErr err
      StepOk x st'' -> StepOk (f x) st''

instance Monad CompileM where
  return = pure
  action >>= next = CompileM $ \st -> case unCompileM action st of
    StepErr err -> StepErr err
    StepOk x st' -> unCompileM (next x) st'

-- | Adapter for callers that still want an 'Either' boundary
-- representation: convert at the boundary, but the internal monad
-- traffic uses 'Step'.
runCompileM :: CompileM a -> CompileState -> Either CompileError (a, CompileState)
runCompileM action st = case unCompileM action st of
  StepErr err -> Left err
  StepOk x st' -> Right (x, st')

initialCompileState :: CompileState
initialCompileState = CompileState
  { csNextTemp = 0
  , csNextBlock = 0
  , csNextLabel = 0
  , csDataPrefix = "HCC_DATA"
  , csVars = scopeMapEmpty
  , csStructs = symbolMapEmpty
  , csStructSizes = symbolMapEmpty
  , csStructMembers = symbolMapEmpty
  , csGlobals = symbolMapEmpty
  , csConstants = symbolMapEmpty
  , csFunctions = symbolSetEmpty
  , csFunctionTypes = symbolMapEmpty
  , csSymbolAliases = symbolMapEmpty
  , csLabels = symbolMapEmpty
  , csDataItems = []
  , csBreakTargets = []
  , csContinueTargets = []
  , csSwitchCaseTargets = []
  , csTargetBits = 64
  , csCurrentFunction = Nothing
  , csCurrentReturnSlot = Nothing
  }

initialCompileStateForTarget :: String -> Int -> CompileState
initialCompileStateForTarget prefix bits =
  initialCompileState { csDataPrefix = prefix, csTargetBits = bits }

throwC :: String -> CompileM a
throwC msg = CompileM $ \_ -> StepErr (CompileError msg)

withErrorContext :: String -> CompileM a -> CompileM a
withErrorContext context action = CompileM $ \st ->
  case unCompileM action st of
    StepErr (CompileError msg) -> StepErr (CompileError (context ++ ": " ++ msg))
    StepOk x st' -> StepOk x st'

getC :: (CompileState -> a) -> CompileM a
getC f = CompileM $ \st -> StepOk (f st) st

modifyC :: (CompileState -> CompileState) -> CompileM ()
modifyC f = CompileM $ \st -> StepOk () (f st)

freshTemp :: CompileM Temp
freshTemp = CompileM $ \st ->
  let n = csNextTemp st
  in StepOk (Temp n) (st { csNextTemp = n + 1 })

freshBlock :: CompileM BlockId
freshBlock = CompileM $ \st ->
  let n = csNextBlock st
  in StepOk (BlockId n) (st { csNextBlock = n + 1 })

freshLabel :: CompileM String
freshLabel = CompileM $ \st ->
  let n = csNextLabel st
  in StepOk ("L" ++ show n) (st { csNextLabel = n + 1 })

freshDataLabel :: CompileM String
freshDataLabel = do
  label <- freshLabel
  prefix <- getC csDataPrefix
  pure (prefix ++ "_" ++ label)

addDataItem :: DataItem -> CompileM ()
addDataItem item =
  -- Every caller obtains the label immediately beforehand with
  -- freshDataLabel, so it cannot replace an existing pending item.  Filtering
  -- the whole list here made translation units with many string literals
  -- quadratic in their pending data count.
  modifyC $ \st -> st { csDataItems = item : csDataItems st }

bindVar :: String -> Temp -> CType -> CompileM ()
bindVar name temp ty =
  modifyC $ \st -> st { csVars = scopeMapInsert name (temp, ty) (csVars st) }

bindStruct :: String -> Bool -> [Field] -> CompileM ()
bindStruct name isUnion fields =
  modifyC $ \st -> st
    { csStructs = symbolMapInsert name (isUnion, fields) (csStructs st)
    , csStructSizes = symbolMapDelete name (csStructSizes st)
    , csStructMembers = symbolMapDelete name (csStructMembers st)
    }

bindGlobal :: String -> CType -> CompileM ()
bindGlobal name ty = do
  rejectReservedSymbol "global" name
  resolved <- resolveSymbolName name
  modifyC $ \st -> st { csGlobals = symbolMapInsert resolved ty (csGlobals st) }

rejectReservedSymbol :: String -> String -> CompileM ()
rejectReservedSymbol kind name =
  when ("FUNCTION_" `prefixOf` name || "HCC_DATA_" `prefixOf` name)
    (throwC (kind ++ " name " ++ show name ++ " uses a reserved HCC label prefix"))

bindConstant :: String -> Int -> CompileM ()
bindConstant name value =
  modifyC $ \st -> st { csConstants = symbolMapInsert name value (csConstants st) }

bindFunction :: String -> CompileM ()
bindFunction name = do
  rejectReservedSymbol "function" name
  resolved <- resolveSymbolName name
  modifyC $ \st -> st { csFunctions = symbolSetInsert resolved (csFunctions st) }

bindFunctionType :: String -> CType -> [Param] -> CompileM ()
bindFunctionType name retTy params = do
  rejectReservedSymbol "function" name
  resolved <- resolveSymbolName name
  modifyC $ \st -> st
    { csFunctions = symbolSetInsert resolved (csFunctions st)
    , csFunctionTypes = symbolMapInsert resolved (CFunc retTy (paramTypes params)) (csFunctionTypes st)
    }

bindSymbolAlias :: String -> String -> CompileM ()
bindSymbolAlias public resolved = do
  rejectReservedSymbol "symbol alias" public
  rejectReservedSymbol "symbol alias" resolved
  modifyC $ \st -> st { csSymbolAliases = symbolMapInsert public resolved (csSymbolAliases st) }

resolveSymbolName :: String -> CompileM String
resolveSymbolName name = getC $ \st ->
  case symbolMapLookup name (csSymbolAliases st) of
    Just resolved -> resolved
    Nothing -> name

lookupVarMaybe :: String -> CompileM (Maybe Temp)
lookupVarMaybe name = getC (fmap fst . scopeMapLookup name . csVars)

lookupVarType :: String -> CompileM (Maybe CType)
lookupVarType name = getC (fmap snd . scopeMapLookup name . csVars)

lookupGlobalType :: String -> CompileM (Maybe CType)
lookupGlobalType name = do
  resolved <- resolveSymbolName name
  getC (symbolMapLookup resolved . csGlobals)

lookupConstant :: String -> CompileM (Maybe Int)
lookupConstant name = getC (symbolMapLookup name . csConstants)

lookupFunction :: String -> CompileM Bool
lookupFunction name = do
  resolved <- resolveSymbolName name
  getC (symbolSetMember resolved . csFunctions)

lookupFunctionType :: String -> CompileM (Maybe CType)
lookupFunctionType name = do
  resolved <- resolveSymbolName name
  getC (symbolMapLookup resolved . csFunctionTypes)

lookupStruct :: String -> CompileM (Maybe (Bool, [Field]))
lookupStruct name = getC (symbolMapLookup name . csStructs)

lookupStructSizeCache :: String -> CompileM (Maybe Int)
lookupStructSizeCache name = getC (symbolMapLookup name . csStructSizes)

cacheStructSize :: String -> Int -> CompileM ()
cacheStructSize name size =
  modifyC $ \st -> st { csStructSizes = symbolMapInsert name size (csStructSizes st) }

lookupStructMemberCache :: String -> String -> CompileM (Maybe (CType, Int))
lookupStructMemberCache structName fieldName = CompileM $ \st ->
  case symbolMapLookup structName (csStructMembers st) of
    Nothing -> StepOk Nothing st
    Just members -> StepOk (symbolMapLookup fieldName members) st

cacheStructMember :: String -> String -> (CType, Int) -> CompileM ()
cacheStructMember structName fieldName info =
  modifyC $ \st ->
  let members = case symbolMapLookup structName (csStructMembers st) of
        Just existing -> existing
        Nothing -> symbolMapEmpty
      members' = symbolMapInsert fieldName info members
  in st { csStructMembers = symbolMapInsert structName members' (csStructMembers st) }

targetBits :: CompileM Int
targetBits = getC csTargetBits

targetWordSize :: CompileM Int
targetWordSize = do
  bits <- targetBits
  pure (if bits == 32 then 4 else 8)

currentFunctionName :: CompileM (Maybe String)
currentFunctionName = getC csCurrentFunction

withCurrentFunction :: String -> CompileM a -> CompileM a
withCurrentFunction name action = CompileM $ \st ->
  case unCompileM action st { csCurrentFunction = Just name } of
    StepErr err -> StepErr err
    StepOk x st' -> StepOk x (st' { csCurrentFunction = csCurrentFunction st })

currentReturnType :: CompileM (Maybe CType)
currentReturnType = do
  mname <- currentFunctionName
  case mname of
    Nothing -> pure Nothing
    Just name -> do
      mty <- lookupFunctionType name
      case mty of
        Just (CFunc retTy _) -> pure (Just retTy)
        _ -> pure Nothing

currentReturnSlot :: CompileM (Maybe Temp)
currentReturnSlot = getC csCurrentReturnSlot

withCurrentReturnSlot :: Maybe Temp -> CompileM a -> CompileM a
withCurrentReturnSlot slot action = CompileM $ \st ->
  case unCompileM action st { csCurrentReturnSlot = slot } of
    StepErr err -> StepErr err
    StepOk x st' -> StepOk x (st' { csCurrentReturnSlot = csCurrentReturnSlot st })

withFunctionScope :: CompileM a -> CompileM a
withFunctionScope action = CompileM $ \st ->
  case unCompileM action st
    { csVars = scopeMapEmpty
    , csLabels = symbolMapEmpty
    , csBreakTargets = []
    , csContinueTargets = []
    , csSwitchCaseTargets = []
    , csCurrentReturnSlot = Nothing
    } of
    StepErr err -> StepErr err
    StepOk x st' -> StepOk x (st'
      { csVars = csVars st
      , csLabels = csLabels st
      , csStructs = csStructs st
      , csStructSizes = csStructSizes st
      , csStructMembers = csStructMembers st
      , csConstants = csConstants st
      , csBreakTargets = csBreakTargets st
      , csContinueTargets = csContinueTargets st
      , csSwitchCaseTargets = csSwitchCaseTargets st
      , csCurrentReturnSlot = csCurrentReturnSlot st
      })

withVarScope :: CompileM a -> CompileM a
withVarScope action = CompileM $ \st ->
  case unCompileM action st { csVars = scopeMapEnter (csVars st) } of
    StepErr err -> StepErr err
    StepOk x st' -> StepOk x (st'
      { csVars = scopeMapLeave (csVars st')
      , csStructs = csStructs st
      , csStructSizes = csStructSizes st
      , csStructMembers = csStructMembers st
      , csConstants = csConstants st
      })

withLoopTargets :: BlockId -> BlockId -> CompileM a -> CompileM a
withLoopTargets breakTarget continueTarget action = CompileM $ \st ->
  case unCompileM action st
    { csBreakTargets = breakTarget : csBreakTargets st
    , csContinueTargets = continueTarget : csContinueTargets st
    } of
    StepErr err -> StepErr err
    StepOk x st' -> StepOk x (st'
      { csBreakTargets = csBreakTargets st
      , csContinueTargets = csContinueTargets st
      })

withBreakTarget :: BlockId -> CompileM a -> CompileM a
withBreakTarget breakTarget action = CompileM $ \st ->
  case unCompileM action st { csBreakTargets = breakTarget : csBreakTargets st } of
    StepErr err -> StepErr err
    StepOk x st' -> StepOk x (st' { csBreakTargets = csBreakTargets st })

withSwitchCaseTargets :: [(Maybe Expr, BlockId)] -> CompileM a -> CompileM a
withSwitchCaseTargets targets action = CompileM $ \st ->
  case unCompileM action st { csSwitchCaseTargets = targets : csSwitchCaseTargets st } of
    StepErr err -> StepErr err
    StepOk x st' -> StepOk x (st' { csSwitchCaseTargets = csSwitchCaseTargets st })

currentBreakTarget :: CompileM (Maybe BlockId)
currentBreakTarget = getC (listHead . csBreakTargets)

currentContinueTarget :: CompileM (Maybe BlockId)
currentContinueTarget = getC (listHead . csContinueTargets)

listHead :: [a] -> Maybe a
listHead [] = Nothing
listHead (x:_) = Just x

nextSwitchCaseTarget :: Maybe Expr -> CompileM BlockId
nextSwitchCaseTarget label = CompileM $ \st -> case csSwitchCaseTargets st of
  [] -> StepErr (CompileError "case label outside switch")
  []:_ -> StepErr (CompileError "unexpected switch case label")
  targets:_ -> case lookupSwitchCaseTarget label targets of
    Just target -> StepOk target st
    Nothing -> StepErr (CompileError "case label outside switch")

lookupSwitchCaseTarget :: Maybe Expr -> [(Maybe Expr, BlockId)] -> Maybe BlockId
lookupSwitchCaseTarget label targets = case targets of
  [] -> Nothing
  (targetLabel, target):rest ->
    if sameSwitchLabel label targetLabel
      then Just target
      else lookupSwitchCaseTarget label rest

sameSwitchLabel :: Maybe Expr -> Maybe Expr -> Bool
sameSwitchLabel a b = case (a, b) of
  (Nothing, Nothing) -> True
  (Just x, Just y) -> sameExpr x y
  _ -> False

sameExpr :: Expr -> Expr -> Bool
sameExpr a b = case (a, b) of
  (EInt x, EInt y) -> x == y
  (EChar x, EChar y) -> x == y
  (EString x, EString y) -> x == y
  (EVar x, EVar y) -> x == y
  (EUnary opX x, EUnary opY y) -> opX == opY && sameExpr x y
  (EBinary opX xl xr, EBinary opY yl yr) -> opX == opY && sameExpr xl yl && sameExpr xr yr
  (ECond xc xy xn, ECond yc yy yn) -> sameExpr xc yc && sameExpr xy yy && sameExpr xn yn
  (ECast _ x, ECast _ y) -> sameExpr x y
  _ -> False

labelBlock :: String -> CompileM BlockId
labelBlock name = CompileM $ \st -> case symbolMapLookup name (csLabels st) of
  Just bid -> StepOk bid st
  Nothing ->
    let n = csNextBlock st
        bid = BlockId n
    in StepOk bid (st { csNextBlock = n + 1, csLabels = symbolMapInsert name bid (csLabels st) })
