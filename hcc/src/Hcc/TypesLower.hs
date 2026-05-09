module TypesLower where

import Base
import TypesAst
import TypesIr

data LValue
  = LLocal Temp CType
  | LAddress Operand CType

data SwitchClause = SwitchClause (Maybe Expr) [Stmt]
