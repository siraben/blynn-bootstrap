module Ir where

import Base

data Temp = Temp Int
  deriving (Eq, Ord, Show)

data BlockId = BlockId Int
  deriving (Eq, Ord, Show)

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
  | IULt
  | IULe
  | IUGt
  | IUGe
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
  | ILoadS32 Temp Operand
  | ILoad16 Temp Operand
  | ILoadS16 Temp Operand
  | ILoad8 Temp Operand
  | ILoadS8 Temp Operand
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

renderModuleIr :: ModuleIr -> String
renderModuleIr (ModuleIr dataItems functions) =
  "ModuleIr "
  ++ renderList renderDataItem dataItems
  ++ " "
  ++ renderList renderFunctionIr functions

renderDataItem :: DataItem -> String
renderDataItem (DataItem name values) =
  "DataItem " ++ show name ++ " " ++ renderList renderDataValue values

renderDataValue :: DataValue -> String
renderDataValue value = case value of
  DByte n -> "DByte " ++ show n
  DAddress name -> "DAddress " ++ show name

renderFunctionIr :: FunctionIr -> String
renderFunctionIr (FunctionIr name locals blocks) =
  "FunctionIr "
  ++ show name
  ++ " "
  ++ show locals
  ++ " "
  ++ renderList renderBasicBlock blocks

renderBasicBlock :: BasicBlock -> String
renderBasicBlock (BasicBlock ident instrs term) =
  "BasicBlock "
  ++ renderBlockId ident
  ++ " "
  ++ renderList renderInstr instrs
  ++ " "
  ++ renderTerminator term

renderInstr :: Instr -> String
renderInstr instr = case instr of
  IParam temp n -> "IParam " ++ renderTemp temp ++ " " ++ show n
  IAlloca temp n -> "IAlloca " ++ renderTemp temp ++ " " ++ show n
  IConst temp n -> "IConst " ++ renderTemp temp ++ " " ++ show n
  ICopy temp operand -> "ICopy " ++ renderTemp temp ++ " " ++ renderOperand operand
  IAddrOf dst src -> "IAddrOf " ++ renderTemp dst ++ " " ++ renderTemp src
  ILoad64 temp operand -> "ILoad64 " ++ renderTemp temp ++ " " ++ renderOperand operand
  ILoad32 temp operand -> "ILoad32 " ++ renderTemp temp ++ " " ++ renderOperand operand
  ILoadS32 temp operand -> "ILoadS32 " ++ renderTemp temp ++ " " ++ renderOperand operand
  ILoad16 temp operand -> "ILoad16 " ++ renderTemp temp ++ " " ++ renderOperand operand
  ILoadS16 temp operand -> "ILoadS16 " ++ renderTemp temp ++ " " ++ renderOperand operand
  ILoad8 temp operand -> "ILoad8 " ++ renderTemp temp ++ " " ++ renderOperand operand
  ILoadS8 temp operand -> "ILoadS8 " ++ renderTemp temp ++ " " ++ renderOperand operand
  IStore64 dst src -> "IStore64 " ++ renderOperand dst ++ " " ++ renderOperand src
  IStore32 dst src -> "IStore32 " ++ renderOperand dst ++ " " ++ renderOperand src
  IStore16 dst src -> "IStore16 " ++ renderOperand dst ++ " " ++ renderOperand src
  IStore8 dst src -> "IStore8 " ++ renderOperand dst ++ " " ++ renderOperand src
  IBin temp op left right -> "IBin " ++ renderTemp temp ++ " " ++ renderBinOp op ++ " " ++ renderOperand left ++ " " ++ renderOperand right
  ICond temp initInstrs initValue condInstrs condValue resultInstrs resultValue ->
    "ICond "
    ++ renderTemp temp
    ++ " "
    ++ renderList renderInstr initInstrs
    ++ " "
    ++ renderOperand initValue
    ++ " "
    ++ renderList renderInstr condInstrs
    ++ " "
    ++ renderOperand condValue
    ++ " "
    ++ renderList renderInstr resultInstrs
    ++ " "
    ++ renderOperand resultValue
  ICall temp name args -> "ICall " ++ renderMaybe renderTemp temp ++ " " ++ show name ++ " " ++ renderList renderOperand args
  ICallIndirect temp target args -> "ICallIndirect " ++ renderMaybe renderTemp temp ++ " " ++ renderOperand target ++ " " ++ renderList renderOperand args

renderTerminator :: Terminator -> String
renderTerminator term = case term of
  TRet value -> "TRet " ++ renderMaybe renderOperand value
  TJump ident -> "TJump " ++ renderBlockId ident
  TBranch operand yes no -> "TBranch " ++ renderOperand operand ++ " " ++ renderBlockId yes ++ " " ++ renderBlockId no

renderOperand :: Operand -> String
renderOperand operand = case operand of
  OTemp temp -> "OTemp " ++ renderTemp temp
  OImm n -> "OImm " ++ show n
  OGlobal name -> "OGlobal " ++ show name
  OFunction name -> "OFunction " ++ show name

renderBinOp :: BinOp -> String
renderBinOp op = case op of
  IAdd -> "IAdd"
  ISub -> "ISub"
  IMul -> "IMul"
  IDiv -> "IDiv"
  IMod -> "IMod"
  IShl -> "IShl"
  IShr -> "IShr"
  ISar -> "ISar"
  IEq -> "IEq"
  INe -> "INe"
  ILt -> "ILt"
  ILe -> "ILe"
  IGt -> "IGt"
  IGe -> "IGe"
  IULt -> "IULt"
  IULe -> "IULe"
  IUGt -> "IUGt"
  IUGe -> "IUGe"
  IAnd -> "IAnd"
  IOr -> "IOr"
  IXor -> "IXor"

renderTemp :: Temp -> String
renderTemp (Temp n) = "Temp " ++ show n

renderBlockId :: BlockId -> String
renderBlockId (BlockId n) = "BlockId " ++ show n

renderMaybe :: (a -> String) -> Maybe a -> String
renderMaybe render value = case value of
  Nothing -> "Nothing"
  Just x -> "Just " ++ render x

renderList :: (a -> String) -> [a] -> String
renderList render values = "[" ++ renderListItems render values ++ "]"

renderListItems :: (a -> String) -> [a] -> String
renderListItems render values = case values of
  [] -> ""
  x:xs -> render x ++ renderListTail render xs

renderListTail :: (a -> String) -> [a] -> String
renderListTail render values = case values of
  [] -> ""
  x:xs -> "," ++ render x ++ renderListTail render xs
