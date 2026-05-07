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
codegenModule (ModuleIr dataItems functions) = do
  bodies <- mapM codegenFunction functions
  pure (unlines (header ++ concat bodies ++ concatMap codegenDataItem dataItems))

header :: [String]
header =
  [ "## hcc M1 output"
  , "## target: stage0-posix amd64 M1"
  , ""
  , "DEFINE HCC_ADD_IMMEDIATE_to_rsp 4881C4"
  , "DEFINE HCC_SUB_IMMEDIATE_from_rsp 4881EC"
  , "DEFINE HCC_STORE_RSP_IMMEDIATE_from_rax 48898424"
  , "DEFINE HCC_LOAD_EFFECTIVE_ADDRESS_rax 488D8424"
  , "DEFINE HCC_COPY_rax_to_rsi 4889C6"
  , "DEFINE HCC_COPY_rax_to_rdx 4889C2"
  , "DEFINE HCC_COPY_rax_to_rcx 4889C1"
  , "DEFINE HCC_COPY_rax_to_r8 4989C0"
  , "DEFINE HCC_COPY_rax_to_r9 4989C1"
  , "DEFINE HCC_COPY_rsi_to_rax 4889F0"
  , "DEFINE HCC_COPY_rdx_to_rax 4889D0"
  , "DEFINE HCC_COPY_rcx_to_rax 4889C8"
  , "DEFINE HCC_COPY_r8_to_rax 4C89C0"
  , "DEFINE HCC_COPY_r9_to_rax 4C89C8"
  , "DEFINE HCC_PUSH_RSI 56"
  , "DEFINE HCC_PUSH_RDX 52"
  , "DEFINE HCC_SHL_eax_cl D3E0"
  , "DEFINE HCC_SHR_eax_cl D3E8"
  , "DEFINE HCC_LOAD_INTEGER 488B00"
  , "DEFINE HCC_STORE_INTEGER 488903"
  , "DEFINE HCC_LOAD_WORD 8B00"
  , "DEFINE HCC_STORE_WORD 8903"
  , "DEFINE HCC_STORE_CHAR 8803"
  , "DEFINE HCC_XOR_rbx_rax_into_rax 4831D8"
  , "DEFINE HCC_CALL_rax FFD0"
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
    body <- codegenInstrs alloc totalSlots instrs
    termCode <- codegenTerminator alloc totalSlots term
    tailCode <- codegenBlocks alloc totalSlots rest
    pure (blockLabel bid ++ body ++ termCode ++ tailCode)

blockLabel :: BlockId -> [String]
blockLabel (BlockId 0) = []
blockLabel (BlockId n) = [":HCC_BLOCK_" ++ show n]

codegenInstrs :: Allocation -> Int -> [Instr] -> Either CodegenError [String]
codegenInstrs alloc totalSlots instrs = case instrs of
  [] -> pure []
  instr:rest -> do
    code <- codegenInstr alloc totalSlots instr
    tailCode <- codegenInstrs alloc totalSlots rest
    pure (code ++ tailCode)

codegenInstr :: Allocation -> Int -> Instr -> Either CodegenError [String]
codegenInstr alloc totalSlots instr = case instr of
  IParam temp index -> do
    code <- loadParam totalSlots index
    storeTemp alloc temp code
  IConst temp value ->
    storeTemp alloc temp ["\tLOAD_IMMEDIATE_rax %" ++ show value]
  ICopy temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp code
  IAddrOf temp source -> do
    sourceLoc <- mapAllocError (lookupLocation source alloc)
    code <- addressOfLocation sourceLoc
    storeTemp alloc temp code
  ILoad64 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["\tHCC_LOAD_INTEGER"])
  ILoad32 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["\tHCC_LOAD_WORD"])
  ILoad8 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["\tLOAD_BYTE", "\tMOVEZX"])
  IStore64 addr value -> do
    addrCode <- loadOperand alloc addr
    valueCode <- loadOperand alloc value
    pure (addrCode ++ ["\tPUSH_RAX", "\tPOP_RBX"] ++ valueCode ++ ["\tHCC_STORE_INTEGER"])
  IStore32 addr value -> do
    addrCode <- loadOperand alloc addr
    valueCode <- loadOperand alloc value
    pure (addrCode ++ ["\tPUSH_RAX", "\tPOP_RBX"] ++ valueCode ++ ["\tHCC_STORE_WORD"])
  IStore8 addr value -> do
    addrCode <- loadOperand alloc addr
    valueCode <- loadOperand alloc value
    pure (addrCode ++ ["\tPUSH_RAX", "\tPOP_RBX"] ++ valueCode ++ ["\tHCC_STORE_CHAR"])
  IBin temp op a b -> do
    acode <- loadOperand alloc a
    bcode <- loadOperand alloc b
    opCode <- binOpCode op
    storeTemp alloc temp (acode ++ ["\tPUSH_RAX", "\tPOP_RBX"] ++ bcode ++ opCode)
  ICall result name args -> do
    argCode <- loadArguments alloc 0 args
    let callCode = argCode ++ ["\tCALL_IMMEDIATE %FUNCTION_" ++ name] ++ cleanupCallStack args
    case result of
      Nothing -> pure callCode
      Just temp -> storeTemp alloc temp callCode
  ICallIndirect result callee args -> do
    argCode <- loadArguments alloc 0 args
    calleeCode <- loadOperand alloc callee
    let callCode = argCode ++ calleeCode ++ ["\tHCC_CALL_rax"] ++ cleanupCallStack args
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
loadArguments alloc _ args = do
  regCode <- loadRegisterArguments alloc 0 (take 6 args)
  stackCode <- loadStackArguments alloc (reverse (drop 6 args))
  pure (regCode ++ stackCode)

loadRegisterArguments :: Allocation -> Int -> [Operand] -> Either CodegenError [String]
loadRegisterArguments alloc index args = case args of
  [] -> pure []
  op:rest -> do
    one <- loadOperand alloc op
    move <- argumentMove index
    tailCode <- loadRegisterArguments alloc (index + 1) rest
    pure (one ++ move ++ tailCode)

loadStackArguments :: Allocation -> [Operand] -> Either CodegenError [String]
loadStackArguments alloc args = case args of
  [] -> pure []
  op:rest -> do
    one <- loadOperand alloc op
    tailCode <- loadStackArguments alloc rest
    pure (one ++ ["\tPUSH_RAX"] ++ tailCode)

cleanupCallStack :: [Operand] -> [String]
cleanupCallStack args =
  let stackArgs = length args - 6
  in if stackArgs <= 0 then [] else ["\tHCC_ADD_IMMEDIATE_to_rsp %" ++ show (stackArgs * 8)]

argumentMove :: Int -> Either CodegenError [String]
argumentMove index = case index of
  0 -> Right ["\tCOPY_rax_to_rdi"]
  1 -> Right ["\tHCC_COPY_rax_to_rsi"]
  2 -> Right ["\tHCC_COPY_rax_to_rdx"]
  3 -> Right ["\tHCC_COPY_rax_to_rcx"]
  4 -> Right ["\tHCC_COPY_rax_to_r8"]
  5 -> Right ["\tHCC_COPY_rax_to_r9"]
  _ -> Left (CodegenError ("unsupported call argument index: " ++ show index))

loadParam :: Int -> Int -> Either CodegenError [String]
loadParam totalSlots index = case index of
  0 -> Right ["\tPUSH_RDI", "\tPOP_RAX"]
  1 -> Right ["\tHCC_COPY_rsi_to_rax"]
  2 -> Right ["\tHCC_COPY_rdx_to_rax"]
  3 -> Right ["\tHCC_COPY_rcx_to_rax"]
  4 -> Right ["\tHCC_COPY_r8_to_rax"]
  5 -> Right ["\tHCC_COPY_r9_to_rax"]
  _ -> Right ["\tLOAD_RSP_IMMEDIATE_into_rax %" ++ show (totalSlots * 8 + 8 + (index - 6) * 8)]

binOpCode :: BinOp -> Either CodegenError [String]
binOpCode op = case op of
  IAdd -> Right ["\tADD_rbx_to_rax"]
  ISub -> Right ["\tSUBTRACT_rax_from_rbx_into_rbx", "\tMOVE_rbx_to_rax"]
  IMul -> Right ["\tMULTIPLY_rax_by_rbx_into_rax"]
  IDiv -> Right ["\tXCHG_rax_rbx", "\tCQTO", "\tDIVIDES_rax_by_rbx_into_rax"]
  IMod -> Right ["\tXCHG_rax_rbx", "\tCQTO", "\tMODULUSS_rax_from_rbx_into_rbx", "\tMOVE_rdx_to_rax"]
  IShl -> Right ["\tCOPY_rax_to_rcx", "\tMOVE_rbx_to_rax", "\tHCC_SHL_eax_cl"]
  IShr -> Right ["\tCOPY_rax_to_rcx", "\tMOVE_rbx_to_rax", "\tHCC_SHR_eax_cl"]
  IEq -> Right ["\tCMP", "\tSETE", "\tMOVEZX"]
  INe -> Right ["\tCMP", "\tSETNE", "\tMOVEZX"]
  ILt -> Right ["\tCMP", "\tSETL", "\tMOVEZX"]
  ILe -> Right ["\tCMP", "\tSETLE", "\tMOVEZX"]
  IGt -> Right ["\tCMP", "\tSETG", "\tMOVEZX"]
  IGe -> Right ["\tCMP", "\tSETGE", "\tMOVEZX"]
  IAnd -> Right ["\tAND_rax_rbx"]
  IOr -> Right ["\tOR_rax_rbx"]
  IXor -> Right ["\tHCC_XOR_rbx_rax_into_rax"]

loadOperand :: Allocation -> Operand -> Either CodegenError [String]
loadOperand alloc op = case op of
  OImm value -> Right ["\tLOAD_IMMEDIATE_rax %" ++ show value]
  OGlobal name -> Right ["\tLOAD_IMMEDIATE_rax &" ++ name]
  OFunction name -> Right ["\tLOAD_IMMEDIATE_rax &FUNCTION_" ++ name]
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

addressOfLocation :: Location -> Either CodegenError [String]
addressOfLocation loc = case loc of
  OnStack slot -> Right ["\tHCC_LOAD_EFFECTIVE_ADDRESS_rax %" ++ show (8 * slot)]
  InReg _ -> Left (CodegenError "cannot take address of register-allocated value")

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

codegenDataItem :: DataItem -> [String]
codegenDataItem (DataItem label bytes) =
  [":" ++ label, "\t" ++ joinWords (map byteHex bytes), ""]

byteHex :: Int -> String
byteHex value =
  let digits = "0123456789ABCDEF"
      b = value `mod` 256
  in "'" ++ [digits !! (b `div` 16), digits !! (b `mod` 16)] ++ "'"

joinWords :: [String] -> String
joinWords xs = case xs of
  [] -> ""
  [x] -> x
  x:rest -> x ++ " " ++ joinWords rest

mapCompileError :: Either CompileError a -> Either CodegenError a
mapCompileError result = case result of
  Left (CompileError msg) -> Left (CodegenError msg)
  Right x -> Right x

mapAllocError :: Either String a -> Either CodegenError a
mapAllocError result = case result of
  Left msg -> Left (CodegenError msg)
  Right x -> Right x
