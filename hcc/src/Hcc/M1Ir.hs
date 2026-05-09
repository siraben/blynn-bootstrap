module M1Ir where

import Base
import TypesAst
import CompileM
import IntTable
import TypesIr
import Lower
import LowerBootstrap
import LowerImplicit

data CodegenError = CodegenError String

emitM1IrWithDataPrefix :: ([String] -> IO ()) -> String -> Program -> IO (Either CodegenError ())
emitM1IrWithDataPrefix write prefix ast = case ast of
  Program decls ->
    case mapCompileRun (unCompileM registerBuiltinStructs initialCompileState { csDataPrefix = prefix }) of
      Left err -> pure (Left err)
      Right (_, st0) -> do
        write ["HCCM1IR 1"]
        registered <- registerTopDeclsIr write st0 decls
        case registered of
          Left err -> pure (Left err)
          Right st -> emitTopDeclsIr write st decls

emitTopDeclsIr :: ([String] -> IO ()) -> CompileState -> [TopDecl] -> IO (Either CodegenError ())
emitTopDeclsIr write st decls = case decls of
  [] -> pure (Right ())
  Function _ name params body:rest ->
    case mapCompileRun (unCompileM (registerImplicitCalls (paramDeclNamesIr params) body >> lowerFunction name params body) st) of
      Left err -> pure (Left err)
      Right (fn, st') -> do
        emitFunction write (optimizeFunctionIr fn)
        st'' <- flushPendingDataItemsIr write st'
        emitTopDeclsIr write st'' rest
  _:rest -> emitTopDeclsIr write st rest

registerTopDeclsIr :: ([String] -> IO ()) -> CompileState -> [TopDecl] -> IO (Either CodegenError CompileState)
registerTopDeclsIr write st decls = case decls of
  [] -> pure (Right st)
  decl:rest -> do
    result <- registerTopDeclIr write st decl
    case mapCompileRun result of
      Left err -> pure (Left err)
      Right (_, st') -> registerTopDeclsIr write st' rest

registerTopDeclIr :: ([String] -> IO ()) -> CompileState -> TopDecl -> IO (Either CompileError ((), CompileState))
registerTopDeclIr write st decl = case decl of
  Global ty name initExpr ->
    case unCompileM (registerTypeAggregates ty >> bindGlobal name ty >> globalData ty initExpr) st of
      Left err -> pure (Left err)
      Right (values, st') -> do
        emitDataItem write (DataItem name values)
        st'' <- flushPendingDataItemsIr write st'
        pure (Right ((), st''))
  Globals globals ->
    registerGlobalsIr write st globals
  _ -> pure (registerTopDeclShallowState st decl)

registerTopDeclShallowState :: CompileState -> TopDecl -> Either CompileError ((), CompileState)
registerTopDeclShallowState st decl = case decl of
  Function ty name _ _ ->
    unCompileM (registerTypeAggregates ty >> bindGlobal name ty >> bindFunction name) st
  Prototype ty name _ ->
    unCompileM (registerTypeAggregates ty >> bindGlobal name ty >> bindFunction name) st
  StructDecl isUnion name fields ->
    unCompileM (registerFieldAggregates fields >> bindStruct name isUnion fields) st
  ExternGlobals globals ->
    unCompileM (registerExternGlobals globals) st
  EnumConstants constants ->
    unCompileM (registerConstants constants) st
  _ -> Right ((), st)

registerGlobalsIr :: ([String] -> IO ()) -> CompileState -> [(CType, String, Maybe Expr)] -> IO (Either CompileError ((), CompileState))
registerGlobalsIr write st globals = case globals of
  [] -> pure (Right ((), st))
  (ty, name, initExpr):rest ->
    case unCompileM (registerTypeAggregates ty >> bindGlobal name ty >> globalData ty initExpr) st of
      Left err -> pure (Left err)
      Right (values, st') -> do
        emitDataItem write (DataItem name values)
        st'' <- flushPendingDataItemsIr write st'
        registerGlobalsIr write st'' rest

flushPendingDataItemsIr :: ([String] -> IO ()) -> CompileState -> IO CompileState
flushPendingDataItemsIr write st = case csDataItems st of
  [] -> pure st
  items -> do
    emitDataItems write (reverse items)
    pure st { csDataItems = [] }

paramDeclNamesIr :: [Param] -> [String]
paramDeclNamesIr params = case params of
  [] -> []
  Param _ name:rest -> name : paramDeclNamesIr rest

emitDataItems :: ([String] -> IO ()) -> [DataItem] -> IO ()
emitDataItems write items = case items of
  [] -> pure ()
  item:rest -> do
    emitDataItem write item
    emitDataItems write rest

emitDataItem :: ([String] -> IO ()) -> DataItem -> IO ()
emitDataItem write item = case item of
  DataItem label values -> do
    write ["DATA " ++ label]
    emitDataValues write values
    write ["ENDDATA"]

emitDataValues :: ([String] -> IO ()) -> [DataValue] -> IO ()
emitDataValues write values = case values of
  [] -> pure ()
  value:rest -> do
    write [dataValueLine value]
    emitDataValues write rest

dataValueLine :: DataValue -> String
dataValueLine value = case value of
  DByte byte -> "DV B " ++ show byte
  DAddress label -> "DV A " ++ label

emitFunction :: ([String] -> IO ()) -> FunctionIr -> IO ()
emitFunction write fn = case fn of
  FunctionIr name _ blocks -> do
    write ["FUNC " ++ name]
    emitBlocks write blocks
    write ["ENDFUNC"]

emitBlocks :: ([String] -> IO ()) -> [BasicBlock] -> IO ()
emitBlocks write blocks = case blocks of
  [] -> pure ()
  block:rest -> do
    emitBlock write block
    emitBlocks write rest

emitBlock :: ([String] -> IO ()) -> BasicBlock -> IO ()
emitBlock write block = case block of
  BasicBlock bid instrs term -> do
    write ["BLOCK " ++ blockIdText bid]
    emitInstrs write instrs
    write [terminatorLine term]

emitInstrs :: ([String] -> IO ()) -> [Instr] -> IO ()
emitInstrs write instrs = case instrs of
  [] -> pure ()
  instr:rest -> do
    emitInstr write instr
    emitInstrs write rest

emitInstr :: ([String] -> IO ()) -> Instr -> IO ()
emitInstr write instr = case instr of
  IParam temp index -> write ["I PARAM " ++ tempText temp ++ " " ++ show index]
  IAlloca temp size -> write ["I ALLOCA " ++ tempText temp ++ " " ++ show size]
  IConst temp value -> write ["I CONST " ++ tempText temp ++ " " ++ show value]
  IConstBytes temp bytes -> write ["I CONSTB " ++ tempText temp ++ " B " ++ intListFields bytes]
  ICopy temp op -> write ["I COPY " ++ tempText temp ++ " " ++ operandFields op]
  IAddrOf temp source -> write ["I ADDROF " ++ tempText temp ++ " " ++ tempText source]
  ILoad64 temp op -> write ["I LOAD64 " ++ tempText temp ++ " " ++ operandFields op]
  ILoad32 temp op -> write ["I LOAD32 " ++ tempText temp ++ " " ++ operandFields op]
  ILoadS32 temp op -> write ["I LOADS32 " ++ tempText temp ++ " " ++ operandFields op]
  ILoad16 temp op -> write ["I LOAD16 " ++ tempText temp ++ " " ++ operandFields op]
  ILoadS16 temp op -> write ["I LOADS16 " ++ tempText temp ++ " " ++ operandFields op]
  ILoad8 temp op -> write ["I LOAD8 " ++ tempText temp ++ " " ++ operandFields op]
  ILoadS8 temp op -> write ["I LOADS8 " ++ tempText temp ++ " " ++ operandFields op]
  IStore64 addr value -> write ["I STORE64 " ++ operandFields addr ++ " " ++ operandFields value]
  IStore32 addr value -> write ["I STORE32 " ++ operandFields addr ++ " " ++ operandFields value]
  IStore16 addr value -> write ["I STORE16 " ++ operandFields addr ++ " " ++ operandFields value]
  IStore8 addr value -> write ["I STORE8 " ++ operandFields addr ++ " " ++ operandFields value]
  IBin temp op left right -> write ["I BIN " ++ tempText temp ++ " " ++ binOpText op ++ " " ++ operandFields left ++ " " ++ operandFields right]
  ICall result name args -> write ["I CALL " ++ maybeTempText result ++ " " ++ name ++ " " ++ operandsFields args]
  ICallIndirect result callee args -> write ["I CALLI " ++ maybeTempText result ++ " " ++ operandFields callee ++ " " ++ operandsFields args]
  ICond temp condInstrs condOp trueInstrs trueOp falseInstrs falseOp -> do
    write ["I COND " ++ tempText temp]
    write ["BEGIN"]
    emitInstrs write condInstrs
    write ["END"]
    write ["CONDOP " ++ operandFields condOp]
    write ["BEGIN"]
    emitInstrs write trueInstrs
    write ["END"]
    write ["TRUEOP " ++ operandFields trueOp]
    write ["BEGIN"]
    emitInstrs write falseInstrs
    write ["END"]
    write ["FALSEOP " ++ operandFields falseOp]
    write ["ENDCOND"]

terminatorLine :: Terminator -> String
terminatorLine term = case term of
  TRet Nothing -> "TERM RET N"
  TRet (Just op) -> "TERM RET Y " ++ operandFields op
  TJump bid -> "TERM JUMP " ++ blockIdText bid
  TBranch op yes no -> "TERM BRANCH " ++ operandFields op ++ " " ++ blockIdText yes ++ " " ++ blockIdText no

operandsFields :: [Operand] -> String
operandsFields ops = show (length ops) ++ operandsFieldsRest ops

operandsFieldsRest :: [Operand] -> String
operandsFieldsRest ops = case ops of
  [] -> ""
  op:rest -> " " ++ operandFields op ++ operandsFieldsRest rest

operandFields :: Operand -> String
operandFields op = case op of
  OTemp temp -> "T " ++ tempText temp
  OImm value -> "I " ++ show value
  OImmBytes bytes -> "B " ++ intListFields bytes
  OGlobal name -> "G " ++ name
  OFunction name -> "F " ++ name

intListFields :: [Int] -> String
intListFields values = show (length values) ++ intListFieldsRest values

intListFieldsRest :: [Int] -> String
intListFieldsRest values = case values of
  [] -> ""
  value:rest -> " " ++ show value ++ intListFieldsRest rest

maybeTempText :: Maybe Temp -> String
maybeTempText maybeTemp = case maybeTemp of
  Nothing -> "-"
  Just temp -> tempText temp

tempText :: Temp -> String
tempText temp = case temp of
  Temp n -> show n

blockIdText :: BlockId -> String
blockIdText bid = case bid of
  BlockId n -> show n

binOpText :: BinOp -> String
binOpText op = case op of
  IAdd -> "ADD"
  ISub -> "SUB"
  IMul -> "MUL"
  IDiv -> "DIV"
  IMod -> "MOD"
  IShl -> "SHL"
  IShr -> "SHR"
  ISar -> "SAR"
  IEq -> "EQ"
  INe -> "NE"
  ILt -> "LT"
  ILe -> "LE"
  IGt -> "GT"
  IGe -> "GE"
  IULt -> "ULT"
  IULe -> "ULE"
  IUGt -> "UGT"
  IUGe -> "UGE"
  IAnd -> "AND"
  IOr -> "OR"
  IXor -> "XOR"

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
  IAdd -> if isZeroOperand a then ICopy temp b else if isZeroOperand b then ICopy temp a else IBin temp op a b
  ISub -> if isZeroOperand b || sameOperand a b then if sameOperand a b then IConst temp 0 else ICopy temp a else IBin temp op a b
  IMul -> if isZeroOperand a || isZeroOperand b then IConst temp 0 else if isOneOperand a then ICopy temp b else if isOneOperand b then ICopy temp a else IBin temp op a b
  IDiv -> if isOneOperand b then ICopy temp a else IBin temp op a b
  IMod -> if isOneOperand b || sameOperand a b then IConst temp 0 else IBin temp op a b
  IShl -> if isZeroOperand b then ICopy temp a else IBin temp op a b
  IShr -> if isZeroOperand b then ICopy temp a else IBin temp op a b
  ISar -> if isZeroOperand b then ICopy temp a else IBin temp op a b
  IEq -> if sameOperand a b then IConst temp 1 else IBin temp op a b
  INe -> if sameOperand a b then IConst temp 0 else IBin temp op a b
  ILt -> if sameOperand a b then IConst temp 0 else IBin temp op a b
  ILe -> if sameOperand a b then IConst temp 1 else IBin temp op a b
  IGt -> if sameOperand a b then IConst temp 0 else IBin temp op a b
  IGe -> if sameOperand a b then IConst temp 1 else IBin temp op a b
  IULt -> if sameOperand a b then IConst temp 0 else IBin temp op a b
  IULe -> if sameOperand a b then IConst temp 1 else IBin temp op a b
  IUGt -> if sameOperand a b then IConst temp 0 else IBin temp op a b
  IUGe -> if sameOperand a b then IConst temp 1 else IBin temp op a b
  IAnd -> if isZeroOperand a || isZeroOperand b then IConst temp 0 else if sameOperand a b then ICopy temp a else IBin temp op a b
  IOr -> if isZeroOperand a then ICopy temp b else if isZeroOperand b || sameOperand a b then ICopy temp a else IBin temp op a b
  IXor -> if isZeroOperand a then ICopy temp b else if isZeroOperand b then ICopy temp a else if sameOperand a b then IConst temp 0 else IBin temp op a b

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
      in BasicBlock bid optimized term

containsCondInstr :: [Instr] -> Bool
containsCondInstr instrs = case instrs of
  [] -> False
  ICond _ _ _ _ _ _ _: _ -> True
  _:rest -> containsCondInstr rest

data BlockStats = BlockStats (IntMap Int) (IntMap Int) (IntMap Bool)

functionStats :: [BasicBlock] -> BlockStats
functionStats blocks =
  functionStatsFrom blocks (BlockStats intMapEmpty intMapEmpty intMapEmpty)

functionStatsFrom :: [BasicBlock] -> BlockStats -> BlockStats
functionStatsFrom blocks stats = case blocks of
  [] -> stats
  BasicBlock _ instrs term:rest ->
    functionStatsFrom rest (countTerminator term (countInstrList instrs stats))

blockStats :: [Instr] -> Terminator -> BlockStats
blockStats instrs term =
  let emptyStats = BlockStats intMapEmpty intMapEmpty intMapEmpty
      instrStats = countInstrList instrs emptyStats
      termStats = countTerminator term instrStats
  in blockTerminatorTemps term (blockNestedCondTemps instrs termStats)

optimizeInstrs :: BlockStats -> BlockStats -> IntMap Operand -> [Instr] -> [Instr]
optimizeInstrs globalStats localStats env instrs = case instrs of
  [] -> []
  instr:rest ->
    if pureForwardable globalStats localStats instr
    then case pureForwardValue instr of
      Just (Temp key, op) -> optimizeInstrs globalStats localStats (intMapInsert key (rewriteOperand env op) env) rest
      Nothing -> optimizeInstrs globalStats localStats env rest
    else rewriteInstr env instr : optimizeInstrs globalStats localStats env rest

pureForwardable :: BlockStats -> BlockStats -> Instr -> Bool
pureForwardable globalStats localStats instr = case pureForwardValue instr of
  Nothing -> False
  Just (temp, _) ->
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
  ICallIndirect result callee args -> ICallIndirect result (rewriteOperand env callee) (map (rewriteOperand env) args)
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
  BlockStats uses _ _ -> lookupTempInt 0 temp uses

tempDefCount :: BlockStats -> Temp -> Int
tempDefCount stats temp = case stats of
  BlockStats _ defs _ -> lookupTempInt 0 temp defs

tempBlocked :: BlockStats -> Temp -> Bool
tempBlocked stats temp = case stats of
  BlockStats _ _ blocked -> lookupTempBool False temp blocked

lookupTempBool :: Bool -> Temp -> IntMap Bool -> Bool
lookupTempBool fallback temp table = case temp of
  Temp key -> lookupIntDefault fallback key table

lookupTempInt :: Int -> Temp -> IntMap Int -> Int
lookupTempInt fallback temp table = case temp of
  Temp key -> lookupIntDefault fallback key table

lookupIntDefault :: a -> Int -> IntMap a -> a
lookupIntDefault fallback key table = case intMapLookup key table of
  Just value -> value
  Nothing -> fallback

incrementInt :: Int -> IntMap Int -> IntMap Int
incrementInt key table = case intMapLookup key table of
  Nothing -> intMapInsert key 1 table
  Just value -> intMapInsert key (value + 1) table

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

mapCompileRun :: Either CompileError a -> Either CodegenError a
mapCompileRun result = case result of
  Left (CompileError msg) -> Left (CodegenError msg)
  Right value -> Right value
