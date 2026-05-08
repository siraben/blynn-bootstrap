module LowerTypes where

import Base
import Ast
import Ir

data LValue
  = LLocal Temp CType
  | LAddress Operand CType
  deriving (Eq)

data SwitchClause = SwitchClause (Maybe Expr) [Stmt]
  deriving (Eq)
