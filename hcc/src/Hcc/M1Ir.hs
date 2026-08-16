module M1Ir
  ( CodegenError(..)
  , emitM1IrWithDataPrefixTarget
  ) where

import Base
import TypesAst
import CompileM
import TypesIr
import Lower
import LowerBootstrap
import LowerImplicit
import SymbolTable

data CodegenError = CodegenError String

emitM1IrWithDataPrefixTarget :: (String -> IO ()) -> String -> Int -> Program -> IO (Either CodegenError ())
emitM1IrWithDataPrefixTarget write prefix target ast =
  case buildM1IrModuleWithDataPrefixTarget prefix target ast of
    Left err -> pure (Left err)
    Right ir -> do
      write "HCCIR 1"
      emitModuleIr write ir
      pure (Right ())

buildM1IrModuleWithDataPrefixTarget :: String -> Int -> Program -> Either CodegenError ModuleIr
buildM1IrModuleWithDataPrefixTarget prefix target ast = case ast of
  Program decls ->
    case mapCompileRun (runCompileM registerBuiltinStructs (initialCompileStateForTarget prefix target)) of
      Left err -> Left err
      Right (_, st0) ->
        case mapCompileRun (runCompileM (registerInternalAliases prefix decls) st0) of
          Left err -> Left err
          Right (_, stAliases) ->
            case registerTopDeclsIr stAliases decls of
              Left err -> Left err
              Right (st, registeredItems) ->
                case lowerTopDeclsIr st decls of
                  Left err -> Left err
                  Right (_, functionItems) ->
                    normalizeAddressAddends target (ModuleIr (registeredItems ++ functionItems))

registerInternalAliases :: String -> [TopDecl] -> CompileM ()
registerInternalAliases prefix decls = case decls of
  [] -> pure ()
  decl:rest -> do
    registerInternalAlias prefix decl
    registerInternalAliases prefix rest

registerInternalAlias :: String -> TopDecl -> CompileM ()
registerInternalAlias prefix decl = case decl of
  Function InternalLinkage _ name _ _ ->
    bindSymbolAlias name (internalSymbolName prefix name)
  Prototype InternalLinkage _ name _ ->
    bindSymbolAlias name (internalSymbolName prefix name)
  Global InternalLinkage _ name _ ->
    bindSymbolAlias name (internalSymbolName prefix name)
  Globals InternalLinkage globals ->
    registerInternalGlobalAliases prefix globals
  _ -> pure ()

registerInternalGlobalAliases :: String -> [(CType, String, Maybe Expr)] -> CompileM ()
registerInternalGlobalAliases prefix globals = case globals of
  [] -> pure ()
  (_, name, _):rest -> do
    bindSymbolAlias name (internalSymbolName prefix name)
    registerInternalGlobalAliases prefix rest

internalSymbolName :: String -> String -> String
internalSymbolName prefix name = "HCC_INTERNAL_" ++ prefix ++ "_" ++ name

lowerTopDeclsIr :: CompileState -> [TopDecl] -> Either CodegenError (CompileState, [TopItemIr])
lowerTopDeclsIr st decls = case decls of
  [] -> Right (st, [])
  Function _ _ name params body:rest ->
    case mapCompileRun (runCompileM (do
      resolved <- resolveSymbolName name
      registerImplicitCalls (map (\(Param _ paramName) -> paramName) params) body
      fn <- lowerFunction name params body
      pure (renameFunctionIr resolved fn)) st) of
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
  Global _ ty name initExpr ->
    case mapCompileRun (runCompileM (do
      registerTypeAggregates ty
      bindGlobal name ty
      values <- withErrorContext ("global " ++ name) (globalData ty initExpr)
      resolved <- resolveSymbolName name
      pure (resolved, values)) st) of
      Left err -> Left err
      Right ((resolved, values), st') -> do
        case pendingDataItemsIr st' of
          (pending, st'') -> Right (st'', TopData (DataItem resolved values) : pending)
  Globals _ globals ->
    registerGlobalsIr st globals
  _ ->
    case mapCompileRun (registerTopDeclShallowState st decl) of
      Left err -> Left err
      Right (_, st') -> Right (st', [])

registerTopDeclShallowState :: CompileState -> TopDecl -> Either CompileError ((), CompileState)
registerTopDeclShallowState st decl = case decl of
  Function _ ty name params _ ->
    runCompileM (registerFunctionDecl ty name params) st
  Prototype _ ty name params ->
    runCompileM (registerFunctionDecl ty name params) st
  StructDecl isUnion name fields ->
    runCompileM (registerFieldAggregates fields >> bindStruct name isUnion fields) st
  ExternGlobals globals ->
    runCompileM (registerExternGlobals globals) st
  EnumConstants constants ->
    runCompileM (mapM_ (uncurry bindConstant) constants) st
  TypeDecl types ->
    runCompileM (mapM_ registerTypeAggregates types) st
  _ -> Right ((), st)

registerFunctionDecl :: CType -> String -> [Param] -> CompileM ()
registerFunctionDecl ty name params = do
  registerTypeAggregates ty
  mapM_ registerTypeAggregates (paramTypes params)
  bindGlobal name ty
  bindFunctionType name ty params

registerGlobalsIr :: CompileState -> [(CType, String, Maybe Expr)] -> Either CodegenError (CompileState, [TopItemIr])
registerGlobalsIr st globals = case globals of
  [] -> Right (st, [])
  (ty, name, initExpr):rest ->
    case mapCompileRun (runCompileM (do
      registerTypeAggregates ty
      bindGlobal name ty
      values <- withErrorContext ("global " ++ name) (globalData ty initExpr)
      resolved <- resolveSymbolName name
      pure (resolved, values)) st) of
      Left err -> Left err
      Right ((resolved, values), st') ->
        case pendingDataItemsIr st' of
          (pending, st'') ->
            case registerGlobalsIr st'' rest of
              Left err -> Left err
              Right (stFinal, restItems) -> Right (stFinal, TopData (DataItem resolved values) : pending ++ restItems)

renameFunctionIr :: String -> FunctionIr -> FunctionIr
renameFunctionIr resolved fn = case fn of
  FunctionIr _ blocks -> FunctionIr resolved blocks

pendingDataItemsIr :: CompileState -> ([TopItemIr], CompileState)
pendingDataItemsIr st = case csDataItems st of
  [] -> ([], st)
  items -> (map TopData (reverse items), st { csDataItems = [] })

emitModuleIr :: (String -> IO ()) -> ModuleIr -> IO ()
emitModuleIr write ir = case ir of
  ModuleIr items -> emitTopItemsIr write items

emitTopItemsIr :: (String -> IO ()) -> [TopItemIr] -> IO ()
emitTopItemsIr write = mapM_ (emitTopItemIr write)

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
  DAddress label offset -> "a " ++ label ++ " " ++ show offset
  DLabel label -> "l " ++ label

zeroRun :: [DataValue] -> (Int, [DataValue])
zeroRun values = case values of
  DByte 0:rest ->
    case zeroRun rest of
      (count, tailValues) -> (count + 1, tailValues)
  _ -> (0, values)

normalizeAddressAddends :: Int -> ModuleIr -> Either CodegenError ModuleIr
normalizeAddressAddends target ir = case ir of
  ModuleIr items ->
    let refs = addressAddendRefsTopItems items
        word = if target == 32 then 4 else 8
    in case normalizeAddressAddendTopItems word refs items of
      Left err -> Left err
      Right normalized -> Right (ModuleIr normalized)

addressAddendRefsTopItems :: [TopItemIr] -> SymbolMap [Int]
addressAddendRefsTopItems = collectTopItems symbolMapEmpty

collectTopItems :: SymbolMap [Int] -> [TopItemIr] -> SymbolMap [Int]
collectTopItems refs items = case items of
  [] -> refs
  TopData (DataItem _ values):rest ->
    collectTopItems (collectDataValues refs values) rest
  _:rest -> collectTopItems refs rest

collectDataValues :: SymbolMap [Int] -> [DataValue] -> SymbolMap [Int]
collectDataValues refs values = case values of
  [] -> refs
  DAddress label offset:rest ->
    if offset == 0
      then collectDataValues refs rest
      else
        let offsets = case symbolMapLookup label refs of
              Nothing -> []
              Just existing -> existing
            refs' = symbolMapInsert label (insertOffset offset offsets) refs
        in collectDataValues refs' rest
  _:rest -> collectDataValues refs rest

normalizeAddressAddendTopItems :: Int -> SymbolMap [Int] -> [TopItemIr] -> Either CodegenError [TopItemIr]
normalizeAddressAddendTopItems word refs items = case items of
  [] -> Right []
  TopData item:rest ->
    case normalizeAddressAddendDataItem word refs item of
      Left err -> Left err
      Right normalizedItem ->
        case normalizeAddressAddendTopItems word refs rest of
          Left err -> Left err
          Right normalizedRest -> Right (TopData normalizedItem : normalizedRest)
  TopFunction fn:rest ->
    case normalizeAddressAddendTopItems word refs rest of
      Left err -> Left err
      Right normalizedRest -> Right (TopFunction fn : normalizedRest)

normalizeAddressAddendDataItem :: Int -> SymbolMap [Int] -> DataItem -> Either CodegenError DataItem
normalizeAddressAddendDataItem word refs item = case item of
  DataItem label values ->
    let offsets = case symbolMapLookup label refs of
          Nothing -> []
          Just existing -> existing
        size = dataValuesSize word values
    in case validateOffsets word label size values offsets of
      Left err -> Left err
      Right () -> Right (DataItem label (rewriteAddressAddends (insertInteriorLabels word label offsets 0 values)))

insertOffset :: Int -> [Int] -> [Int]
insertOffset value values = case values of
  [] -> [value]
  x:xs ->
    if value == x
      then values
      else if value < x
        then value : values
        else x : insertOffset value xs

validateOffsets :: Int -> String -> Int -> [DataValue] -> [Int] -> Either CodegenError ()
validateOffsets word label size values offsets = case offsets of
  [] -> Right ()
  offset:rest ->
    if offset < 0 || offset > size
      then Left (CodegenError ("global address initializer points outside data object " ++ label))
      else if not (offsetIsDataBoundary word offset 0 values)
        then Left (CodegenError ("global address initializer points inside an indivisible data value in " ++ label))
        else validateOffsets word label size values rest

offsetIsDataBoundary :: Int -> Int -> Int -> [DataValue] -> Bool
offsetIsDataBoundary word offset pos values =
  if offset == pos
    then True
    else case values of
      [] -> False
      value:rest -> offsetIsDataBoundary word offset (pos + dataValueSize word value) rest

insertInteriorLabels :: Int -> String -> [Int] -> Int -> [DataValue] -> [DataValue]
insertInteriorLabels word label offsets pos values =
  let (here, later) = splitOffsetsAt pos offsets
      labels = dataInteriorLabels label here
  in case values of
    [] -> labels
    value:rest ->
      let next = pos + dataValueSize word value
      in labels ++ value : insertInteriorLabels word label later next rest

splitOffsetsAt :: Int -> [Int] -> ([Int], [Int])
splitOffsetsAt pos offsets = case offsets of
  [] -> ([], [])
  offset:rest ->
    if offset == pos
      then case splitOffsetsAt pos rest of
        (same, later) -> (offset:same, later)
      else ([], offsets)

dataInteriorLabels :: String -> [Int] -> [DataValue]
dataInteriorLabels label offsets = case offsets of
  [] -> []
  offset:rest -> DLabel (dataInteriorLabel label offset) : dataInteriorLabels label rest

rewriteAddressAddends :: [DataValue] -> [DataValue]
rewriteAddressAddends values = case values of
  [] -> []
  DAddress label offset:rest ->
    if offset == 0
      then DAddress label 0 : rewriteAddressAddends rest
      else DAddress (dataInteriorLabel label offset) 0 : rewriteAddressAddends rest
  value:rest -> value : rewriteAddressAddends rest

dataInteriorLabel :: String -> Int -> String
dataInteriorLabel label offset = "HCC_DATA_" ++ label ++ "_" ++ show offset

dataValuesSize :: Int -> [DataValue] -> Int
dataValuesSize word values = case values of
  [] -> 0
  value:rest -> dataValueSize word value + dataValuesSize word rest

dataValueSize :: Int -> DataValue -> Int
dataValueSize word value = case value of
  DByte _ -> 1
  DAddress _ _ -> word
  DLabel _ -> 0

emitFunctionIr :: (String -> IO ()) -> FunctionIr -> IO ()
emitFunctionIr write fn = case fn of
  FunctionIr name blocks -> do
    write ("F " ++ name)
    emitBlocksIr write blocks
    write "E"

emitBlocksIr :: (String -> IO ()) -> [BasicBlock] -> IO ()
emitBlocksIr write = mapM_ (emitBlockIr write)

emitBlockIr :: (String -> IO ()) -> BasicBlock -> IO ()
emitBlockIr write block = case block of
  BasicBlock bid instrs term -> do
    write ("L " ++ blockIdText bid)
    emitInstrsIr write instrs
    write (terminatorIrLine term)

emitInstrsIr :: (String -> IO ()) -> [Instr] -> IO ()
emitInstrsIr write = mapM_ (emitInstrIr write)

emitInstrIr :: (String -> IO ()) -> Instr -> IO ()
emitInstrIr write instr = case instr of
  IParam temp index -> write ("1 " ++ tempText temp ++ " " ++ show index)
  IAlloca temp size -> write ("2 " ++ tempText temp ++ " " ++ show size)
  IConst temp value -> write ("3 " ++ tempText temp ++ " " ++ show value)
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
  ICall result name args -> write ("19 " ++ maybe "-" tempText result ++ " " ++ name ++ " " ++ listIrFields operandIrFields args)
  ICallIndirect result callee args -> write ("20 " ++ maybe "-" tempText result ++ " " ++ operandIrFields callee ++ " " ++ listIrFields operandIrFields args)
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

operandIrFields :: Operand -> String
operandIrFields op = case op of
  OTemp temp -> "T" ++ tempText temp
  OImm value -> "I" ++ show value
  OImmBytes bytes -> "B" ++ listIrFields show bytes
  OGlobal name -> "G" ++ name
  OFunction name -> "F" ++ name

listIrFields :: (a -> String) -> [a] -> String
listIrFields render values = show (length values) ++ listIrFieldsRest render values

listIrFieldsRest :: (a -> String) -> [a] -> String
listIrFieldsRest render values = case values of
  [] -> ""
  value:rest -> ' ' : render value ++ listIrFieldsRest render rest

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

mapCompileRun :: Either CompileError a -> Either CodegenError a
mapCompileRun result = case result of
  Left (CompileError msg) -> Left (CodegenError msg)
  Right value -> Right value
