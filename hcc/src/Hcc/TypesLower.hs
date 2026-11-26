module TypesLower
  ( LValue(..)
  ) where

import TypesAst
import TypesIr

data LValue
  = LLocal Temp CType
  | LAddress Operand CType
