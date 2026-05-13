module CompileM
  ( CompileError(..)
  , CompileState(..)
  , CompileM(..)
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
  , withFunctionScope
  , withVarScope
  , withLoopTargets
  , withBreakTarget
  , currentBreakTarget
  , currentContinueTarget
  , labelBlock
  ) where

import Base
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

data CompileM a = CompileM
  { unCompileM :: CompileState -> Either CompileError (a, CompileState)
  }

instance Functor CompileM where
  fmap f action = CompileM $ \st -> case unCompileM action st of
    Left err -> Left err
    Right (x, st') -> Right (f x, st')

instance Applicative CompileM where
  pure x = CompileM $ \st -> Right (x, st)
  ff <*> fx = CompileM $ \st -> case unCompileM ff st of
    Left err -> Left err
    Right (f, st') -> case unCompileM fx st' of
      Left err -> Left err
      Right (x, st'') -> Right (f x, st'')

instance Monad CompileM where
  return = pure
  action >>= next = CompileM $ \st -> case unCompileM action st of
    Left err -> Left err
    Right (x, st') -> unCompileM (next x) st'

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
throwC msg = CompileM $ \_ -> Left (CompileError msg)

withErrorContext :: String -> CompileM a -> CompileM a
withErrorContext context action = CompileM $ \st ->
  case unCompileM action st of
    Left (CompileError msg) -> Left (CompileError (context ++ ": " ++ msg))
    Right result -> Right result

freshTemp :: CompileM Temp
freshTemp = CompileM $ \st ->
  let n = csNextTemp st
  in Right (Temp n, st { csNextTemp = n + 1 })

freshBlock :: CompileM BlockId
freshBlock = CompileM $ \st ->
  let n = csNextBlock st
  in Right (BlockId n, st { csNextBlock = n + 1 })

freshLabel :: CompileM String
freshLabel = CompileM $ \st ->
  let n = csNextLabel st
    in Right ("L" ++ show n, st { csNextLabel = n + 1 })

freshDataLabel :: CompileM String
freshDataLabel = do
  label <- freshLabel
  CompileM $ \st -> Right (csDataPrefix st ++ "_" ++ label, st)

addDataItem :: DataItem -> CompileM ()
addDataItem item@(DataItem label _) = CompileM $ \st ->
  Right ((), st { csDataItems = item : removeLabel label (csDataItems st) })
  where
    removeLabel key items = case items of
      [] -> []
      DataItem label' _:rest | label' == key -> removeLabel key rest
      x:rest -> x : removeLabel key rest

bindVar :: String -> Temp -> CType -> CompileM ()
bindVar name temp ty = CompileM $ \st ->
  Right ((), st { csVars = scopeMapInsert name (temp, ty) (csVars st) })

bindStruct :: String -> Bool -> [Field] -> CompileM ()
bindStruct name isUnion fields = CompileM $ \st ->
  Right ((), st
    { csStructs = symbolMapInsert name (isUnion, fields) (csStructs st)
    , csStructSizes = symbolMapDelete name (csStructSizes st)
    , csStructMembers = symbolMapDelete name (csStructMembers st)
    })

bindGlobal :: String -> CType -> CompileM ()
bindGlobal name ty = CompileM $ \st ->
  Right ((), st { csGlobals = symbolMapInsert name ty (csGlobals st) })

bindConstant :: String -> Int -> CompileM ()
bindConstant name value = CompileM $ \st ->
  Right ((), st { csConstants = symbolMapInsert name value (csConstants st) })

bindFunction :: String -> CompileM ()
bindFunction name = CompileM $ \st ->
  Right ((), st { csFunctions = symbolSetInsert name (csFunctions st) })

bindFunctionType :: String -> CType -> [Param] -> CompileM ()
bindFunctionType name retTy params = CompileM $ \st ->
  Right ((), st
    { csFunctions = symbolSetInsert name (csFunctions st)
    , csFunctionTypes = symbolMapInsert name (CFunc retTy (paramTypes params)) (csFunctionTypes st)
    })
  where
    paramTypes xs = case xs of
      [] -> []
      Param ty _:rest -> ty : paramTypes rest

lookupVarMaybe :: String -> CompileM (Maybe Temp)
lookupVarMaybe name = CompileM $ \st -> Right (fmap fst (scopeMapLookup name (csVars st)), st)

lookupVarType :: String -> CompileM (Maybe CType)
lookupVarType name = CompileM $ \st -> Right (fmap snd (scopeMapLookup name (csVars st)), st)

lookupGlobalType :: String -> CompileM (Maybe CType)
lookupGlobalType name = CompileM $ \st -> Right (symbolMapLookup name (csGlobals st), st)

lookupConstant :: String -> CompileM (Maybe Int)
lookupConstant name = CompileM $ \st -> Right (symbolMapLookup name (csConstants st), st)

lookupFunction :: String -> CompileM Bool
lookupFunction name = CompileM $ \st -> Right (symbolSetMember name (csFunctions st), st)

lookupFunctionType :: String -> CompileM (Maybe CType)
lookupFunctionType name = CompileM $ \st -> Right (symbolMapLookup name (csFunctionTypes st), st)

lookupStruct :: String -> CompileM (Maybe (Bool, [Field]))
lookupStruct name = CompileM $ \st -> Right (symbolMapLookup name (csStructs st), st)

lookupStructSizeCache :: String -> CompileM (Maybe Int)
lookupStructSizeCache name = CompileM $ \st -> Right (symbolMapLookup name (csStructSizes st), st)

cacheStructSize :: String -> Int -> CompileM ()
cacheStructSize name size = CompileM $ \st ->
  Right ((), st { csStructSizes = symbolMapInsert name size (csStructSizes st) })

lookupStructMemberCache :: String -> String -> CompileM (Maybe (CType, Int))
lookupStructMemberCache structName fieldName = CompileM $ \st ->
  case symbolMapLookup structName (csStructMembers st) of
    Nothing -> Right (Nothing, st)
    Just members -> Right (symbolMapLookup fieldName members, st)

cacheStructMember :: String -> String -> (CType, Int) -> CompileM ()
cacheStructMember structName fieldName info = CompileM $ \st ->
  let members = case symbolMapLookup structName (csStructMembers st) of
        Just existing -> existing
        Nothing -> symbolMapEmpty
      members' = symbolMapInsert fieldName info members
  in Right ((), st { csStructMembers = symbolMapInsert structName members' (csStructMembers st) })

targetBits :: CompileM Int
targetBits = CompileM $ \st -> Right (csTargetBits st, st)

targetWordSize :: CompileM Int
targetWordSize = do
  bits <- targetBits
  pure (if bits == 32 then 4 else 8)

currentFunctionName :: CompileM (Maybe String)
currentFunctionName = CompileM $ \st -> Right (csCurrentFunction st, st)

withCurrentFunction :: String -> CompileM a -> CompileM a
withCurrentFunction name action = CompileM $ \st ->
  case unCompileM action st { csCurrentFunction = Just name } of
    Left err -> Left err
    Right (x, st') -> Right (x, st' { csCurrentFunction = csCurrentFunction st })

withFunctionScope :: CompileM a -> CompileM a
withFunctionScope action = CompileM $ \st ->
  case unCompileM action st { csVars = scopeMapEmpty, csLabels = symbolMapEmpty, csBreakTargets = [], csContinueTargets = [] } of
    Left err -> Left err
    Right (x, st') -> Right (x, st'
      { csVars = csVars st
      , csLabels = csLabels st
      , csBreakTargets = csBreakTargets st
      , csContinueTargets = csContinueTargets st
      })

withVarScope :: CompileM a -> CompileM a
withVarScope action = CompileM $ \st ->
  case unCompileM action st { csVars = scopeMapEnter (csVars st) } of
    Left err -> Left err
    Right (x, st') -> Right (x, st' { csVars = scopeMapLeave (csVars st') })

withLoopTargets :: BlockId -> BlockId -> CompileM a -> CompileM a
withLoopTargets breakTarget continueTarget action = CompileM $ \st ->
  case unCompileM action st
    { csBreakTargets = breakTarget : csBreakTargets st
    , csContinueTargets = continueTarget : csContinueTargets st
    } of
    Left err -> Left err
    Right (x, st') -> Right (x, st'
      { csBreakTargets = csBreakTargets st
      , csContinueTargets = csContinueTargets st
      })

withBreakTarget :: BlockId -> CompileM a -> CompileM a
withBreakTarget breakTarget action = CompileM $ \st ->
  case unCompileM action st { csBreakTargets = breakTarget : csBreakTargets st } of
    Left err -> Left err
    Right (x, st') -> Right (x, st' { csBreakTargets = csBreakTargets st })

currentBreakTarget :: CompileM (Maybe BlockId)
currentBreakTarget = CompileM $ \st -> Right (case csBreakTargets st of [] -> Nothing; x:_ -> Just x, st)

currentContinueTarget :: CompileM (Maybe BlockId)
currentContinueTarget = CompileM $ \st -> Right (case csContinueTargets st of [] -> Nothing; x:_ -> Just x, st)

labelBlock :: String -> CompileM BlockId
labelBlock name = CompileM $ \st -> case symbolMapLookup name (csLabels st) of
  Just bid -> Right (bid, st)
  Nothing ->
    let n = csNextBlock st
        bid = BlockId n
    in Right (bid, st { csNextBlock = n + 1, csLabels = symbolMapInsert name bid (csLabels st) })
