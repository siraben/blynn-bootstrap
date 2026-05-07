module Hcc.CompileM
  ( CompileError(..)
  , CompileM
  , CompileState(..)
  , bindVar
  , freshBlock
  , freshLabel
  , freshTemp
  , labelBlock
  , initialCompileState
  , addDataItem
  , getDataItems
  , lookupVar
  , runCompileM
  , throwC
  , withFunctionScope
  , withVarScope
  ) where

import Hcc.Ir

data CompileError = CompileError String
  deriving (Eq, Show)

data CompileState = CompileState
  { csNextTemp :: Int
  , csNextBlock :: Int
  , csNextLabel :: Int
  , csVars :: [(String, Temp)]
  , csLabels :: [(String, BlockId)]
  , csDataItems :: [DataItem]
  } deriving (Eq, Show)

newtype CompileM a = CompileM
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
  , csVars = []
  , csLabels = []
  , csDataItems = []
  }

runCompileM :: CompileM a -> Either CompileError a
runCompileM action = case unCompileM action initialCompileState of
  Left err -> Left err
  Right (x, _) -> Right x

throwC :: String -> CompileM a
throwC msg = CompileM $ \_ -> Left (CompileError msg)

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

addDataItem :: DataItem -> CompileM ()
addDataItem item = CompileM $ \st ->
  Right ((), st { csDataItems = item : csDataItems st })

getDataItems :: CompileM [DataItem]
getDataItems = CompileM $ \st -> Right (reverse (csDataItems st), st)

bindVar :: String -> Temp -> CompileM ()
bindVar name temp = CompileM $ \st ->
  Right ((), st { csVars = (name, temp) : remove name (csVars st) })
  where
    remove key vars = case vars of
      [] -> []
      (k, v):rest | k == key -> remove key rest
                  | otherwise -> (k, v) : remove key rest

lookupVar :: String -> CompileM Temp
lookupVar name = CompileM $ \st -> case lookup name (csVars st) of
  Just temp -> Right (temp, st)
  Nothing -> Left (CompileError ("unbound variable: " ++ name))

withFunctionScope :: CompileM a -> CompileM a
withFunctionScope action = CompileM $ \st ->
  case unCompileM action st { csVars = [], csLabels = [] } of
    Left err -> Left err
    Right (x, st') -> Right (x, st' { csVars = csVars st, csLabels = csLabels st })

withVarScope :: CompileM a -> CompileM a
withVarScope action = CompileM $ \st ->
  case unCompileM action st of
    Left err -> Left err
    Right (x, st') -> Right (x, st' { csVars = csVars st })

labelBlock :: String -> CompileM BlockId
labelBlock name = CompileM $ \st -> case lookup name (csLabels st) of
  Just bid -> Right (bid, st)
  Nothing ->
    let n = csNextBlock st
        bid = BlockId n
    in Right (bid, st { csNextBlock = n + 1, csLabels = (name, bid) : csLabels st })
