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
  , withFunctionScope
  , withVarScope
  , withLoopTargets
  , withBreakTarget
  , currentBreakTarget
  , currentContinueTarget
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
  , csLabels :: SymbolMap BlockId
  , csDataItems :: [DataItem]
  , csBreakTargets :: [BlockId]
  , csContinueTargets :: [BlockId]
  , csTargetBits :: Int
  , csCurrentFunction :: Maybe String
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
  , csLabels = symbolMapEmpty
  , csDataItems = []
  , csBreakTargets = []
  , csContinueTargets = []
  , csTargetBits = 64
  , csCurrentFunction = Nothing
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
addDataItem item@(DataItem label _) =
  modifyC $ \st -> st { csDataItems = item : filter (\(DataItem label' _) -> label' /= label) (csDataItems st) }

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
  modifyC $ \st -> st { csGlobals = symbolMapInsert name ty (csGlobals st) }

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
  modifyC $ \st -> st { csFunctions = symbolSetInsert name (csFunctions st) }

bindFunctionType :: String -> CType -> [Param] -> CompileM ()
bindFunctionType name retTy params = do
  rejectReservedSymbol "function" name
  modifyC $ \st -> st
    { csFunctions = symbolSetInsert name (csFunctions st)
    , csFunctionTypes = symbolMapInsert name (CFunc retTy (paramTypes params)) (csFunctionTypes st)
    }

lookupVarMaybe :: String -> CompileM (Maybe Temp)
lookupVarMaybe name = getC (fmap fst . scopeMapLookup name . csVars)

lookupVarType :: String -> CompileM (Maybe CType)
lookupVarType name = getC (fmap snd . scopeMapLookup name . csVars)

lookupGlobalType :: String -> CompileM (Maybe CType)
lookupGlobalType name = getC (symbolMapLookup name . csGlobals)

lookupConstant :: String -> CompileM (Maybe Int)
lookupConstant name = getC (symbolMapLookup name . csConstants)

lookupFunction :: String -> CompileM Bool
lookupFunction name = getC (symbolSetMember name . csFunctions)

lookupFunctionType :: String -> CompileM (Maybe CType)
lookupFunctionType name = getC (symbolMapLookup name . csFunctionTypes)

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

withFunctionScope :: CompileM a -> CompileM a
withFunctionScope action = CompileM $ \st ->
  case unCompileM action st { csVars = scopeMapEmpty, csLabels = symbolMapEmpty, csBreakTargets = [], csContinueTargets = [] } of
    StepErr err -> StepErr err
    StepOk x st' -> StepOk x (st'
      { csVars = csVars st
      , csLabels = csLabels st
      , csBreakTargets = csBreakTargets st
      , csContinueTargets = csContinueTargets st
      })

withVarScope :: CompileM a -> CompileM a
withVarScope action = CompileM $ \st ->
  case unCompileM action st { csVars = scopeMapEnter (csVars st) } of
    StepErr err -> StepErr err
    StepOk x st' -> StepOk x (st' { csVars = scopeMapLeave (csVars st') })

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

currentBreakTarget :: CompileM (Maybe BlockId)
currentBreakTarget = getC (listHead . csBreakTargets)

currentContinueTarget :: CompileM (Maybe BlockId)
currentContinueTarget = getC (listHead . csContinueTargets)

listHead :: [a] -> Maybe a
listHead [] = Nothing
listHead (x:_) = Just x

labelBlock :: String -> CompileM BlockId
labelBlock name = CompileM $ \st -> case symbolMapLookup name (csLabels st) of
  Just bid -> StepOk bid st
  Nothing ->
    let n = csNextBlock st
        bid = BlockId n
    in StepOk bid (st { csNextBlock = n + 1, csLabels = symbolMapInsert name bid (csLabels st) })
