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
bindGlobal name ty = do
  rejectReservedSymbol "global" name
  resolved <- resolveSymbolName name
  CompileM $ \st -> Right ((), st { csGlobals = symbolMapInsert resolved ty (csGlobals st) })

rejectReservedSymbol :: String -> String -> CompileM ()
rejectReservedSymbol kind name =
  if "FUNCTION_" `prefixOf` name || "HCC_DATA_" `prefixOf` name
    then throwC (kind ++ " name " ++ show name ++ " uses a reserved HCC label prefix")
    else pure ()

bindConstant :: String -> Int -> CompileM ()
bindConstant name value = CompileM $ \st ->
  Right ((), st { csConstants = symbolMapInsert name value (csConstants st) })

bindFunction :: String -> CompileM ()
bindFunction name = do
  rejectReservedSymbol "function" name
  resolved <- resolveSymbolName name
  CompileM $ \st -> Right ((), st { csFunctions = symbolSetInsert resolved (csFunctions st) })

bindFunctionType :: String -> CType -> [Param] -> CompileM ()
bindFunctionType name retTy params = do
  rejectReservedSymbol "function" name
  resolved <- resolveSymbolName name
  CompileM $ \st -> Right ((), st
    { csFunctions = symbolSetInsert resolved (csFunctions st)
    , csFunctionTypes = symbolMapInsert resolved (CFunc retTy (paramTypes params)) (csFunctionTypes st)
    })

bindSymbolAlias :: String -> String -> CompileM ()
bindSymbolAlias public resolved = do
  rejectReservedSymbol "symbol alias" public
  rejectReservedSymbol "symbol alias" resolved
  CompileM $ \st -> Right ((), st { csSymbolAliases = symbolMapInsert public resolved (csSymbolAliases st) })

resolveSymbolName :: String -> CompileM String
resolveSymbolName name = CompileM $ \st ->
  case symbolMapLookup name (csSymbolAliases st) of
    Just resolved -> Right (resolved, st)
    Nothing -> Right (name, st)

lookupVarMaybe :: String -> CompileM (Maybe Temp)
lookupVarMaybe name = CompileM $ \st -> Right (fmap fst (scopeMapLookup name (csVars st)), st)

lookupVarType :: String -> CompileM (Maybe CType)
lookupVarType name = CompileM $ \st -> Right (fmap snd (scopeMapLookup name (csVars st)), st)

lookupGlobalType :: String -> CompileM (Maybe CType)
lookupGlobalType name = do
  resolved <- resolveSymbolName name
  CompileM $ \st -> Right (symbolMapLookup resolved (csGlobals st), st)

lookupConstant :: String -> CompileM (Maybe Int)
lookupConstant name = CompileM $ \st -> Right (symbolMapLookup name (csConstants st), st)

lookupFunction :: String -> CompileM Bool
lookupFunction name = do
  resolved <- resolveSymbolName name
  CompileM $ \st -> Right (symbolSetMember resolved (csFunctions st), st)

lookupFunctionType :: String -> CompileM (Maybe CType)
lookupFunctionType name = do
  resolved <- resolveSymbolName name
  CompileM $ \st -> Right (symbolMapLookup resolved (csFunctionTypes st), st)

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
currentReturnSlot = CompileM $ \st -> Right (csCurrentReturnSlot st, st)

withCurrentReturnSlot :: Maybe Temp -> CompileM a -> CompileM a
withCurrentReturnSlot slot action = CompileM $ \st ->
  case unCompileM action st { csCurrentReturnSlot = slot } of
    Left err -> Left err
    Right (x, st') -> Right (x, st' { csCurrentReturnSlot = csCurrentReturnSlot st })

withFunctionScope :: CompileM a -> CompileM a
withFunctionScope action = CompileM $ \st ->
  case unCompileM action st { csVars = scopeMapEmpty, csLabels = symbolMapEmpty, csBreakTargets = [], csContinueTargets = [], csSwitchCaseTargets = [], csCurrentReturnSlot = Nothing } of
    Left err -> Left err
    Right (x, st') -> Right (x, st'
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
    Left err -> Left err
    Right (x, st') -> Right (x, st'
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

withSwitchCaseTargets :: [(Maybe Expr, BlockId)] -> CompileM a -> CompileM a
withSwitchCaseTargets targets action = CompileM $ \st ->
  case unCompileM action st { csSwitchCaseTargets = targets : csSwitchCaseTargets st } of
    Left err -> Left err
    Right (x, st') -> Right (x, st' { csSwitchCaseTargets = csSwitchCaseTargets st })

currentBreakTarget :: CompileM (Maybe BlockId)
currentBreakTarget = CompileM $ \st -> Right (case csBreakTargets st of [] -> Nothing; x:_ -> Just x, st)

currentContinueTarget :: CompileM (Maybe BlockId)
currentContinueTarget = CompileM $ \st -> Right (case csContinueTargets st of [] -> Nothing; x:_ -> Just x, st)

nextSwitchCaseTarget :: Maybe Expr -> CompileM BlockId
nextSwitchCaseTarget label = CompileM $ \st -> case csSwitchCaseTargets st of
  [] -> Left (CompileError "case label outside switch")
  []:_ -> Left (CompileError "unexpected switch case label")
  targets:_ -> case lookupSwitchCaseTarget label targets of
    Just target -> Right (target, st)
    Nothing -> Left (CompileError "case label outside switch")

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
  Just bid -> Right (bid, st)
  Nothing ->
    let n = csNextBlock st
        bid = BlockId n
    in Right (bid, st { csNextBlock = n + 1, csLabels = symbolMapInsert name bid (csLabels st) })
