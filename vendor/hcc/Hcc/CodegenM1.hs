module Hcc.CodegenM1
  ( CodegenError(..)
  , codegenM1
  , codegenM1WithDataPrefix
  ) where

import Hcc.Ast
import Hcc.CompileM
import Hcc.Ir
import Hcc.Lower
import Hcc.RegAlloc

data CodegenError = CodegenError String
  deriving (Eq, Show)

type Lines = [String] -> [String]

codegenM1 :: Program -> Either CodegenError String
codegenM1 = codegenM1WithDataPrefix "HCC_DATA"

codegenM1WithDataPrefix :: String -> Program -> Either CodegenError String
codegenM1WithDataPrefix prefix ast = do
  ir <- mapCompileError (lowerProgramWithDataPrefix prefix ast)
  codegenModule ir

codegenModule :: ModuleIr -> Either CodegenError String
codegenModule (ModuleIr dataItems functions) = do
  bodies <- mapM codegenFunction functions
  pure (renderLines (linesFromList header . composeLines bodies . composeLines (map (linesFromList . codegenDataItem) dataItems)))

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
  , "DEFINE HCC_SHL_rax_cl 48D3E0"
  , "DEFINE HCC_SHR_rax_cl 48D3E8"
  , "DEFINE HCC_SAR_rax_cl 48D3F8"
  , "DEFINE HCC_LOAD_INTEGER 488B00"
  , "DEFINE HCC_STORE_INTEGER 488903"
  , "DEFINE HCC_LOAD_WORD 8B00"
  , "DEFINE HCC_LOAD_SIGNED_WORD 486300"
  , "DEFINE HCC_LOAD_HALF 0FB700"
  , "DEFINE HCC_LOAD_SIGNED_HALF 480FBF00"
  , "DEFINE HCC_STORE_WORD 8903"
  , "DEFINE HCC_STORE_HALF 668903"
  , "DEFINE HCC_STORE_CHAR 8803"
  , "DEFINE HCC_LOAD_SIGNED_CHAR 480FBE00"
  , "DEFINE HCC_XOR_rbx_rax_into_rax 4831D8"
  , "DEFINE HCC_CALL_rax FFD0"
  , ""
  ]

codegenFunction :: FunctionIr -> Either CodegenError Lines
codegenFunction fn@(FunctionIr name _ blocks) = do
  alloc <- mapAllocError (allocateFunction fn)
  body <- withCodegenContext ("function " ++ name) (codegenBlocks name alloc (stackSlotCount alloc) blocks)
  pure (line (":FUNCTION_" ++ name) . linesFromList (prologue (stackSlotCount alloc)) . body . line "")

withCodegenContext :: String -> Either CodegenError a -> Either CodegenError a
withCodegenContext context result = case result of
  Left (CodegenError msg) -> Left (CodegenError (context ++ ": " ++ msg))
  Right value -> Right value

prologue :: Int -> [String]
prologue slots =
  if slots == 0 then [] else ["\tHCC_SUB_IMMEDIATE_from_rsp %" ++ show (slots * 8)]

codegenBlocks :: String -> Allocation -> Int -> [BasicBlock] -> Either CodegenError Lines
codegenBlocks fnName alloc totalSlots blocks = case blocks of
  [] -> pure id
  BasicBlock bid instrs term:rest -> do
    body <- codegenInstrs fnName alloc totalSlots instrs
    termCode <- codegenTerminator fnName alloc totalSlots term
    tailCode <- codegenBlocks fnName alloc totalSlots rest
    pure (linesFromList (blockLabel fnName bid) . linesFromList body . linesFromList termCode . tailCode)

blockLabel :: String -> BlockId -> [String]
blockLabel _ (BlockId 0) = []
blockLabel fnName (BlockId n) = [":" ++ blockRef fnName (BlockId n)]

codegenInstrs :: String -> Allocation -> Int -> [Instr] -> Either CodegenError [String]
codegenInstrs fnName alloc totalSlots instrs = case instrs of
  [] -> pure []
  instr:rest -> do
    code <- codegenInstr fnName alloc totalSlots instr
    tailCode <- codegenInstrs fnName alloc totalSlots rest
    pure (code ++ tailCode)

codegenInstr :: String -> Allocation -> Int -> Instr -> Either CodegenError [String]
codegenInstr fnName alloc totalSlots instr = case instr of
  IParam temp index -> do
    code <- loadParam totalSlots index
    storeTemp alloc temp code
  IAlloca _ _ ->
    pure []
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
  ILoadS32 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["\tHCC_LOAD_SIGNED_WORD"])
  ILoad16 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["\tHCC_LOAD_HALF"])
  ILoadS16 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["\tHCC_LOAD_SIGNED_HALF"])
  ILoad8 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["\tLOAD_BYTE", "\tMOVEZX"])
  ILoadS8 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["\tHCC_LOAD_SIGNED_CHAR"])
  IStore64 addr value -> do
    addrCode <- loadOperand alloc addr
    valueCode <- loadOperand alloc value
    pure (addrCode ++ ["\tPUSH_RAX", "\tPOP_RBX"] ++ valueCode ++ ["\tHCC_STORE_INTEGER"])
  IStore32 addr value -> do
    addrCode <- loadOperand alloc addr
    valueCode <- loadOperand alloc value
    pure (addrCode ++ ["\tPUSH_RAX", "\tPOP_RBX"] ++ valueCode ++ ["\tHCC_STORE_WORD"])
  IStore16 addr value -> do
    addrCode <- loadOperand alloc addr
    valueCode <- loadOperand alloc value
    pure (addrCode ++ ["\tPUSH_RAX", "\tPOP_RBX"] ++ valueCode ++ ["\tHCC_STORE_HALF"])
  IStore8 addr value -> do
    addrCode <- loadOperand alloc addr
    valueCode <- loadOperand alloc value
    pure (addrCode ++ ["\tPUSH_RAX", "\tPOP_RBX"] ++ valueCode ++ ["\tHCC_STORE_CHAR"])
  IBin temp op a b -> do
    acode <- loadOperand alloc a
    bcode <- loadOperand alloc b
    opCode <- binOpCode op
    storeTemp alloc temp (acode ++ ["\tPUSH_RAX", "\tPOP_RBX"] ++ bcode ++ opCode)
  ICond temp condInstrs condOp trueInstrs trueOp falseInstrs falseOp -> do
    condCode <- codegenInstrs fnName alloc totalSlots condInstrs
    condLoad <- loadOperand alloc condOp
    trueCode <- codegenInstrs fnName alloc totalSlots trueInstrs
    trueLoad <- loadOperand alloc trueOp
    falseCode <- codegenInstrs fnName alloc totalSlots falseInstrs
    falseLoad <- loadOperand alloc falseOp
    let Temp n = temp
    let elseLabel = "HCC_COND_ELSE_" ++ fnName ++ "_" ++ show n
    let doneLabel = "HCC_COND_DONE_" ++ fnName ++ "_" ++ show n
    trueStore <- storeTemp alloc temp trueLoad
    falseStore <- storeTemp alloc temp falseLoad
    pure ( condCode ++ condLoad ++
           [ "\tTEST"
           , "\tJUMP_NE %" ++ doneLabel ++ "_TRUE"
           , "\tJUMP %" ++ elseLabel
           , ":" ++ doneLabel ++ "_TRUE"
           ] ++
           trueCode ++ trueStore ++
           [ "\tJUMP %" ++ doneLabel
           , ":" ++ elseLabel
           ] ++
           falseCode ++ falseStore ++
           [":" ++ doneLabel])
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

codegenTerminator :: String -> Allocation -> Int -> Terminator -> Either CodegenError [String]
codegenTerminator fnName alloc totalSlots term = case term of
  TRet Nothing -> pure (["\tLOAD_IMMEDIATE_rax %0"] ++ cleanupStack totalSlots ++ ["\tRETURN"])
  TRet (Just op) -> do
    code <- loadOperand alloc op
    pure (code ++ cleanupStack totalSlots ++ ["\tRETURN"])
  TJump bid -> pure ["\tJUMP %" ++ blockRef fnName bid]
  TBranch op yes no -> do
    code <- loadOperand alloc op
    pure (code ++ ["\tTEST", "\tJUMP_NE %" ++ blockRef fnName yes, "\tJUMP %" ++ blockRef fnName no])

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
  IShl -> Right ["\tCOPY_rax_to_rcx", "\tMOVE_rbx_to_rax", "\tHCC_SHL_rax_cl"]
  IShr -> Right ["\tCOPY_rax_to_rcx", "\tMOVE_rbx_to_rax", "\tHCC_SHR_rax_cl"]
  ISar -> Right ["\tCOPY_rax_to_rcx", "\tMOVE_rbx_to_rax", "\tHCC_SAR_rax_cl"]
  IEq -> Right ["\tCMP", "\tSETE", "\tMOVEZX"]
  INe -> Right ["\tCMP", "\tSETNE", "\tMOVEZX"]
  ILt -> Right ["\tCMP", "\tSETL", "\tMOVEZX"]
  ILe -> Right ["\tCMP", "\tSETLE", "\tMOVEZX"]
  IGt -> Right ["\tCMP", "\tSETG", "\tMOVEZX"]
  IGe -> Right ["\tCMP", "\tSETGE", "\tMOVEZX"]
  IULt -> Right ["\tCMP", "\tSETB", "\tMOVEZX"]
  IULe -> Right ["\tCMP", "\tSETBE", "\tMOVEZX"]
  IUGt -> Right ["\tCMP", "\tSETA", "\tMOVEZX"]
  IUGe -> Right ["\tCMP", "\tSETAE", "\tMOVEZX"]
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
  StackObject slot _ -> Right ["\tHCC_LOAD_EFFECTIVE_ADDRESS_rax %" ++ show (8 * slot)]

addressOfLocation :: Location -> Either CodegenError [String]
addressOfLocation loc = case loc of
    OnStack slot -> Right ["\tHCC_LOAD_EFFECTIVE_ADDRESS_rax %" ++ show (8 * slot)]
    StackObject slot _ -> Right ["\tHCC_LOAD_EFFECTIVE_ADDRESS_rax %" ++ show (8 * slot)]
    InReg _ -> Left (CodegenError "cannot take address of register-allocated value")

storeTemp :: Allocation -> Temp -> [String] -> Either CodegenError [String]
storeTemp alloc temp code = do
  loc <- mapAllocError (lookupLocation temp alloc)
  case loc of
    OnStack slot -> Right (code ++ ["\tHCC_STORE_RSP_IMMEDIATE_from_rax %" ++ show (8 * slot)])
    StackObject{} -> Left (CodegenError ("cannot assign to stack object address: " ++ show temp))
    InReg _ -> Right code

cleanupStack :: Int -> [String]
cleanupStack slots =
  if slots == 0 then [] else ["\tHCC_ADD_IMMEDIATE_to_rsp %" ++ show (slots * 8)]

blockRef :: String -> BlockId -> String
blockRef fnName (BlockId n) = "HCC_BLOCK_" ++ fnName ++ "_" ++ show n

codegenDataItem :: DataItem -> [String]
codegenDataItem (DataItem label values) =
  [":" ++ label, "\t" ++ joinWords (map dataValueM1 values), ""]

dataValueM1 :: DataValue -> String
dataValueM1 value = case value of
  DByte byte -> byteHex byte
  DAddress label -> "&" ++ label ++ " '00' '00' '00' '00'"

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

linesFromList :: [String] -> Lines
linesFromList = (++)

line :: String -> Lines
line text = (text:)

composeLines :: [Lines] -> Lines
composeLines builders = case builders of
  [] -> id
  builder:rest -> builder . composeLines rest

renderLines :: Lines -> String
renderLines builder = go (builder []) "" where
  go :: [String] -> ShowS
  go lines' = case lines' of
    [] -> id
    text:rest -> showString text . showChar '\n' . go rest

mapCompileError :: Either CompileError a -> Either CodegenError a
mapCompileError result = case result of
  Left (CompileError msg) -> Left (CodegenError msg)
  Right x -> Right x

mapAllocError :: Either String a -> Either CodegenError a
mapAllocError result = case result of
  Left msg -> Left (CodegenError msg)
  Right x -> Right x
