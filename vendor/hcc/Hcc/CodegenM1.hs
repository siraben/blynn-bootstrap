module Hcc.CodegenM1
  ( CodegenError(..)
  , codegenM1
  ) where

import Hcc.Ast
import Hcc.CompileM
import Hcc.Ir
import Hcc.Lower
import Hcc.RegAlloc

data CodegenError = CodegenError String
  deriving (Eq, Show)

codegenM1 :: Program -> Either CodegenError String
codegenM1 ast = do
  ir <- mapCompileError (lowerProgram ast)
  codegenModule ir

codegenModule :: ModuleIr -> Either CodegenError String
codegenModule (ModuleIr functions) = do
  bodies <- mapM codegenFunction functions
  pure (unlines (header ++ concat bodies))

header :: [String]
header =
  [ "## hcc M1 output"
  , "## target: stage0-posix amd64 M1"
  , ""
  , "DEFINE HCC_ADD_IMMEDIATE_to_rsp 4881C4"
  , "DEFINE HCC_SUB_IMMEDIATE_from_rsp 4881EC"
  , "DEFINE HCC_STORE_RSP_IMMEDIATE_from_rax 48898424"
  , "DEFINE HCC_COPY_rax_to_rsi 4889C6"
  , "DEFINE HCC_COPY_rax_to_rdx 4889C2"
  , "DEFINE HCC_COPY_rsi_to_rax 4889F0"
  , "DEFINE HCC_COPY_rdx_to_rax 4889D0"
  , "DEFINE HCC_PUSH_RSI 56"
  , "DEFINE HCC_PUSH_RDX 52"
  , ""
  ]

codegenFunction :: FunctionIr -> Either CodegenError [String]
codegenFunction fn@(FunctionIr name _ blocks) = do
  alloc <- mapAllocError (allocateFunction fn)
  body <- codegenBlocks alloc (stackSlotCount alloc) blocks
  pure ((":FUNCTION_" ++ name) : prologue (stackSlotCount alloc) ++ body ++ [""])

prologue :: Int -> [String]
prologue slots =
  if slots == 0 then [] else ["\tHCC_SUB_IMMEDIATE_from_rsp %" ++ show (slots * 8)]

codegenBlocks :: Allocation -> Int -> [BasicBlock] -> Either CodegenError [String]
codegenBlocks alloc totalSlots blocks = case blocks of
  [] -> pure []
  BasicBlock bid instrs term:rest -> do
    body <- codegenInstrs alloc instrs
    termCode <- codegenTerminator alloc totalSlots term
    tailCode <- codegenBlocks alloc totalSlots rest
    pure (blockLabel bid ++ body ++ termCode ++ tailCode)

blockLabel :: BlockId -> [String]
blockLabel (BlockId 0) = []
blockLabel (BlockId n) = [":HCC_BLOCK_" ++ show n]

codegenInstrs :: Allocation -> [Instr] -> Either CodegenError [String]
codegenInstrs alloc instrs = case instrs of
  [] -> pure []
  instr:rest -> do
    code <- codegenInstr alloc instr
    tailCode <- codegenInstrs alloc rest
    pure (code ++ tailCode)

codegenInstr :: Allocation -> Instr -> Either CodegenError [String]
codegenInstr alloc instr = case instr of
  IParam{} -> pure []
  IConst temp value ->
    storeTemp alloc temp ["\tLOAD_IMMEDIATE_rax %" ++ show value]
  IBin temp op a b -> do
    acode <- loadOperand alloc a
    bcode <- loadOperand alloc b
    opCode <- binOpCode op
    storeTemp alloc temp (acode ++ ["\tPUSH_RAX", "\tPOP_RBX"] ++ bcode ++ opCode)
  ICall result name args -> do
    argCode <- loadArguments alloc 0 args
    let callCode = argCode ++ ["\tCALL_IMMEDIATE %FUNCTION_" ++ name]
    case result of
      Nothing -> pure callCode
      Just temp -> storeTemp alloc temp callCode

codegenTerminator :: Allocation -> Int -> Terminator -> Either CodegenError [String]
codegenTerminator alloc totalSlots term = case term of
  TRet Nothing -> pure (["\tLOAD_IMMEDIATE_rax %0"] ++ cleanupStack totalSlots ++ ["\tRETURN"])
  TRet (Just op) -> do
    code <- loadOperand alloc op
    pure (code ++ cleanupStack totalSlots ++ ["\tRETURN"])
  TJump bid -> pure ["\tJUMP %" ++ blockRef bid]
  TBranch op yes no -> do
    code <- loadOperand alloc op
    pure (code ++ ["\tTEST", "\tJUMP_NE %" ++ blockRef yes, "\tJUMP %" ++ blockRef no])

loadArguments :: Allocation -> Int -> [Operand] -> Either CodegenError [String]
loadArguments alloc index args = case args of
  [] -> pure []
  op:rest -> do
    one <- loadOperand alloc op
    move <- argumentMove index
    tailCode <- loadArguments alloc (index + 1) rest
    pure (one ++ move ++ tailCode)

argumentMove :: Int -> Either CodegenError [String]
argumentMove index = case index of
  0 -> Right ["\tCOPY_rax_to_rdi"]
  1 -> Right ["\tHCC_COPY_rax_to_rsi"]
  2 -> Right ["\tHCC_COPY_rax_to_rdx"]
  _ -> Left (CodegenError ("unsupported call argument index: " ++ show index))

binOpCode :: BinOp -> Either CodegenError [String]
binOpCode op = case op of
  IAdd -> Right ["\tADD_rbx_to_rax"]
  ISub -> Right ["\tSUBTRACT_rax_from_rbx_into_rbx", "\tMOVE_rbx_to_rax"]
  IMul -> Right ["\tMULTIPLY_rax_by_rbx_into_rax"]
  IEq -> Right ["\tCMP", "\tSETE", "\tMOVEZX"]
  INe -> Right ["\tCMP", "\tSETNE", "\tMOVEZX"]
  ILt -> Right ["\tCMP", "\tSETL", "\tMOVEZX"]
  ILe -> Right ["\tCMP", "\tSETLE", "\tMOVEZX"]
  IGt -> Right ["\tCMP", "\tSETG", "\tMOVEZX"]
  IGe -> Right ["\tCMP", "\tSETGE", "\tMOVEZX"]
  IAnd -> Right ["\tAND_rax_rbx"]
  IOr -> Right ["\tOR_rax_rbx"]

loadOperand :: Allocation -> Operand -> Either CodegenError [String]
loadOperand alloc op = case op of
  OImm value -> Right ["\tLOAD_IMMEDIATE_rax %" ++ show value]
  OGlobal name -> Left (CodegenError ("cannot load global yet: " ++ name))
  OTemp temp -> do
    loc <- mapAllocError (lookupLocation temp alloc)
    loadLocation loc

loadLocation :: Location -> Either CodegenError [String]
loadLocation loc = case loc of
  InReg Rax -> Right []
  InReg Rbx -> Right ["\tMOVE_rbx_to_rax"]
  InReg Rdi -> Right ["\tPUSH_RDI", "\tPOP_RAX"]
  InReg Rsi -> Right ["\tHCC_COPY_rsi_to_rax"]
  InReg Rdx -> Right ["\tHCC_COPY_rdx_to_rax"]
  OnStack slot -> Right ["\tLOAD_RSP_IMMEDIATE_into_rax %" ++ show (8 * slot)]

storeTemp :: Allocation -> Temp -> [String] -> Either CodegenError [String]
storeTemp alloc temp code = do
  loc <- mapAllocError (lookupLocation temp alloc)
  case loc of
    OnStack slot -> Right (code ++ ["\tHCC_STORE_RSP_IMMEDIATE_from_rax %" ++ show (8 * slot)])
    InReg _ -> Right code

cleanupStack :: Int -> [String]
cleanupStack slots =
  if slots == 0 then [] else ["\tHCC_ADD_IMMEDIATE_to_rsp %" ++ show (slots * 8)]

blockRef :: BlockId -> String
blockRef (BlockId n) = "HCC_BLOCK_" ++ show n

mapCompileError :: Either CompileError a -> Either CodegenError a
mapCompileError result = case result of
  Left (CompileError msg) -> Left (CodegenError msg)
  Right x -> Right x

mapAllocError :: Either String a -> Either CodegenError a
mapAllocError result = case result of
  Left msg -> Left (CodegenError msg)
  Right x -> Right x
