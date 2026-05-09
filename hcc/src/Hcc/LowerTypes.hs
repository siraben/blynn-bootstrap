module LowerTypes where

import Base
import Ast
import Ir

data LValue
  = LLocal Temp CType
  | LAddress Operand CType

data SwitchClause = SwitchClause (Maybe Expr) [Stmt]
