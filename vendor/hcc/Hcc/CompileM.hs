module CompileM where

import Base
import Ast
import Ir
import SymbolTable

data CompileError = CompileError String

data CompileState = CompileState
  { csNextTemp :: Int
  , csNextBlock :: Int
  , csNextLabel :: Int
  , csDataPrefix :: String
  , csVars :: SymbolMap (Temp, CType)
  , csStructs :: SymbolMap (Bool, [Field])
  , csGlobals :: SymbolMap CType
  , csConstants :: SymbolMap Int
  , csFunctions :: SymbolSet
  , csLabels :: SymbolMap BlockId
  , csDataItems :: [DataItem]
  , csBreakTargets :: [BlockId]
  , csContinueTargets :: [BlockId]
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
  , csVars = symbolMapEmpty
  , csStructs = symbolMapEmpty
  , csGlobals = symbolMapEmpty
  , csConstants = symbolMapEmpty
  , csFunctions = symbolSetEmpty
  , csLabels = symbolMapEmpty
  , csDataItems = []
  , csBreakTargets = []
  , csContinueTargets = []
  }

runCompileM :: CompileM a -> Either CompileError a
runCompileM = runCompileMWithDataPrefix "HCC_DATA"

runCompileMWithDataPrefix :: String -> CompileM a -> Either CompileError a
runCompileMWithDataPrefix prefix action = case unCompileM action initialCompileState { csDataPrefix = prefix } of
  Left err -> Left err
  Right (x, _) -> Right x

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

getDataItems :: CompileM [DataItem]
getDataItems = CompileM $ \st -> Right (reverse (csDataItems st), st)

bindVar :: String -> Temp -> CType -> CompileM ()
bindVar name temp ty = CompileM $ \st ->
  Right ((), st { csVars = symbolMapInsert name (temp, ty) (csVars st) })

bindStruct :: String -> Bool -> [Field] -> CompileM ()
bindStruct name isUnion fields = CompileM $ \st ->
  Right ((), st { csStructs = symbolMapInsert name (isUnion, fields) (csStructs st) })

bindGlobal :: String -> CType -> CompileM ()
bindGlobal name ty = CompileM $ \st ->
  Right ((), st { csGlobals = symbolMapInsert name ty (csGlobals st) })

bindConstant :: String -> Int -> CompileM ()
bindConstant name value = CompileM $ \st ->
  Right ((), st { csConstants = symbolMapInsert name value (csConstants st) })

bindFunction :: String -> CompileM ()
bindFunction name = CompileM $ \st ->
  Right ((), st { csFunctions = symbolSetInsert name (csFunctions st) })

lookupVar :: String -> CompileM Temp
lookupVar name = CompileM $ \st -> case symbolMapLookup name (csVars st) of
  Just (temp, _) -> Right (temp, st)
  Nothing -> Left (CompileError ("unbound variable: " ++ name))

lookupVarMaybe :: String -> CompileM (Maybe Temp)
lookupVarMaybe name = CompileM $ \st -> Right (fmap fst (symbolMapLookup name (csVars st)), st)

lookupVarType :: String -> CompileM (Maybe CType)
lookupVarType name = CompileM $ \st -> Right (fmap snd (symbolMapLookup name (csVars st)), st)

lookupGlobalType :: String -> CompileM (Maybe CType)
lookupGlobalType name = CompileM $ \st -> Right (symbolMapLookup name (csGlobals st), st)

lookupConstant :: String -> CompileM (Maybe Int)
lookupConstant name = CompileM $ \st -> Right (symbolMapLookup name (csConstants st), st)

lookupFunction :: String -> CompileM Bool
lookupFunction name = CompileM $ \st -> Right (symbolSetMember name (csFunctions st), st)

lookupStruct :: String -> CompileM (Maybe (Bool, [Field]))
lookupStruct name = CompileM $ \st -> Right (symbolMapLookup name (csStructs st), st)

withFunctionScope :: CompileM a -> CompileM a
withFunctionScope action = CompileM $ \st ->
  case unCompileM action st { csVars = symbolMapEmpty, csLabels = symbolMapEmpty, csBreakTargets = [], csContinueTargets = [] } of
    Left err -> Left err
    Right (x, st') -> Right (x, st'
      { csVars = csVars st
      , csLabels = csLabels st
      , csBreakTargets = csBreakTargets st
      , csContinueTargets = csContinueTargets st
      })

withVarScope :: CompileM a -> CompileM a
withVarScope action = CompileM $ \st ->
  case unCompileM action st of
    Left err -> Left err
    Right (x, st') -> Right (x, st' { csVars = csVars st })

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
