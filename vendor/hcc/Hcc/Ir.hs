module Hcc.Ir where

newtype Temp = Temp Int
  deriving (Eq, Show)

newtype BlockId = BlockId Int
  deriving (Eq, Show)

data Operand
  = OTemp Temp
  | OImm Int
  | OGlobal String
  deriving (Eq, Show)

data BinOp
  = IAdd
  | ISub
  | IMul
  | IDiv
  | IMod
  | IShl
  | IShr
  | IEq
  | INe
  | ILt
  | ILe
  | IGt
  | IGe
  | IAnd
  | IOr
  deriving (Eq, Show)

data Instr
  = IParam Temp Int
  | IConst Temp Int
  | ICopy Temp Operand
  | ILoad8 Temp Operand
  | IBin Temp BinOp Operand Operand
  | ICall (Maybe Temp) String [Operand]
  deriving (Eq, Show)

data Terminator
  = TRet (Maybe Operand)
  | TJump BlockId
  | TBranch Operand BlockId BlockId
  deriving (Eq, Show)

data BasicBlock = BasicBlock BlockId [Instr] Terminator
  deriving (Eq, Show)

data DataItem = DataItem String [Int]
  deriving (Eq, Show)

data FunctionIr = FunctionIr String [String] [BasicBlock]
  deriving (Eq, Show)

data ModuleIr = ModuleIr [DataItem] [FunctionIr]
  deriving (Eq, Show)
