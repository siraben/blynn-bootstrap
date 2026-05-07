module LowerTypes where

import Ast
import Ir

data LValue
  = LLocal Temp CType
  | LAddress Operand CType
  deriving (Eq, Show)

data SwitchClause = SwitchClause (Maybe Expr) [Stmt]
  deriving (Eq, Show)
