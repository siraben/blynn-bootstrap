module LowerParams
  ( lowerParams
  , paramNames
  ) where

import Base
import TypesAst
import CompileM
import TypesIr

lowerParams :: Int -> [Param] -> CompileM ([String], [Instr])
lowerParams index params = case params of
  [] -> pure ([], [])
  Param ty name:rest -> do
    temp <- freshTemp
    bindVar name temp ty
    result <- lowerParams (index + 1) rest
    case result of
      (names, instrs) -> pure (name:names, IParam temp index:instrs)

paramNames :: [Param] -> [String]
paramNames params = case params of
  [] -> []
  Param _ name:rest -> name : paramNames rest
