module LowerParams
  ( lowerParams
  ) where

import Base
import TypesAst
import CompileM
import TypesIr

lowerParams :: Int -> [Param] -> CompileM [Instr]
lowerParams index params = case params of
  [] -> pure []
  Param ty name:rest -> do
    temp <- freshTemp
    bindVar name temp ty
    instrs <- lowerParams (index + 1) rest
    pure (IParam temp index:instrs)
