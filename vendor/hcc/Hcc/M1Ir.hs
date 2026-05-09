module M1Ir where

import Base
import Ast
import CodegenM1
import CompileM
import Ir
import Lower
import LowerBootstrap
import LowerImplicit

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

emitModule :: ([String] -> IO ()) -> ModuleIr -> IO ()
emitModule write moduleIr = case moduleIr of
  ModuleIr dataItems functions -> do
    emitDataItems write dataItems
    emitFunctions write functions

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

emitFunctions :: ([String] -> IO ()) -> [FunctionIr] -> IO ()
emitFunctions write functions = case functions of
  [] -> pure ()
  fn:rest -> do
    emitFunction write (optimizeFunctionIr fn)
    emitFunctions write rest

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
