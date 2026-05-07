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
  body <- codegenBlocks alloc 0 blocks
  pure ((":FUNCTION_" ++ name) : body ++ [""])

codegenBlocks :: Allocation -> Int -> [BasicBlock] -> Either CodegenError [String]
codegenBlocks alloc slots blocks = case blocks of
  [] -> pure []
  BasicBlock bid instrs term:rest -> do
    (body, slots') <- codegenInstrs alloc slots instrs
    termCode <- codegenTerminator alloc slots' term
    tailCode <- codegenBlocks alloc slots' rest
    pure (blockLabel bid ++ body ++ termCode ++ tailCode)

blockLabel :: BlockId -> [String]
blockLabel (BlockId 0) = []
blockLabel (BlockId n) = [":HCC_BLOCK_" ++ show n]

codegenInstrs :: Allocation -> Int -> [Instr] -> Either CodegenError ([String], Int)
codegenInstrs alloc slots instrs = case instrs of
  [] -> pure ([], slots)
  instr:rest -> do
    (code, slots') <- codegenInstr alloc slots instr
    (tailCode, slots'') <- codegenInstrs alloc slots' rest
    pure (code ++ tailCode, slots'')

codegenInstr :: Allocation -> Int -> Instr -> Either CodegenError ([String], Int)
codegenInstr alloc slots instr = case instr of
  IParam{} -> pure ([], slots)
  IConst temp value ->
    storeTemp alloc slots temp ["\tLOAD_IMMEDIATE_rax %" ++ show value]
  IBin temp op a b -> do
    acode <- loadOperand alloc slots a
    bcode <- loadOperand alloc (slots + 1) b
    opCode <- binOpCode op
    storeTemp alloc slots temp (acode ++ ["\tPUSH_RAX"] ++ bcode ++ ["\tPOP_RBX"] ++ opCode)
  ICall result name args -> do
    argCode <- loadArguments alloc slots 0 args
    let callCode = argCode ++ ["\tCALL_IMMEDIATE %FUNCTION_" ++ name]
    case result of
      Nothing -> pure (callCode, slots)
      Just temp -> storeTemp alloc slots temp callCode

codegenTerminator :: Allocation -> Int -> Terminator -> Either CodegenError [String]
codegenTerminator alloc slots term = case term of
  TRet Nothing -> pure (["\tLOAD_IMMEDIATE_rax %0"] ++ cleanupStack slots ++ ["\tRETURN"])
  TRet (Just op) -> do
    code <- loadOperand alloc slots op
    pure (code ++ cleanupStack slots ++ ["\tRETURN"])
  TJump{} -> Left (CodegenError "M1 backend does not support jumps yet")
  TBranch{} -> Left (CodegenError "M1 backend does not support branches yet")

loadArguments :: Allocation -> Int -> Int -> [Operand] -> Either CodegenError [String]
loadArguments alloc slots index args = case args of
  [] -> pure []
  op:rest -> do
    one <- loadOperand alloc slots op
    move <- argumentMove index
    tailCode <- loadArguments alloc slots (index + 1) rest
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

loadOperand :: Allocation -> Int -> Operand -> Either CodegenError [String]
loadOperand alloc slots op = case op of
  OImm value -> Right ["\tLOAD_IMMEDIATE_rax %" ++ show value]
  OGlobal name -> Left (CodegenError ("cannot load global yet: " ++ name))
  OTemp temp -> do
    loc <- mapAllocError (lookupLocation temp alloc)
    loadLocation slots loc

loadLocation :: Int -> Location -> Either CodegenError [String]
loadLocation slots loc = case loc of
  InReg Rax -> Right []
  InReg Rbx -> Right ["\tMOVE_rbx_to_rax"]
  InReg Rdi -> Right ["\tPUSH_RDI", "\tPOP_RAX"]
  InReg Rsi -> Right ["\tHCC_COPY_rsi_to_rax"]
  InReg Rdx -> Right ["\tHCC_COPY_rdx_to_rax"]
  OnStack slot ->
    let offset = 8 * (slots - 1 - slot)
    in if offset < 0
       then Left (CodegenError ("stack slot not initialized: " ++ show slot))
       else Right ["\tLOAD_RSP_IMMEDIATE_into_rax %" ++ show offset]

storeTemp :: Allocation -> Int -> Temp -> [String] -> Either CodegenError ([String], Int)
storeTemp alloc slots temp code = do
  loc <- mapAllocError (lookupLocation temp alloc)
  case loc of
    OnStack slot | slot == slots -> Right (code ++ ["\tPUSH_RAX"], slots + 1)
                 | otherwise -> Left (CodegenError ("non-linear stack slot assignment: " ++ show slot))
    InReg _ -> Right (code, slots)

cleanupStack :: Int -> [String]
cleanupStack slots =
  if slots == 0 then [] else ["\tHCC_ADD_IMMEDIATE_to_rsp %" ++ show (slots * 8)]

mapCompileError :: Either CompileError a -> Either CodegenError a
mapCompileError result = case result of
  Left (CompileError msg) -> Left (CodegenError msg)
  Right x -> Right x

mapAllocError :: Either String a -> Either CodegenError a
mapAllocError result = case result of
  Left msg -> Left (CodegenError msg)
  Right x -> Right x
