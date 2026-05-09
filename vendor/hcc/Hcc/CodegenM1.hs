module CodegenM1 where

import Base
import Ast
import CompileM
import IntTable
import Ir
import Lower
import LowerBootstrap
import LowerImplicit
import RegAlloc
import TextBuilder

data CodegenError = CodegenError String

type Lines = [String] -> [String]

codegenM1 :: Program -> Either CodegenError String
codegenM1 = codegenM1WithDataPrefix "HCC_DATA"

codegenM1WithDataPrefix :: String -> Program -> Either CodegenError String
codegenM1WithDataPrefix prefix ast = do
  lines' <- codegenM1LinesWithDataPrefix prefix ast
  pure (renderLineList lines')

codegenM1LinesWithDataPrefix :: String -> Program -> Either CodegenError [String]
codegenM1LinesWithDataPrefix prefix ast = do
  ir <- mapCompileError (lowerProgramWithDataPrefix prefix ast)
  codegenModuleLines ir

codegenM1WriteWithDataPrefix :: ([String] -> IO ()) -> String -> Program -> IO (Either CodegenError ())
codegenM1WriteWithDataPrefix write = codegenM1WriteTraceWithDataPrefix write (\_ -> pure ())

codegenM1WriteTraceWithDataPrefix :: ([String] -> IO ()) -> (String -> IO ()) -> String -> Program -> IO (Either CodegenError ())
codegenM1WriteTraceWithDataPrefix write trace prefix (Program decls) = do
  trace "registering declarations"
  case mapCompileRun (unCompileM registerBuiltinStructs initialCompileState { csDataPrefix = prefix }) of
    Left err -> pure (Left err)
    Right (_, st0) -> do
      trace "header"
      write header
      registered <- registerTopDeclsShallowIO write trace st0 decls
      case registered of
        Left err -> pure (Left err)
        Right st -> codegenTopDeclsWrite write trace st decls

codegenModuleLines :: ModuleIr -> Either CodegenError [String]
codegenModuleLines (ModuleIr dataItems functions) = do
  bodies <- mapM codegenFunction functions
  pure ((linesFromList header . composeLines bodies . composeLines (map (linesFromList . codegenDataItem) dataItems)) [])

codegenModuleWrite :: ([String] -> IO ()) -> (String -> IO ()) -> ModuleIr -> IO (Either CodegenError ())
codegenModuleWrite write trace (ModuleIr dataItems functions) = do
  trace "header"
  write header
  codegenDataItemsWrite write trace dataItems
  codegenFunctionsWrite write trace functions

codegenDataItemsWrite :: ([String] -> IO ()) -> (String -> IO ()) -> [DataItem] -> IO ()
codegenDataItemsWrite write trace items = case items of
  [] -> pure ()
  item:rest -> do
    codegenDataItemWrite write item
    codegenDataItemsWrite write trace rest

codegenFunctionsWrite :: ([String] -> IO ()) -> (String -> IO ()) -> [FunctionIr] -> IO (Either CodegenError ())
codegenFunctionsWrite write trace functions = case functions of
  [] -> pure (Right ())
  fn@(FunctionIr name _ _):rest -> do
    trace ("function " ++ name)
    case codegenFunction fn of
      Left err -> pure (Left err)
      Right builder -> do
        write (builder [])
        codegenFunctionsWrite write trace rest

codegenTopDeclsWrite :: ([String] -> IO ()) -> (String -> IO ()) -> CompileState -> [TopDecl] -> IO (Either CodegenError ())
codegenTopDeclsWrite write trace st decls = case decls of
  [] -> pure (Right ())
  Function _ name params body:rest -> do
    trace ("lower function " ++ name)
    case mapCompileRun (unCompileM (registerImplicitCalls (paramDeclNames params) body >> lowerFunction name params body) st) of
      Left err -> pure (Left err)
      Right (fn, st') -> case codegenFunction fn of
        Left err -> pure (Left err)
        Right builder -> do
          trace ("write function " ++ name)
          write (builder [])
          st'' <- flushPendingDataItems write st'
          codegenTopDeclsWrite write trace st'' rest
  _:rest -> codegenTopDeclsWrite write trace st rest

registerTopDeclsShallow :: [TopDecl] -> CompileM ()
registerTopDeclsShallow decls = CompileM $ \st -> registerTopDeclsShallowState st decls

registerTopDeclsShallowState :: CompileState -> [TopDecl] -> Either CompileError ((), CompileState)
registerTopDeclsShallowState st decls = case decls of
  [] -> Right ((), st)
  decl:rest -> case registerTopDeclShallowState st decl of
    Left err -> Left err
    Right ((), st') -> registerTopDeclsShallowState st' rest

registerTopDeclShallowState :: CompileState -> TopDecl -> Either CompileError ((), CompileState)
registerTopDeclShallowState st decl = case decl of
  Function ty name _ _ ->
    unCompileM (registerTypeAggregates ty >> bindGlobal name ty >> bindFunction name) st
  Prototype ty name _ ->
    unCompileM (registerTypeAggregates ty >> bindGlobal name ty >> bindFunction name) st
  StructDecl isUnion name fields ->
    unCompileM (registerFieldAggregates fields >> bindStruct name isUnion fields) st
  Global ty name initExpr ->
    unCompileM (registerTypeAggregates ty >> bindGlobal name ty >> globalData ty initExpr >>= addDataItem . DataItem name) st
  ExternGlobals globals ->
    unCompileM (registerExternGlobals globals) st
  Globals globals ->
    unCompileM (registerGlobals globals) st
  EnumConstants constants ->
    unCompileM (registerConstants constants) st
  _ -> Right ((), st)

registerTopDeclsShallowIO :: ([String] -> IO ()) -> (String -> IO ()) -> CompileState -> [TopDecl] -> IO (Either CodegenError CompileState)
registerTopDeclsShallowIO write trace st decls = case decls of
  [] -> pure (Right st)
  decl:rest -> do
    trace (registerTopDeclTrace decl)
    result <- registerTopDeclShallowWriteState write st decl
    case mapCompileRun result of
      Left err -> pure (Left err)
      Right (_, st') -> registerTopDeclsShallowIO write trace st' rest

registerTopDeclShallowWriteState :: ([String] -> IO ()) -> CompileState -> TopDecl -> IO (Either CompileError ((), CompileState))
registerTopDeclShallowWriteState write st decl = case decl of
  Global ty name initExpr ->
    case unCompileM (registerTypeAggregates ty >> bindGlobal name ty >> globalData ty initExpr) st of
      Left err -> pure (Left err)
      Right (values, st') -> do
        codegenDataItemWrite write (DataItem name values)
        st'' <- flushPendingDataItems write st'
        pure (Right ((), st''))
  Globals globals ->
    registerGlobalsShallowWriteState write st globals
  _ -> pure (registerTopDeclShallowState st decl)

registerGlobalsShallowWriteState :: ([String] -> IO ()) -> CompileState -> [(CType, String, Maybe Expr)] -> IO (Either CompileError ((), CompileState))
registerGlobalsShallowWriteState write st globals = case globals of
  [] -> pure (Right ((), st))
  (ty, name, initExpr):rest ->
    case unCompileM (registerTypeAggregates ty >> bindGlobal name ty >> globalData ty initExpr) st of
      Left err -> pure (Left err)
      Right (values, st') -> do
        codegenDataItemWrite write (DataItem name values)
        st'' <- flushPendingDataItems write st'
        registerGlobalsShallowWriteState write st'' rest

flushPendingDataItems :: ([String] -> IO ()) -> CompileState -> IO CompileState
flushPendingDataItems write st = case csDataItems st of
  [] -> pure st
  items -> do
    codegenDataItemsWrite write (\_ -> pure ()) (reverse items)
    pure st { csDataItems = [] }

registerTopDeclTrace :: TopDecl -> String
registerTopDeclTrace decl = case decl of
  Function _ name _ _ -> "register function " ++ name
  Prototype _ name _ -> "register prototype " ++ name
  StructDecl _ name _ -> "register struct " ++ name
  Global _ name _ -> "register global " ++ name
  ExternGlobals _ -> "register extern globals"
  Globals _ -> "register globals"
  EnumConstants _ -> "register enum constants"
  TypeDecl -> "register typedef"

paramDeclNames :: [Param] -> [String]
paramDeclNames params = case params of
  [] -> []
  Param _ name:rest -> name : paramDeclNames rest

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
  , "DEFINE HCC_M_RAX_RBX 4889C3"
  , "DEFINE HCC_COPY_rax_to_r8 4989C0"
  , "DEFINE HCC_COPY_rax_to_r9 4989C1"
  , "DEFINE HCC_M_RDI_RAX 4889F8"
  , "DEFINE HCC_COPY_rsi_to_rax 4889F0"
  , "DEFINE HCC_COPY_rdx_to_rax 4889D0"
  , "DEFINE HCC_COPY_rcx_to_rax 4889C8"
  , "DEFINE HCC_COPY_r8_to_rax 4C89C0"
  , "DEFINE HCC_COPY_r9_to_rax 4C89C8"
  , "DEFINE HCC_PUSH_RSI 56"
  , "DEFINE HCC_PUSH_RDX 52"
  , "DEFINE HCC_LOAD_IMMEDIATE64_rax 48B8"
  , "DEFINE HCC_LI64_80000000 48B80000008000000000"
  , "DEFINE HCC_LI64_FFFFFFFF 48B8FFFFFFFF00000000"
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
codegenFunction fn = do
  let optimized@(FunctionIr name _ blocks) = optimizeFunctionIr fn
  alloc <- mapAllocError (allocateFunction optimized)
  body <- withCodegenContext ("function " ++ name) (codegenBlocks name alloc (stackSlotCount alloc) blocks)
  pure (line (":FUNCTION_" ++ name) . linesFromList (prologue (stackSlotCount alloc)) . body . line "")

optimizeFunctionIr :: FunctionIr -> FunctionIr
optimizeFunctionIr fn = case fn of
  FunctionIr name params blocks ->
    let simplified = map simplifyBasicBlock blocks
        stats = functionStats simplified
    in FunctionIr name params (map (optimizeBasicBlock stats) simplified)

simplifyBasicBlock :: BasicBlock -> BasicBlock
simplifyBasicBlock block = case block of
  BasicBlock bid instrs term ->
    BasicBlock bid (map simplifyInstr instrs) term

simplifyInstr :: Instr -> Instr
simplifyInstr instr = case instr of
  IBin temp op a b -> simplifyBin temp op a b
  _ -> instr

simplifyBin :: Temp -> BinOp -> Operand -> Operand -> Instr
simplifyBin temp op a b = case op of
  IAdd ->
    if isZeroOperand a
    then ICopy temp b
    else if isZeroOperand b
      then ICopy temp a
      else IBin temp op a b
  ISub ->
    if isZeroOperand b || sameOperand a b
    then if sameOperand a b then IConst temp 0 else ICopy temp a
    else IBin temp op a b
  IMul ->
    if isZeroOperand a || isZeroOperand b
    then IConst temp 0
    else if isOneOperand a
      then ICopy temp b
      else if isOneOperand b
        then ICopy temp a
        else IBin temp op a b
  IDiv ->
    if isOneOperand b
    then ICopy temp a
    else IBin temp op a b
  IMod ->
    if isOneOperand b || sameOperand a b
    then IConst temp 0
    else IBin temp op a b
  IShl ->
    if isZeroOperand b then ICopy temp a else IBin temp op a b
  IShr ->
    if isZeroOperand b then ICopy temp a else IBin temp op a b
  ISar ->
    if isZeroOperand b then ICopy temp a else IBin temp op a b
  IEq ->
    if sameOperand a b then IConst temp 1 else IBin temp op a b
  INe ->
    if sameOperand a b then IConst temp 0 else IBin temp op a b
  ILt ->
    if sameOperand a b then IConst temp 0 else IBin temp op a b
  ILe ->
    if sameOperand a b then IConst temp 1 else IBin temp op a b
  IGt ->
    if sameOperand a b then IConst temp 0 else IBin temp op a b
  IGe ->
    if sameOperand a b then IConst temp 1 else IBin temp op a b
  IULt ->
    if sameOperand a b then IConst temp 0 else IBin temp op a b
  IULe ->
    if sameOperand a b then IConst temp 1 else IBin temp op a b
  IUGt ->
    if sameOperand a b then IConst temp 0 else IBin temp op a b
  IUGe ->
    if sameOperand a b then IConst temp 1 else IBin temp op a b
  IAnd ->
    if isZeroOperand a || isZeroOperand b
    then IConst temp 0
    else if sameOperand a b
      then ICopy temp a
      else IBin temp op a b
  IOr ->
    if isZeroOperand a
    then ICopy temp b
    else if isZeroOperand b || sameOperand a b
      then ICopy temp a
      else IBin temp op a b
  IXor ->
    if isZeroOperand a
    then ICopy temp b
    else if isZeroOperand b
      then ICopy temp a
      else if sameOperand a b
        then IConst temp 0
        else IBin temp op a b

isZeroOperand :: Operand -> Bool
isZeroOperand op = case op of
  OImm value -> value == 0
  OImmBytes bytes -> allZeroBytes bytes
  _ -> False

isOneOperand :: Operand -> Bool
isOneOperand op = case op of
  OImm value -> value == 1
  OImmBytes bytes -> oneThenZeroBytes bytes
  _ -> False

oneThenZeroBytes :: [Int] -> Bool
oneThenZeroBytes bytes = case bytes of
  [] -> False
  b:rest -> b == 1 && allZeroBytes rest

allZeroBytes :: [Int] -> Bool
allZeroBytes bytes = case bytes of
  [] -> True
  b:rest -> b == 0 && allZeroBytes rest

sameOperand :: Operand -> Operand -> Bool
sameOperand a b = case a of
  OTemp ta -> case b of
    OTemp tb -> sameTemp ta tb
    _ -> False
  OImm va -> case b of
    OImm vb -> va == vb
    _ -> False
  OImmBytes ba -> case b of
    OImmBytes bb -> sameInts ba bb
    _ -> False
  OGlobal na -> case b of
    OGlobal nb -> na == nb
    _ -> False
  OFunction na -> case b of
    OFunction nb -> na == nb
    _ -> False

sameTemp :: Temp -> Temp -> Bool
sameTemp a b = case a of
  Temp x -> case b of
    Temp y -> x == y

sameInts :: [Int] -> [Int] -> Bool
sameInts a b = case a of
  [] -> case b of
    [] -> True
    _ -> False
  x:xs -> case b of
    [] -> False
    y:ys -> x == y && sameInts xs ys

optimizeBasicBlock :: BlockStats -> BasicBlock -> BasicBlock
optimizeBasicBlock globalStats block = case block of
  BasicBlock bid instrs term ->
    if containsCondInstr instrs
    then block
    else
      let localStats = blockStats instrs term
          optimized = optimizeInstrs globalStats localStats intMapEmpty instrs
          term' = term
      in BasicBlock bid optimized term'

functionStats :: [BasicBlock] -> BlockStats
functionStats blocks =
  functionStatsFrom blocks (BlockStats intMapEmpty intMapEmpty intMapEmpty)

functionStatsFrom :: [BasicBlock] -> BlockStats -> BlockStats
functionStatsFrom blocks stats = case blocks of
  [] -> stats
  BasicBlock _ instrs term:rest ->
    functionStatsFrom rest (countTerminator term (countInstrList instrs stats))

containsCondInstr :: [Instr] -> Bool
containsCondInstr instrs = case instrs of
  [] -> False
  ICond _ _ _ _ _ _ _: _ -> True
  _:rest -> containsCondInstr rest

data BlockStats = BlockStats (IntMap Int) (IntMap Int) (IntMap Bool)

blockStats :: [Instr] -> Terminator -> BlockStats
blockStats instrs term =
  let emptyStats = BlockStats intMapEmpty intMapEmpty intMapEmpty
      instrStats = countInstrList instrs emptyStats
      termStats = countTerminator term instrStats
      blockedStats = blockTerminatorTemps term (blockNestedCondTemps instrs termStats)
  in blockedStats

optimizeInstrs :: BlockStats -> BlockStats -> IntMap Operand -> [Instr] -> [Instr]
optimizeInstrs globalStats localStats env instrs = case instrs of
  [] -> []
  instr:rest ->
    if pureForwardable globalStats localStats instr
    then case pureForwardValue instr of
      Just pair -> case pair of
        (Temp key, op) ->
          optimizeInstrs globalStats localStats (intMapInsert key (rewriteOperand env op) env) rest
      Nothing -> optimizeInstrs globalStats localStats env rest
    else
      let instr' = rewriteInstr env instr
      in instr' : optimizeInstrs globalStats localStats env rest

pureForwardable :: BlockStats -> BlockStats -> Instr -> Bool
pureForwardable globalStats localStats instr = case pureForwardValue instr of
  Nothing -> False
  Just pair -> case pair of
    (temp, _) ->
      tempDefCount localStats temp == 1 &&
      tempDefCount globalStats temp == 1 &&
      tempUseCount localStats temp == tempUseCount globalStats temp &&
      tempUseCount localStats temp <= 1 &&
      not (tempBlocked localStats temp) &&
      not (tempBlocked globalStats temp)

pureForwardValue :: Instr -> Maybe (Temp, Operand)
pureForwardValue instr = case instr of
  IConst temp value -> Just (temp, OImm value)
  IConstBytes temp bytes -> Just (temp, OImmBytes bytes)
  ICopy temp op -> Just (temp, op)
  _ -> Nothing

rewriteInstr :: IntMap Operand -> Instr -> Instr
rewriteInstr env instr = case instr of
  ICopy temp op -> ICopy temp (rewriteOperand env op)
  ILoad64 temp op -> ILoad64 temp (rewriteOperand env op)
  ILoad32 temp op -> ILoad32 temp (rewriteOperand env op)
  ILoadS32 temp op -> ILoadS32 temp (rewriteOperand env op)
  ILoad16 temp op -> ILoad16 temp (rewriteOperand env op)
  ILoadS16 temp op -> ILoadS16 temp (rewriteOperand env op)
  ILoad8 temp op -> ILoad8 temp (rewriteOperand env op)
  ILoadS8 temp op -> ILoadS8 temp (rewriteOperand env op)
  IStore64 addr value -> IStore64 (rewriteOperand env addr) (rewriteOperand env value)
  IStore32 addr value -> IStore32 (rewriteOperand env addr) (rewriteOperand env value)
  IStore16 addr value -> IStore16 (rewriteOperand env addr) (rewriteOperand env value)
  IStore8 addr value -> IStore8 (rewriteOperand env addr) (rewriteOperand env value)
  IBin temp op a b -> IBin temp op (rewriteOperand env a) (rewriteOperand env b)
  ICall result name args -> ICall result name (map (rewriteOperand env) args)
  ICallIndirect result callee args ->
    ICallIndirect result (rewriteOperand env callee) (map (rewriteOperand env) args)
  _ -> instr

rewriteOperand :: IntMap Operand -> Operand -> Operand
rewriteOperand env op = case op of
  OTemp temp -> case temp of
    Temp key -> case intMapLookup key env of
      Just replacement -> rewriteOperand env replacement
      Nothing -> op
  _ -> op

tempUseCount :: BlockStats -> Temp -> Int
tempUseCount stats temp = case stats of
  BlockStats uses _ _ -> lookupIntDefault 0 temp uses

tempDefCount :: BlockStats -> Temp -> Int
tempDefCount stats temp = case stats of
  BlockStats _ defs _ -> lookupIntDefault 0 temp defs

tempBlocked :: BlockStats -> Temp -> Bool
tempBlocked stats temp = case stats of
  BlockStats _ _ blocked -> lookupIntDefault False temp blocked

lookupIntDefault :: a -> Temp -> IntMap a -> a
lookupIntDefault fallback temp table = case temp of
  Temp key -> case intMapLookup key table of
    Just value -> value
    Nothing -> fallback

countInstrList :: [Instr] -> BlockStats -> BlockStats
countInstrList instrs stats = case instrs of
  [] -> stats
  instr:rest -> countInstrList rest (countInstr instr stats)

countInstr :: Instr -> BlockStats -> BlockStats
countInstr instr stats = case instr of
  IParam temp _ -> countDef temp stats
  IAlloca temp _ -> countDef temp stats
  IConst temp _ -> countDef temp stats
  IConstBytes temp _ -> countDef temp stats
  ICopy temp op -> countDef temp (countOperand op stats)
  IAddrOf temp source -> countDef temp (countUse source (countBlocked source stats))
  ILoad64 temp op -> countDef temp (countOperand op stats)
  ILoad32 temp op -> countDef temp (countOperand op stats)
  ILoadS32 temp op -> countDef temp (countOperand op stats)
  ILoad16 temp op -> countDef temp (countOperand op stats)
  ILoadS16 temp op -> countDef temp (countOperand op stats)
  ILoad8 temp op -> countDef temp (countOperand op stats)
  ILoadS8 temp op -> countDef temp (countOperand op stats)
  IStore64 addr value -> countOperand value (countOperand addr stats)
  IStore32 addr value -> countOperand value (countOperand addr stats)
  IStore16 addr value -> countOperand value (countOperand addr stats)
  IStore8 addr value -> countOperand value (countOperand addr stats)
  IBin temp _ a b -> countDef temp (countOperand b (countOperand a stats))
  ICond temp condInstrs condOp trueInstrs trueOp falseInstrs falseOp ->
    countDef temp
      (countOperand falseOp
      (countInstrList falseInstrs
      (countOperand trueOp
      (countInstrList trueInstrs
      (countOperand condOp
      (countInstrList condInstrs stats))))))
  ICall result _ args -> countMaybeDef result (countOperands args stats)
  ICallIndirect result callee args -> countMaybeDef result (countOperands args (countOperand callee stats))

countTerminator :: Terminator -> BlockStats -> BlockStats
countTerminator term stats = case term of
  TRet Nothing -> stats
  TRet (Just op) -> countOperand op stats
  TJump _ -> stats
  TBranch op _ _ -> countOperand op stats

countOperands :: [Operand] -> BlockStats -> BlockStats
countOperands ops stats = case ops of
  [] -> stats
  op:rest -> countOperands rest (countOperand op stats)

countOperand :: Operand -> BlockStats -> BlockStats
countOperand op stats = case op of
  OTemp temp -> countUse temp stats
  _ -> stats

countMaybeDef :: Maybe Temp -> BlockStats -> BlockStats
countMaybeDef mtemp stats = case mtemp of
  Nothing -> stats
  Just temp -> countDef temp stats

countUse :: Temp -> BlockStats -> BlockStats
countUse temp stats = case stats of
  BlockStats uses defs blocked -> case temp of
    Temp key -> BlockStats (incrementInt key uses) defs blocked

countDef :: Temp -> BlockStats -> BlockStats
countDef temp stats = case stats of
  BlockStats uses defs blocked -> case temp of
    Temp key -> BlockStats uses (incrementInt key defs) blocked

countBlocked :: Temp -> BlockStats -> BlockStats
countBlocked temp stats = case stats of
  BlockStats uses defs blocked -> case temp of
    Temp key -> BlockStats uses defs (intMapInsert key True blocked)

incrementInt :: Int -> IntMap Int -> IntMap Int
incrementInt key table = case intMapLookup key table of
  Nothing -> intMapInsert key 1 table
  Just value -> intMapInsert key (value + 1) table

blockNestedCondTemps :: [Instr] -> BlockStats -> BlockStats
blockNestedCondTemps instrs stats = case instrs of
  [] -> stats
  instr:rest -> blockNestedCondTemps rest (blockNestedCondTempsInstr instr stats)

blockNestedCondTempsInstr :: Instr -> BlockStats -> BlockStats
blockNestedCondTempsInstr instr stats = case instr of
  ICond _ condInstrs condOp trueInstrs trueOp falseInstrs falseOp ->
    blockOperand falseOp
      (blockInstrTemps falseInstrs
      (blockOperand trueOp
      (blockInstrTemps trueInstrs
      (blockOperand condOp
      (blockInstrTemps condInstrs stats)))))
  _ -> stats

blockInstrTemps :: [Instr] -> BlockStats -> BlockStats
blockInstrTemps instrs stats = case instrs of
  [] -> stats
  instr:rest -> blockInstrTemps rest (blockInstrTempsOne instr stats)

blockInstrTempsOne :: Instr -> BlockStats -> BlockStats
blockInstrTempsOne instr stats = case instr of
  IParam temp _ -> countBlocked temp stats
  IAlloca temp _ -> countBlocked temp stats
  IConst temp _ -> countBlocked temp stats
  IConstBytes temp _ -> countBlocked temp stats
  ICopy temp op -> countBlocked temp (blockOperand op stats)
  IAddrOf temp source -> countBlocked temp (countBlocked source stats)
  ILoad64 temp op -> countBlocked temp (blockOperand op stats)
  ILoad32 temp op -> countBlocked temp (blockOperand op stats)
  ILoadS32 temp op -> countBlocked temp (blockOperand op stats)
  ILoad16 temp op -> countBlocked temp (blockOperand op stats)
  ILoadS16 temp op -> countBlocked temp (blockOperand op stats)
  ILoad8 temp op -> countBlocked temp (blockOperand op stats)
  ILoadS8 temp op -> countBlocked temp (blockOperand op stats)
  IStore64 addr value -> blockOperand value (blockOperand addr stats)
  IStore32 addr value -> blockOperand value (blockOperand addr stats)
  IStore16 addr value -> blockOperand value (blockOperand addr stats)
  IStore8 addr value -> blockOperand value (blockOperand addr stats)
  IBin temp _ a b -> countBlocked temp (blockOperand b (blockOperand a stats))
  ICond temp condInstrs condOp trueInstrs trueOp falseInstrs falseOp ->
    countBlocked temp
      (blockOperand falseOp
      (blockInstrTemps falseInstrs
      (blockOperand trueOp
      (blockInstrTemps trueInstrs
      (blockOperand condOp
      (blockInstrTemps condInstrs stats))))))
  ICall result _ args -> blockMaybe result (blockOperands args stats)
  ICallIndirect result callee args -> blockMaybe result (blockOperands args (blockOperand callee stats))

blockOperands :: [Operand] -> BlockStats -> BlockStats
blockOperands ops stats = case ops of
  [] -> stats
  op:rest -> blockOperands rest (blockOperand op stats)

blockOperand :: Operand -> BlockStats -> BlockStats
blockOperand op stats = case op of
  OTemp temp -> countBlocked temp stats
  _ -> stats

blockMaybe :: Maybe Temp -> BlockStats -> BlockStats
blockMaybe mtemp stats = case mtemp of
  Nothing -> stats
  Just temp -> countBlocked temp stats

blockTerminatorTemps :: Terminator -> BlockStats -> BlockStats
blockTerminatorTemps term stats = case term of
  TRet Nothing -> stats
  TRet (Just op) -> blockOperand op stats
  TJump _ -> stats
  TBranch op _ _ -> blockOperand op stats

withCodegenContext :: String -> Either CodegenError a -> Either CodegenError a
withCodegenContext context result = case result of
  Left (CodegenError msg) -> Left (CodegenError (context ++ ": " ++ msg))
  Right value -> Right value

prologue :: Int -> [String]
prologue slots =
  if slots == 0 then [] else ["  HCC_SUB_IMMEDIATE_from_rsp %" ++ show (slots * 8)]

codegenBlocks :: String -> Allocation -> Int -> [BasicBlock] -> Either CodegenError Lines
codegenBlocks fnName alloc totalSlots blocks = case blocks of
  [] -> pure id
  BasicBlock bid instrs term:rest -> do
    body <- codegenInstrs fnName alloc totalSlots instrs
    termCode <- codegenTerminator fnName alloc totalSlots (nextBlockId rest) term
    tailCode <- codegenBlocks fnName alloc totalSlots rest
    pure (linesFromList (blockLabel fnName bid) . body . linesFromList termCode . tailCode)

nextBlockId :: [BasicBlock] -> Maybe BlockId
nextBlockId blocks = case blocks of
  [] -> Nothing
  BasicBlock bid _ _: _ -> Just bid

blockLabel :: String -> BlockId -> [String]
blockLabel _ (BlockId 0) = []
blockLabel fnName (BlockId n) = [":" ++ blockRef fnName (BlockId n)]

codegenInstrs :: String -> Allocation -> Int -> [Instr] -> Either CodegenError Lines
codegenInstrs fnName alloc totalSlots instrs = case instrs of
  [] -> pure id
  instr:rest -> do
    code <- codegenInstr fnName alloc totalSlots instr
    tailCode <- codegenInstrs fnName alloc totalSlots rest
    pure (linesFromList code . tailCode)

codegenInstr :: String -> Allocation -> Int -> Instr -> Either CodegenError [String]
codegenInstr fnName alloc totalSlots instr = case instr of
  IParam temp index -> do
    code <- loadParam totalSlots index
    storeTemp alloc temp code
  IAlloca _ _ ->
    pure []
  IConst temp value ->
    storeTemp alloc temp (loadImmediate value)
  IConstBytes temp bytes ->
    storeTemp alloc temp (loadImmediateBytes bytes)
  ICopy temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp code
  IAddrOf temp source -> do
    sourceLoc <- mapAllocError (lookupLocation source alloc)
    code <- addressOfLocation sourceLoc
    storeTemp alloc temp code
  ILoad64 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["  HCC_LOAD_INTEGER"])
  ILoad32 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["  HCC_LOAD_WORD"])
  ILoadS32 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["  HCC_LOAD_SIGNED_WORD"])
  ILoad16 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["  HCC_LOAD_HALF"])
  ILoadS16 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["  HCC_LOAD_SIGNED_HALF"])
  ILoad8 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["  LOAD_BYTE", "  MOVEZX"])
  ILoadS8 temp op -> do
    code <- loadOperand alloc op
    storeTemp alloc temp (code ++ ["  HCC_LOAD_SIGNED_CHAR"])
  IStore64 addr value -> do
    addrCode <- loadOperand alloc addr
    valueCode <- loadOperand alloc value
    pure (addrCode ++ ["  HCC_M_RAX_RBX"] ++ valueCode ++ ["  HCC_STORE_INTEGER"])
  IStore32 addr value -> do
    addrCode <- loadOperand alloc addr
    valueCode <- loadOperand alloc value
    pure (addrCode ++ ["  HCC_M_RAX_RBX"] ++ valueCode ++ ["  HCC_STORE_WORD"])
  IStore16 addr value -> do
    addrCode <- loadOperand alloc addr
    valueCode <- loadOperand alloc value
    pure (addrCode ++ ["  HCC_M_RAX_RBX"] ++ valueCode ++ ["  HCC_STORE_HALF"])
  IStore8 addr value -> do
    addrCode <- loadOperand alloc addr
    valueCode <- loadOperand alloc value
    pure (addrCode ++ ["  HCC_M_RAX_RBX"] ++ valueCode ++ ["  HCC_STORE_CHAR"])
  IBin temp op a b -> do
    acode <- loadOperand alloc a
    bcode <- loadOperand alloc b
    opCode <- binOpCode op
    storeTemp alloc temp (acode ++ ["  HCC_M_RAX_RBX"] ++ bcode ++ opCode)
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
    pure ( condCode [] ++ condLoad ++
           [ "  TEST"
           , "  JUMP_EQ %" ++ elseLabel
           ] ++
           trueCode [] ++ trueStore ++
           [ "  JUMP %" ++ doneLabel
           , ":" ++ elseLabel
           ] ++
           falseCode [] ++ falseStore ++
           [":" ++ doneLabel])
  ICall result name args -> do
    argCode <- loadArguments alloc 0 args
    let callCode = argCode ++ ["  CALL_IMMEDIATE %FUNCTION_" ++ name] ++ cleanupCallStack args
    case result of
      Nothing -> pure callCode
      Just temp -> storeTemp alloc temp callCode
  ICallIndirect result callee args -> do
    argCode <- loadArguments alloc 0 args
    calleeCode <- loadOperandWithRspBias alloc (callStackBytes args) callee
    let callCode = argCode ++ calleeCode ++ ["  HCC_CALL_rax"] ++ cleanupCallStack args
    case result of
      Nothing -> pure callCode
      Just temp -> storeTemp alloc temp callCode

codegenTerminator :: String -> Allocation -> Int -> Maybe BlockId -> Terminator -> Either CodegenError [String]
codegenTerminator fnName alloc totalSlots next term = case term of
  TRet Nothing -> pure (["  LOAD_IMMEDIATE_rax %0"] ++ cleanupStack totalSlots ++ ["  RETURN"])
  TRet (Just op) -> do
    code <- loadOperand alloc op
    pure (code ++ cleanupStack totalSlots ++ ["  RETURN"])
  TJump bid ->
    if sameMaybeBlock next bid
    then pure []
    else pure ["  JUMP %" ++ blockRef fnName bid]
  TBranch op yes no -> do
    code <- loadOperand alloc op
    if sameMaybeBlock next yes
      then pure (code ++ ["  TEST", "  JUMP_EQ %" ++ blockRef fnName no])
      else if sameMaybeBlock next no
        then pure (code ++ ["  TEST", "  JUMP_NE %" ++ blockRef fnName yes])
        else pure (code ++ ["  TEST", "  JUMP_NE %" ++ blockRef fnName yes, "  JUMP %" ++ blockRef fnName no])

sameMaybeBlock :: Maybe BlockId -> BlockId -> Bool
sameMaybeBlock maybeBid bid = case maybeBid of
  Nothing -> False
  Just nextBid -> sameBlock nextBid bid

sameBlock :: BlockId -> BlockId -> Bool
sameBlock a b = case a of
  BlockId x -> case b of
    BlockId y -> x == y

loadArguments :: Allocation -> Int -> [Operand] -> Either CodegenError [String]
loadArguments alloc _ args = do
  stackCode <- pushStackArguments alloc 0 (reverse (drop 6 args))
  registerCode <- loadRegisterArguments alloc (callStackBytes args) 0 (take 6 args)
  pure (stackCode ++ registerCode)

pushStackArguments :: Allocation -> Int -> [Operand] -> Either CodegenError [String]
pushStackArguments alloc pushed args = case args of
  [] -> pure []
  op:rest -> do
    one <- loadOperandWithRspBias alloc (pushed * 8) op
    tailCode <- pushStackArguments alloc (pushed + 1) rest
    pure (one ++ ["  PUSH_RAX"] ++ tailCode)

loadRegisterArguments :: Allocation -> Int -> Int -> [Operand] -> Either CodegenError [String]
loadRegisterArguments alloc rspBias index args = case args of
  [] -> pure []
  op:rest -> do
    code <- loadOperandWithRspBias alloc rspBias op
    move <- argumentMove index
    tailCode <- loadRegisterArguments alloc rspBias (index + 1) rest
    pure (code ++ move ++ tailCode)

cleanupCallStack :: [Operand] -> [String]
cleanupCallStack args =
  let bytes = callStackBytes args
  in if bytes <= 0 then [] else ["  HCC_ADD_IMMEDIATE_to_rsp %" ++ show bytes]

callStackBytes :: [Operand] -> Int
callStackBytes args =
  let stackArgs = length args - 6
  in if stackArgs <= 0 then 0 else stackArgs * 8

argumentMove :: Int -> Either CodegenError [String]
argumentMove index = case index of
  0 -> Right ["  COPY_rax_to_rdi"]
  1 -> Right ["  HCC_COPY_rax_to_rsi"]
  2 -> Right ["  HCC_COPY_rax_to_rdx"]
  3 -> Right ["  HCC_COPY_rax_to_rcx"]
  4 -> Right ["  HCC_COPY_rax_to_r8"]
  5 -> Right ["  HCC_COPY_rax_to_r9"]
  _ -> Left (CodegenError ("unsupported call argument index: " ++ show index))

loadParam :: Int -> Int -> Either CodegenError [String]
loadParam totalSlots index = case index of
  0 -> Right ["  HCC_M_RDI_RAX"]
  1 -> Right ["  HCC_COPY_rsi_to_rax"]
  2 -> Right ["  HCC_COPY_rdx_to_rax"]
  3 -> Right ["  HCC_COPY_rcx_to_rax"]
  4 -> Right ["  HCC_COPY_r8_to_rax"]
  5 -> Right ["  HCC_COPY_r9_to_rax"]
  _ -> Right ["  LOAD_RSP_IMMEDIATE_into_rax %" ++ show (totalSlots * 8 + 8 + (index - 6) * 8)]

binOpCode :: BinOp -> Either CodegenError [String]
binOpCode op = case op of
  IAdd -> Right ["  ADD_rbx_to_rax"]
  ISub -> Right ["  SUBTRACT_rax_from_rbx_into_rbx", "  MOVE_rbx_to_rax"]
  IMul -> Right ["  MULTIPLY_rax_by_rbx_into_rax"]
  IDiv -> Right ["  XCHG_rax_rbx", "  CQTO", "  DIVIDES_rax_by_rbx_into_rax"]
  IMod -> Right ["  XCHG_rax_rbx", "  CQTO", "  MODULUSS_rax_from_rbx_into_rbx", "  MOVE_rdx_to_rax"]
  IShl -> Right ["  COPY_rax_to_rcx", "  MOVE_rbx_to_rax", "  HCC_SHL_rax_cl"]
  IShr -> Right ["  COPY_rax_to_rcx", "  MOVE_rbx_to_rax", "  HCC_SHR_rax_cl"]
  ISar -> Right ["  COPY_rax_to_rcx", "  MOVE_rbx_to_rax", "  HCC_SAR_rax_cl"]
  IEq -> Right ["  CMP", "  SETE", "  MOVEZX"]
  INe -> Right ["  CMP", "  SETNE", "  MOVEZX"]
  ILt -> Right ["  CMP", "  SETL", "  MOVEZX"]
  ILe -> Right ["  CMP", "  SETLE", "  MOVEZX"]
  IGt -> Right ["  CMP", "  SETG", "  MOVEZX"]
  IGe -> Right ["  CMP", "  SETGE", "  MOVEZX"]
  IULt -> Right ["  CMP", "  SETB", "  MOVEZX"]
  IULe -> Right ["  CMP", "  SETBE", "  MOVEZX"]
  IUGt -> Right ["  CMP", "  SETA", "  MOVEZX"]
  IUGe -> Right ["  CMP", "  SETAE", "  MOVEZX"]
  IAnd -> Right ["  AND_rax_rbx"]
  IOr -> Right ["  OR_rax_rbx"]
  IXor -> Right ["  HCC_XOR_rbx_rax_into_rax"]

loadOperand :: Allocation -> Operand -> Either CodegenError [String]
loadOperand alloc = loadOperandWithRspBias alloc 0

loadOperandWithRspBias :: Allocation -> Int -> Operand -> Either CodegenError [String]
loadOperandWithRspBias alloc rspBias op = case op of
  OImm value -> Right (loadImmediate value)
  OImmBytes bytes -> Right (loadImmediateBytes bytes)
  OGlobal name -> Right ["  LOAD_IMMEDIATE_rax &" ++ name]
  OFunction name -> Right ["  LOAD_IMMEDIATE_rax &FUNCTION_" ++ name]
  OTemp temp -> do
    loc <- mapAllocError (lookupLocation temp alloc)
    loadLocationWithRspBias rspBias loc

loadImmediate :: Int -> [String]
loadImmediate value =
  if value == 2147483648
    then ["  HCC_LI64_80000000"]
    else if value == 4294967295
      then ["  HCC_LI64_FFFFFFFF"]
      else if value >= (-2147483648) && value <= 2147483647
        then ["  LOAD_IMMEDIATE_rax %" ++ show value]
        else [textRender (textString "  HCC_LOAD_IMMEDIATE64_rax " `textAppend` byteHexWords (word64Bytes value))]

loadImmediateBytes :: [Int] -> [String]
loadImmediateBytes bytes =
  loadImmediateBytes8 (takeInts 8 (bytes ++ zeroBytes))

loadImmediateBytes8 :: [Int] -> [String]
loadImmediateBytes8 bytes =
  if bytes == [0, 0, 0, 128, 0, 0, 0, 0]
    then ["  HCC_LI64_80000000"]
    else if bytes == [255, 255, 255, 255, 0, 0, 0, 0]
      then ["  HCC_LI64_FFFFFFFF"]
      else [textRender (textString "  HCC_LOAD_IMMEDIATE64_rax " `textAppend` byteHexWords bytes)]

zeroBytes :: [Int]
zeroBytes = 0 : zeroBytes

word64Bytes :: Int -> [Int]
word64Bytes value = map byte ([0..7] :: [Int]) where
  byte shift = (value `div` (256 ^ shift)) `mod` 256

takeInts :: Int -> [Int] -> [Int]
takeInts count values =
  if count <= 0
    then []
    else case values of
      [] -> []
      value:rest -> value : takeInts (count - 1) rest

loadLocationWithRspBias :: Int -> Location -> Either CodegenError [String]
loadLocationWithRspBias rspBias loc = case loc of
  InReg Rax -> Right []
  InReg Rbx -> Right ["  MOVE_rbx_to_rax"]
  InReg Rdi -> Right ["  HCC_M_RDI_RAX"]
  InReg Rsi -> Right ["  HCC_COPY_rsi_to_rax"]
  InReg Rdx -> Right ["  HCC_COPY_rdx_to_rax"]
  OnStack slot -> Right ["  LOAD_RSP_IMMEDIATE_into_rax %" ++ show (8 * slot + rspBias)]
  StackObject slot _ -> Right ["  HCC_LOAD_EFFECTIVE_ADDRESS_rax %" ++ show (8 * slot + rspBias)]

addressOfLocation :: Location -> Either CodegenError [String]
addressOfLocation loc = case loc of
    OnStack slot -> Right ["  HCC_LOAD_EFFECTIVE_ADDRESS_rax %" ++ show (8 * slot)]
    StackObject slot _ -> Right ["  HCC_LOAD_EFFECTIVE_ADDRESS_rax %" ++ show (8 * slot)]
    InReg _ -> Left (CodegenError "cannot take address of register-allocated value")

storeTemp :: Allocation -> Temp -> [String] -> Either CodegenError [String]
storeTemp alloc temp code = do
  loc <- mapAllocError (lookupLocation temp alloc)
  case loc of
    OnStack slot -> Right (code ++ ["  HCC_STORE_RSP_IMMEDIATE_from_rax %" ++ show (8 * slot)])
    StackObject _ _ -> Left (CodegenError ("cannot assign to stack object address: " ++ renderTemp temp))
    InReg _ -> Right code

cleanupStack :: Int -> [String]
cleanupStack slots =
  if slots == 0 then [] else ["  HCC_ADD_IMMEDIATE_to_rsp %" ++ show (slots * 8)]

blockRef :: String -> BlockId -> String
blockRef fnName (BlockId n) = "HCC_BLOCK_" ++ fnName ++ "_" ++ show n

codegenDataItem :: DataItem -> [String]
codegenDataItem (DataItem label values) =
  [":" ++ label, "  " ++ joinWords (map dataValueM1 values), ""]

codegenDataItemWrite :: ([String] -> IO ()) -> DataItem -> IO ()
codegenDataItemWrite write (DataItem label values) = do
  write [":" ++ label]
  codegenDataValuesWrite write 0 textEmpty values
  write [""]

codegenDataValuesWrite :: ([String] -> IO ()) -> Int -> TextBuilder -> [DataValue] -> IO ()
codegenDataValuesWrite write count chunk values = case values of
  [] -> codegenDataChunkWrite write chunk
  value:rest ->
    if count >= 16
      then do
        codegenDataChunkWrite write chunk
        codegenDataValuesWrite write 0 textEmpty values
      else codegenDataValuesWrite write (count + 1) (appendDataValue count chunk value) rest

appendDataValue :: Int -> TextBuilder -> DataValue -> TextBuilder
appendDataValue count chunk value =
  let sep = if count == 0 then textEmpty else textChar ' '
  in chunk `textAppend` sep `textAppend` dataValueM1Text value

codegenDataChunkWrite :: ([String] -> IO ()) -> TextBuilder -> IO ()
codegenDataChunkWrite write chunk = case chunk of
  TextBuilder len _ ->
    if len == 0
    then pure ()
    else write [textRender (textString "  " `textAppend` chunk)]

dataValueM1 :: DataValue -> String
dataValueM1 value = case value of
  DByte byte -> textRender (byteHexText byte)
  DAddress label -> "&" ++ label ++ " '00' '00' '00' '00'"

dataValueM1Text :: DataValue -> TextBuilder
dataValueM1Text value = case value of
  DByte byte -> byteHexText byte
  DAddress label -> textString ("&" ++ label ++ " '00' '00' '00' '00'")

byteHex :: Int -> String
byteHex value = textRender (byteHexText value)

byteHexText :: Int -> TextBuilder
byteHexText value =
  TextBuilder 4 (\rest -> '\'' : high : low : '\'' : rest)
  where
    digits = "0123456789ABCDEF"
    b = value `mod` 256
    high = digits !! (b `div` 16)
    low = digits !! (b `mod` 16)

byteHexWords :: [Int] -> TextBuilder
byteHexWords values = textIntercalate (textChar ' ') (map byteHexText values)

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
renderLines builder = renderLineList (builder [])

renderLineList :: [String] -> String
renderLineList lines' = go lines' "" where
  go :: [String] -> String -> String
  go ls = case ls of
    [] -> id
    text:rest -> (text++) . ('\n':) . go rest

mapCompileError :: Either CompileError a -> Either CodegenError a
mapCompileError result = case result of
  Left (CompileError msg) -> Left (CodegenError msg)
  Right x -> Right x

mapCompileRun :: Either CompileError a -> Either CodegenError a
mapCompileRun = mapCompileError

mapAllocError :: Either String a -> Either CodegenError a
mapAllocError result = case result of
  Left msg -> Left (CodegenError msg)
  Right x -> Right x
