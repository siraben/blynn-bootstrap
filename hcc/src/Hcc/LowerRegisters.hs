module LowerRegisters
  ( registerTypeAggregates
  , registerExternGlobals
  , registerFieldAggregates
  ) where

import Base
import TypesAst
import CompileM

registerExternGlobals :: [(CType, String)] -> CompileM ()
registerExternGlobals = mapM_ $ \(ty, name) -> do
    registerTypeAggregates ty
    bindGlobal name ty

registerFieldAggregates :: [Field] -> CompileM ()
registerFieldAggregates = mapM_ $ \(Field ty _) -> registerTypeAggregates ty

registerTypeAggregates :: CType -> CompileM ()
registerTypeAggregates ty = case ty of
  CPtr inner -> registerTypeAggregates inner
  CArray inner _ -> registerTypeAggregates inner
  CFunc ret params -> do
    registerTypeAggregates ret
    mapM_ registerTypeAggregates params
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
