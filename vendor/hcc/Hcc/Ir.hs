module Hcc.Ir where

newtype Temp = Temp Int
  deriving (Eq, Show)

newtype BlockId = BlockId Int
  deriving (Eq, Show)

data Operand
  = OTemp Temp
  | OImm Int
  | OGlobal String
  | OFunction String
  deriving (Eq, Show)

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
  | IAnd
  | IOr
  | IXor
  deriving (Eq, Show)

data Instr
  = IParam Temp Int
  | IAlloca Temp Int
  | IConst Temp Int
  | ICopy Temp Operand
  | IAddrOf Temp Temp
  | ILoad64 Temp Operand
  | ILoad32 Temp Operand
  | ILoad16 Temp Operand
  | ILoad8 Temp Operand
  | IStore64 Operand Operand
  | IStore32 Operand Operand
  | IStore16 Operand Operand
  | IStore8 Operand Operand
  | IBin Temp BinOp Operand Operand
  | ICond Temp [Instr] Operand [Instr] Operand [Instr] Operand
  | ICall (Maybe Temp) String [Operand]
  | ICallIndirect (Maybe Temp) Operand [Operand]
  deriving (Eq, Show)

data Terminator
  = TRet (Maybe Operand)
  | TJump BlockId
  | TBranch Operand BlockId BlockId
  deriving (Eq, Show)

data BasicBlock = BasicBlock BlockId [Instr] Terminator
  deriving (Eq, Show)

data DataValue
  = DByte Int
  | DAddress String
  deriving (Eq, Show)

data DataItem = DataItem String [DataValue]
  deriving (Eq, Show)

data FunctionIr = FunctionIr String [String] [BasicBlock]
  deriving (Eq, Show)

data ModuleIr = ModuleIr [DataItem] [FunctionIr]
  deriving (Eq, Show)
