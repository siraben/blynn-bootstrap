module TypesIr
  ( Temp(..)
  , BlockId(..)
  , Operand(..)
  , BinOp(..)
  , Instr(..)
  , Terminator(..)
  , BasicBlock(..)
  , DataValue(..)
  , DataItem(..)
  , FunctionIr(..)
  , TopItemIr(..)
  , ModuleIr(..)
  ) where

import Base

data Temp = Temp Int

data BlockId = BlockId Int

data Operand
  = OTemp Temp
  | OImm Int
  | OImmBytes [Int]
  | OGlobal String
  | OFunction String

data BinOp
  = IAdd
  | ISub
  | IMul
  | IDiv
  | IMod
  | IShl
  | IShr
  | ISar
  | IEq
  | INe
  | ILt
  | ILe
  | IGt
  | IGe
  | IULt
  | IULe
  | IUGt
  | IUGe
  | IAnd
  | IOr
  | IXor

data Instr
  = IParam Temp Int
  | IAlloca Temp Int
  | IConst Temp Int
  | IConstBytes Temp [Int]
  | ICopy Temp Operand
  | IAddrOf Temp Temp
  | ILoad64 Temp Operand
  | ILoad32 Temp Operand
  | ILoadS32 Temp Operand
  | ILoad16 Temp Operand
  | ILoadS16 Temp Operand
  | ILoad8 Temp Operand
  | ILoadS8 Temp Operand
  | IStore64 Operand Operand
  | IStore32 Operand Operand
  | IStore16 Operand Operand
  | IStore8 Operand Operand
  | ISExt Temp Int Operand
  | IZExt Temp Int Operand
  | ITrunc Temp Int Operand
  | IBin Temp BinOp Operand Operand
  | ICond Temp [Instr] Operand [Instr] Operand [Instr] Operand
  | ICall (Maybe Temp) String [Operand]
  | ICallIndirect (Maybe Temp) Operand [Operand]

data Terminator
  = TRet (Maybe Operand)
  | TJump BlockId
  | TBranch Operand BlockId BlockId
  | TBranchCmp BinOp Operand Operand BlockId BlockId

data BasicBlock = BasicBlock BlockId [Instr] Terminator

data DataValue
  = DByte Int
  | DAddress String

data DataItem = DataItem String [DataValue]

data FunctionIr = FunctionIr String [BasicBlock]

data TopItemIr
  = TopData DataItem
  | TopFunction FunctionIr

data ModuleIr = ModuleIr [TopItemIr]
