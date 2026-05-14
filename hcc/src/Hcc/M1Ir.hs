module M1Ir
  ( CodegenError(..)
  , emitM1IrWithDataPrefixTarget
  ) where

import Base
import TypesAst
import CompileM
import IntTable
import TypesIr
import Lower
import LowerBootstrap
import LowerImplicit

data CodegenError = CodegenError String

emitM1IrWithDataPrefixTarget :: (String -> IO ()) -> String -> Int -> Program -> IO (Either CodegenError ())
emitM1IrWithDataPrefixTarget write prefix target ast =
  case buildM1IrModuleWithDataPrefixTarget prefix target ast of
    Left err -> pure (Left err)
    Right ir -> do
      write "HCCIR 1"
      emitModuleIr write (optimizeModuleIr ir)
      pure (Right ())

buildM1IrModuleWithDataPrefixTarget :: String -> Int -> Program -> Either CodegenError ModuleIr
buildM1IrModuleWithDataPrefixTarget prefix target ast = case ast of
  Program decls ->
    case mapCompileRun (unCompileM registerBuiltinStructs (initialCompileStateForTarget prefix target)) of
      Left err -> Left err
      Right (_, st0) ->
        case registerTopDeclsIr st0 decls of
          Left err -> Left err
          Right (st, registeredItems) ->
            case lowerTopDeclsIr st decls of
              Left err -> Left err
              Right (_, functionItems) -> Right (ModuleIr (registeredItems ++ functionItems))

lowerTopDeclsIr :: CompileState -> [TopDecl] -> Either CodegenError (CompileState, [TopItemIr])
lowerTopDeclsIr st decls = case decls of
  [] -> Right (st, [])
  Function _ name params body:rest ->
    case mapCompileRun (unCompileM (registerImplicitCalls (paramDeclNamesIr params) body >> lowerFunction name params body) st) of
      Left err -> Left err
      Right (fn, st') ->
        case pendingDataItemsIr st' of
          (pending, st'') ->
            case lowerTopDeclsIr st'' rest of
              Left err -> Left err
              Right (stFinal, restItems) -> Right (stFinal, TopFunction fn : pending ++ restItems)
  _:rest -> lowerTopDeclsIr st rest

registerTopDeclsIr :: CompileState -> [TopDecl] -> Either CodegenError (CompileState, [TopItemIr])
registerTopDeclsIr st decls = case decls of
  [] -> Right (st, [])
  decl:rest ->
    case registerTopDeclIr st decl of
      Left err -> Left err
      Right (st', items) ->
        case registerTopDeclsIr st' rest of
          Left err -> Left err
          Right (st'', restItems) -> Right (st'', items ++ restItems)

registerTopDeclIr :: CompileState -> TopDecl -> Either CodegenError (CompileState, [TopItemIr])
registerTopDeclIr st decl = case decl of
  Global ty name initExpr ->
    case mapCompileRun (unCompileM (registerTypeAggregates ty >> bindGlobal name ty >> globalData ty initExpr) st) of
      Left err -> Left err
      Right (values, st') -> do
        case pendingDataItemsIr st' of
          (pending, st'') -> Right (st'', TopData (DataItem name values) : pending)
  Globals globals ->
    registerGlobalsIr st globals
  _ ->
    case mapCompileRun (registerTopDeclShallowState st decl) of
      Left err -> Left err
      Right (_, st') -> Right (st', [])

registerTopDeclShallowState :: CompileState -> TopDecl -> Either CompileError ((), CompileState)
registerTopDeclShallowState st decl = case decl of
  Function ty name params _ ->
    unCompileM (registerFunctionDecl ty name params) st
  Prototype ty name params ->
    unCompileM (registerFunctionDecl ty name params) st
  StructDecl isUnion name fields ->
    unCompileM (registerFieldAggregates fields >> bindStruct name isUnion fields) st
  ExternGlobals globals ->
    unCompileM (registerExternGlobals globals) st
  EnumConstants constants ->
    unCompileM (registerConstants constants) st
  TypeDecl types ->
    unCompileM (registerTypesAggregates types) st
  _ -> Right ((), st)

registerFunctionDecl :: CType -> String -> [Param] -> CompileM ()
registerFunctionDecl ty name params = do
  registerTypeAggregates ty
  registerTypesAggregates (paramTypes params)
  bindGlobal name ty
  bindFunctionType name ty params

registerGlobalsIr :: CompileState -> [(CType, String, Maybe Expr)] -> Either CodegenError (CompileState, [TopItemIr])
registerGlobalsIr st globals = case globals of
  [] -> Right (st, [])
  (ty, name, initExpr):rest ->
    case mapCompileRun (unCompileM (registerTypeAggregates ty >> bindGlobal name ty >> globalData ty initExpr) st) of
      Left err -> Left err
      Right (values, st') ->
        case pendingDataItemsIr st' of
          (pending, st'') ->
            case registerGlobalsIr st'' rest of
              Left err -> Left err
              Right (stFinal, restItems) -> Right (stFinal, TopData (DataItem name values) : pending ++ restItems)

pendingDataItemsIr :: CompileState -> ([TopItemIr], CompileState)
pendingDataItemsIr st = case csDataItems st of
  [] -> ([], st)
  items -> (map TopData (reverse items), st { csDataItems = [] })

paramDeclNamesIr :: [Param] -> [String]
paramDeclNamesIr params = case params of
  [] -> []
  Param _ name:rest -> name : paramDeclNamesIr rest

emitModuleIr :: (String -> IO ()) -> ModuleIr -> IO ()
emitModuleIr write ir = case ir of
  ModuleIr items -> emitTopItemsIr write items

emitTopItemsIr :: (String -> IO ()) -> [TopItemIr] -> IO ()
emitTopItemsIr write items = case items of
  [] -> pure ()
  item:rest -> do
    emitTopItemIr write item
    emitTopItemsIr write rest

emitTopItemIr :: (String -> IO ()) -> TopItemIr -> IO ()
emitTopItemIr write item = case item of
  TopData dataItem -> emitDataItemIr write dataItem
  TopFunction fn -> emitFunctionIr write fn

emitDataItemIr :: (String -> IO ()) -> DataItem -> IO ()
emitDataItemIr write item = case item of
  DataItem label values -> do
    write ("D " ++ label)
    emitDataValuesIr write values
    write "E"

emitDataValuesIr :: (String -> IO ()) -> [DataValue] -> IO ()
emitDataValuesIr write values = case values of
  [] -> pure ()
  DByte 0:_ ->
    case zeroRun values of
      (count, rest) -> do
        write ("z " ++ show count)
        emitDataValuesIr write rest
  value:rest -> do
    write (dataValueIrLine value)
    emitDataValuesIr write rest

dataValueIrLine :: DataValue -> String
dataValueIrLine value = case value of
  DByte byte -> "b " ++ show byte
  DAddress label -> "a " ++ label

zeroRun :: [DataValue] -> (Int, [DataValue])
zeroRun values = case values of
  DByte 0:rest ->
    case zeroRun rest of
      (count, tailValues) -> (count + 1, tailValues)
  _ -> (0, values)

emitFunctionIr :: (String -> IO ()) -> FunctionIr -> IO ()
emitFunctionIr write fn = case fn of
  FunctionIr name blocks -> do
    write ("F " ++ name)
    emitBlocksIr write blocks
    write "E"

emitBlocksIr :: (String -> IO ()) -> [BasicBlock] -> IO ()
emitBlocksIr write blocks = mapM_ (emitBlockIr write) blocks

emitBlockIr :: (String -> IO ()) -> BasicBlock -> IO ()
emitBlockIr write block = case block of
  BasicBlock bid instrs term -> do
    write ("L " ++ blockIdText bid)
    emitInstrsIr write instrs
    write (terminatorIrLine term)

emitInstrsIr :: (String -> IO ()) -> [Instr] -> IO ()
emitInstrsIr write instrs = mapM_ (emitInstrIr write) instrs

emitInstrIr :: (String -> IO ()) -> Instr -> IO ()
emitInstrIr write instr = case instr of
  IParam temp index -> write ("1 " ++ tempText temp ++ " " ++ show index)
  IAlloca temp size -> write ("2 " ++ tempText temp ++ " " ++ show size)
  IConst temp value -> write ("3 " ++ tempText temp ++ " " ++ show value)
  IConstBytes temp bytes -> write ("4 " ++ tempText temp ++ " B" ++ intListFields bytes)
  ICopy temp op -> emitTempOp write 5 temp op
  IAddrOf temp source -> write ("6 " ++ tempText temp ++ " " ++ tempText source)
  ILoad64 temp op -> emitTempOp write 7 temp op
  ILoad32 temp op -> emitTempOp write 8 temp op
  ILoadS32 temp op -> emitTempOp write 9 temp op
  ILoad16 temp op -> emitTempOp write 10 temp op
  ILoadS16 temp op -> emitTempOp write 11 temp op
  ILoad8 temp op -> emitTempOp write 12 temp op
  ILoadS8 temp op -> emitTempOp write 13 temp op
  IStore64 addr value -> emitOpOp write 14 addr value
  IStore32 addr value -> emitOpOp write 15 addr value
  IStore16 addr value -> emitOpOp write 16 addr value
  IStore8 addr value -> emitOpOp write 17 addr value
  ISExt temp size op -> emitExt write 22 temp size op
  IZExt temp size op -> emitExt write 23 temp size op
  ITrunc temp size op -> emitExt write 24 temp size op
  IBin temp op left right -> write ("18 " ++ tempText temp ++ " " ++ show (binOpCode op) ++ " " ++ operandIrFields left ++ " " ++ operandIrFields right)
  ICall result name args -> write ("19 " ++ maybeTempText result ++ " " ++ name ++ " " ++ operandsIrFields args)
  ICallIndirect result callee args -> write ("20 " ++ maybeTempText result ++ " " ++ operandIrFields callee ++ " " ++ operandsIrFields args)
  ICond temp condInstrs condOp trueInstrs trueOp falseInstrs falseOp -> do
    write ("21 " ++ tempText temp)
    write "["
    emitInstrsIr write condInstrs
    write "]"
    write ("O " ++ operandIrFields condOp)
    write "["
    emitInstrsIr write trueInstrs
    write "]"
    write ("O " ++ operandIrFields trueOp)
    write "["
    emitInstrsIr write falseInstrs
    write "]"
    write ("O " ++ operandIrFields falseOp)
    write "Q"

emitTempOp :: (String -> IO ()) -> Int -> Temp -> Operand -> IO ()
emitTempOp write code temp op =
  write (show code ++ " " ++ tempText temp ++ " " ++ operandIrFields op)

emitOpOp :: (String -> IO ()) -> Int -> Operand -> Operand -> IO ()
emitOpOp write code a b =
  write (show code ++ " " ++ operandIrFields a ++ " " ++ operandIrFields b)

emitExt :: (String -> IO ()) -> Int -> Temp -> Int -> Operand -> IO ()
emitExt write code temp size op =
  write (show code ++ " " ++ tempText temp ++ " " ++ show size ++ " " ++ operandIrFields op)

terminatorIrLine :: Terminator -> String
terminatorIrLine term = case term of
  TRet Nothing -> "R"
  TRet (Just op) -> "R " ++ operandIrFields op
  TJump bid -> "J " ++ blockIdText bid
  TBranch op yes no -> "B " ++ operandIrFields op ++ " " ++ blockIdText yes ++ " " ++ blockIdText no
  TBranchCmp op a b yes no -> "C " ++ show (binOpCode op) ++ " " ++ operandIrFields a ++ " " ++ operandIrFields b ++ " " ++ blockIdText yes ++ " " ++ blockIdText no

operandsIrFields :: [Operand] -> String
operandsIrFields ops = show (length ops) ++ operandsIrFieldsRest ops

operandsIrFieldsRest :: [Operand] -> String
operandsIrFieldsRest ops = case ops of
  [] -> ""
  op:rest -> ' ' : operandIrFields op ++ operandsIrFieldsRest rest

operandIrFields :: Operand -> String
operandIrFields op = case op of
  OTemp temp -> "T" ++ tempText temp
  OImm value -> "I" ++ show value
  OImmBytes bytes -> "B" ++ intListFields bytes
  OGlobal name -> "G" ++ name
  OFunction name -> "F" ++ name

intListFields :: [Int] -> String
intListFields values = show (length values) ++ intListFieldsRest values

intListFieldsRest :: [Int] -> String
intListFieldsRest values = case values of
  [] -> ""
  value:rest -> ' ' : show value ++ intListFieldsRest rest

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

binOpCode :: BinOp -> Int
binOpCode op = case op of
  IAdd -> 1
  ISub -> 2
  IMul -> 3
  IDiv -> 4
  IMod -> 5
  IShl -> 6
  IShr -> 7
  ISar -> 8
  IEq -> 9
  INe -> 10
  ILt -> 11
  ILe -> 12
  IGt -> 13
  IGe -> 14
  IULt -> 15
  IULe -> 16
  IUGt -> 17
  IUGe -> 18
  IAnd -> 19
  IOr -> 20
  IXor -> 21
  IUDiv -> 22
  IUMod -> 23

optimizeFunctionIr :: FunctionIr -> FunctionIr
optimizeFunctionIr fn = case fn of
  FunctionIr name blocks ->
    let simplified = map simplifyBasicBlock blocks
        stats = functionStats simplified
    in FunctionIr name (map (optimizeBasicBlock stats) simplified)

optimizeModuleIr :: ModuleIr -> ModuleIr
optimizeModuleIr ir = case ir of
  ModuleIr items -> ModuleIr (map optimizeTopItemIr items)

optimizeTopItemIr :: TopItemIr -> TopItemIr
optimizeTopItemIr item = case item of
  TopData dataItem -> TopData dataItem
  TopFunction fn -> TopFunction (optimizeFunctionIr fn)

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
  IUDiv -> if isOneOperand b then ICopy temp a else IBin temp op a b
  IUMod -> if isOneOperand b || sameOperand a b then IConst temp 0 else IBin temp op a b
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
    let rewritten = simplifyInstr (rewriteInstr env instr)
    in if pureForwardable globalStats localStats rewritten
       then case pureForwardValue rewritten of
         Just (Temp key, op) -> optimizeInstrs globalStats localStats (intMapInsert key op env) rest
         Nothing -> optimizeInstrs globalStats localStats env rest
       else rewritten : optimizeInstrs globalStats localStats env rest

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
  ISExt temp size op -> ISExt temp size (rewriteOperand env op)
  IZExt temp size op -> IZExt temp size (rewriteOperand env op)
  ITrunc temp size op -> ITrunc temp size (rewriteOperand env op)
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
  Temp key -> intMapLookupDefault fallback key table

lookupTempInt :: Int -> Temp -> IntMap Int -> Int
lookupTempInt fallback temp table = case temp of
  Temp key -> intMapLookupDefault fallback key table

incrementInt :: Int -> IntMap Int -> IntMap Int
incrementInt key table = intMapIncrement key table

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
  ISExt temp _ op -> countDef temp (countOperand op stats)
  IZExt temp _ op -> countDef temp (countOperand op stats)
  ITrunc temp _ op -> countDef temp (countOperand op stats)
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
  TBranchCmp _ a b _ _ -> countOperand b (countOperand a stats)

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
  ISExt temp _ op -> countBlocked temp (blockOperand op stats)
  IZExt temp _ op -> countBlocked temp (blockOperand op stats)
  ITrunc temp _ op -> countBlocked temp (blockOperand op stats)
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
  TBranchCmp _ a b _ _ -> blockOperand b (blockOperand a stats)

mapCompileRun :: Either CompileError a -> Either CodegenError a
mapCompileRun result = case result of
  Left (CompileError msg) -> Left (CodegenError msg)
  Right value -> Right value
