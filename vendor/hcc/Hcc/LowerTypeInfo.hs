module LowerTypeInfo where

import Ast
import CompileM
import LowerCommon

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

isAggregateType :: CType -> Bool
isAggregateType ty = case ty of
  CArray _ _ -> True
  CStruct _ -> True
  CUnion _ -> True
  CStructNamed _ _ -> True
  CUnionNamed _ _ -> True
  CStructDef _ -> True
  CUnionDef _ -> True
  CNamed _ -> True
  _ -> False

isPointerType :: CType -> Bool
isPointerType ty = case ty of
  CPtr _ -> True
  CNamed name -> stringMember name ("intptr_t" : "uintptr_t" : [])
  _ -> False
