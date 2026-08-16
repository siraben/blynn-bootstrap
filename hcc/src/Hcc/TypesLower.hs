module TypesLower
  ( LValue(..)
  ) where

import Base
import TypesAst
import TypesIr

data LValue
  = LLocal Temp CType
  | LAddress Operand CType
  | LBitField Operand CType Int Int
