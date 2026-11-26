module M1Ir
  ( CodegenError(..)
  , emitM1Ir
  ) where

import Base
import TypesAst
import CompileM
import TypesIr
import Lower
import LowerRegisters
import LowerBootstrap

data CodegenError = CodegenError String

-- The caller buffers writes transactionally: a later lowering error must not
-- publish the header or any previously emitted functions.
emitM1Ir :: (String -> IO ()) -> String -> Int -> Program -> IO (Either CodegenError ())
emitM1Ir write prefix target ast = case ast of
  Program decls ->
    case mapCompileRun (runCompileM (do
      registerBuiltinStructs
      registerTopDeclsIr decls) (initialCompileStateForTarget prefix target)) of
      Left err -> pure (Left err)
      Right (registeredItems, st) -> do
        write "HCCIR 1"
        mapM_ (emitDataItemIr write) registeredItems
        lowerAndEmitTopDeclsIr write st decls

lowerAndEmitTopDeclsIr :: (String -> IO ()) -> CompileState -> [TopDecl] -> IO (Either CodegenError ())
lowerAndEmitTopDeclsIr write st decls = case decls of
  [] -> pure (Right ())
  Function _ name params body:rest ->
    case mapCompileRun (runCompileM (lowerFunction name params body) st) of
      Left err -> pure (Left err)
      Right (fn, st') ->
        case pendingDataItemsIr st' of
          (pending, st'') -> do
            emitFunctionIr write fn
            mapM_ (emitDataItemIr write) pending
            lowerAndEmitTopDeclsIr write st'' rest
  _:rest -> lowerAndEmitTopDeclsIr write st rest

registerTopDeclsIr :: [TopDecl] -> CompileM [DataItem]
registerTopDeclsIr decls = concat <$> mapM registerTopDeclIr decls

registerTopDeclIr :: TopDecl -> CompileM [DataItem]
registerTopDeclIr decl = case decl of
  Globals globals -> registerGlobalsIr globals
  Function ty name params _ -> registerFunctionDecl ty name params >> pure []
  Prototype ty name params -> registerFunctionDecl ty name params >> pure []
  ExternGlobals globals -> registerExternGlobals globals >> pure []
  EnumConstants constants -> mapM_ (uncurry bindConstant) constants >> pure []
  TypeDecl types -> mapM_ registerTypeIntroductions types >> pure []

registerGlobal :: CType -> String -> Maybe Expr -> CompileM [DataValue]
registerGlobal declTy name initExpr = do
  let ty = completeArrayType declTy initExpr
  registerTypeIntroductions ty
  bindGlobal name ty
  globalData ty initExpr

registerFunctionDecl :: CType -> String -> [Param] -> CompileM ()
registerFunctionDecl ty name params = do
  registerTypeIntroductions ty
  mapM_ registerTypeIntroductions (paramTypes params)
  bindGlobal name ty
  bindFunctionType name ty params

registerGlobalsIr :: [(CType, String, Maybe Expr)] -> CompileM [DataItem]
registerGlobalsIr globals = case globals of
  [] -> pure []
  (ty, name, initExpr):rest -> do
    values <- registerGlobal ty name initExpr
    pending <- CompileM $ \st -> case pendingDataItemsIr st of
      (items, st') -> StepOk items st'
    restItems <- registerGlobalsIr rest
    pure (DataItem name values : pending ++ restItems)

pendingDataItemsIr :: CompileState -> ([DataItem], CompileState)
pendingDataItemsIr st = case csDataItems st of
  [] -> ([], st)
  items -> (reverse items, st { csDataItems = [] })

emitDataItemIr :: (String -> IO ()) -> DataItem -> IO ()
emitDataItemIr write item = case item of
  DataItem label values -> do
    write ("D " ++ label)
    emitDataValuesIr write values
    write "E"

emitDataValuesIr :: (String -> IO ()) -> [DataValue] -> IO ()
-- Coalesce explicit zero bytes and sized padding into the same wire record.
emitDataValuesIr write = go 0 where
  flush zeros = when (zeros /= 0) (write ("z " ++ show zeros))
  go zeros values = case values of
    [] -> flush zeros
    value:rest -> case value of
      DByte 0 -> go (zeros + 1) rest
      DZero count -> go (zeros + count) rest
      DByte byte -> flush zeros >> write ("b " ++ show byte) >> go 0 rest
      DAddress label -> flush zeros >> write ("a " ++ label) >> go 0 rest

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
