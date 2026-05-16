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
    unCompileM (registerTypesAggregatesIr types) st
  _ -> Right ((), st)

registerFunctionDecl :: CType -> String -> [Param] -> CompileM ()
registerFunctionDecl ty name params = do
  registerTypeAggregates ty
  registerParamAggregates params
  bindGlobal name ty
  bindFunctionType name ty params

registerParamAggregates :: [Param] -> CompileM ()
registerParamAggregates params = case params of
  [] -> pure ()
  Param ty _:rest -> do
    registerTypeAggregates ty
    registerParamAggregates rest

registerTypesAggregatesIr :: [CType] -> CompileM ()
registerTypesAggregatesIr types = case types of
  [] -> pure ()
  ty:rest -> do
    registerTypeAggregates ty
    registerTypesAggregatesIr rest

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

mapCompileRun :: Either CompileError a -> Either CodegenError a
mapCompileRun result = case result of
  Left (CompileError msg) -> Left (CodegenError msg)
  Right value -> Right value
