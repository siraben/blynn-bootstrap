module Main where

import Base
import Ast
import CodegenM1 hiding (line, mapCompileError)
import CompileM
import DriverCommon
import HccSystem
import Ir
import Lower
import M1Ir
import Parser hiding (stringLiteral)
import Token

main :: IO ()
main = do
  hccInit
  args <- hccArgs
  case args of
    [] -> die "hcc1: no input files"
    ["--help"] -> usage >> hccExitSuccess
    "--check":files -> checkFiles files
    _ | "--tokens" `elem` args -> dumpTokens args
    _ | "--ast-summary" `elem` args -> dumpAstSummary args
    _ | "--ir-summary" `elem` args -> dumpIrSummary args
    _ | "--m1-ir" `elem` args -> compileM1Ir args
    _ | "-S" `elem` args -> compileAssembly args
    _ -> die "hcc1: expected -S or --check"

usage :: IO ()
usage = hccPutStrLn "usage: hcc1 -S [-o FILE] INPUT.i\n       hcc1 --m1-ir [-o FILE] INPUT.i\n       hcc1 --tokens [-o FILE] INPUT.i\n       hcc1 --ast-summary [-o FILE] INPUT.i\n       hcc1 --ir-summary [-o FILE] INPUT.i\n       hcc1 --check FILE..."

checkFiles :: [String] -> IO ()
checkFiles files = case files of
  [] -> die "hcc1: no input files"
  _ -> mapM_ checkFile files

checkFile :: String -> IO ()
checkFile path = do
  source <- hccReadFile path
  case lexPlainSource source >>= mapParseError . parseProgram of
    Left msg -> die (path ++ ":" ++ msg)
    Right _ -> pure ()

compileAssembly :: [String] -> IO ()
compileAssembly args = do
  case assemblyArgs args of
    Left msg -> die msg
    Right opts -> do
      let trace = hccTraceIf ("--trace" `elem` args)
      trace ("read " ++ asmInput opts)
      source <- hccReadFile (asmInput opts)
      trace "lex"
      case lexPlainSource source of
        Left msg -> die (asmInput opts ++ ":" ++ msg)
        Right toks -> do
          trace "parse"
          case mapParseError (parseProgram toks) of
            Left msg -> die (asmInput opts ++ ":" ++ msg)
            Right ast -> do
              trace ("open " ++ asmOutput opts)
              handle <- hccOpenWriteFile (asmOutput opts)
              case handle == 0 of
                True -> die ("hcc1: cannot write " ++ asmOutput opts)
                False -> do
                  trace "codegen start"
                  result <- codegenM1WriteTraceWithDataPrefix (hccWriteAndFlushLines handle) trace (dataLabelPrefix (asmInput opts)) ast
                  trace "codegen done"
                  hccClose handle
                  case result of
                    Left (CodegenError msg) -> die (asmInput opts ++ ":" ++ msg)
                    Right _ -> pure ()

compileM1Ir :: [String] -> IO ()
compileM1Ir args = do
  case assemblyArgs args of
    Left msg -> die msg
    Right opts -> do
      let trace = hccTraceIf ("--trace" `elem` args)
      trace ("read " ++ asmInput opts)
      source <- hccReadFile (asmInput opts)
      trace "lex"
      case lexPlainSource source of
        Left msg -> die (asmInput opts ++ ":" ++ msg)
        Right toks -> do
          trace "parse"
          case mapParseError (parseProgram toks) of
            Left msg -> die (asmInput opts ++ ":" ++ msg)
            Right ast -> do
              trace ("open " ++ asmOutput opts)
              handle <- hccOpenWriteFile (asmOutput opts)
              case handle == 0 of
                True -> die ("hcc1: cannot write " ++ asmOutput opts)
                False -> do
                  trace "m1-ir start"
                  result <- emitM1IrWithDataPrefix (hccWriteAndFlushLines handle) (dataLabelPrefix (asmInput opts)) ast
                  trace "m1-ir done"
                  hccClose handle
                  case result of
                    Left (CodegenError msg) -> die (asmInput opts ++ ":" ++ msg)
                    Right _ -> pure ()

mapParseError :: Either ParseError a -> Either String a
mapParseError result = case result of
  Left (ParseError pos msg) -> Left (showPos pos ++ ": " ++ msg)
  Right ast -> Right ast

hccTrace :: String -> IO ()
hccTrace msg = hccPutErrLine ("hcc1: " ++ msg)

hccTraceIf :: Bool -> String -> IO ()
hccTraceIf enabled msg =
  if enabled then hccTrace msg else pure ()

dumpTokens :: [String] -> IO ()
dumpTokens args = do
  case assemblyArgs args of
    Left msg -> die msg
    Right opts -> do
      source <- hccReadFile (asmInput opts)
      case lexPlainSource source of
        Left msg -> die (asmInput opts ++ ":" ++ msg)
        Right toks -> writeCheckpoint (asmOutput opts) (renderTokens toks)

dumpAstSummary :: [String] -> IO ()
dumpAstSummary args = do
  case assemblyArgs args of
    Left msg -> die msg
    Right opts -> do
      source <- hccReadFile (asmInput opts)
      case lexPlainSource source >>= mapParseError . parseProgram of
        Left msg -> die (asmInput opts ++ ":" ++ msg)
        Right ast -> writeCheckpoint (asmOutput opts) (renderAstSummary ast)

dumpIrSummary :: [String] -> IO ()
dumpIrSummary args = do
  case assemblyArgs args of
    Left msg -> die msg
    Right opts -> do
      source <- hccReadFile (asmInput opts)
      case lexPlainSource source >>= mapParseError . parseProgram of
        Left msg -> die (asmInput opts ++ ":" ++ msg)
        Right ast -> case lowerProgramWithDataPrefix (dataLabelPrefix (asmInput opts)) ast of
          Left err -> die (asmInput opts ++ ":" ++ compileErrorText err)
          Right ir -> writeCheckpoint (asmOutput opts) (renderIrSummary ir)

writeCheckpoint :: String -> [String] -> IO ()
writeCheckpoint path lines' = do
  handle <- hccOpenWriteFile path
  case handle == 0 of
    True -> die ("hcc1: cannot write " ++ path)
    False -> hccWriteAndFlushLines handle lines' >> hccClose handle

renderTokens :: [Token] -> [String]
renderTokens toks = case toks of
  [] -> []
  Token tokSpan kind:rest -> (renderSpan tokSpan ++ " " ++ renderTokenKind kind) : renderTokens rest

renderSpan :: Span -> String
renderSpan (Span (SrcPos line col) _) = show line ++ ":" ++ show col

renderTokenKind :: TokenKind -> String
renderTokenKind kind = case kind of
  TokIdent s -> "ident " ++ s
  TokInt s -> "int " ++ s
  TokChar s -> "char " ++ s
  TokString s -> "string " ++ s
  TokPunct s -> "punct " ++ s
  TokDirective s -> "directive " ++ s

renderAstSummary :: Program -> [String]
renderAstSummary (Program decls) =
  ("top_decls " ++ show (length decls))
  : renderTopDecls decls

renderTopDecls :: [TopDecl] -> [String]
renderTopDecls decls = case decls of
  [] -> []
  decl:rest -> renderTopDecl decl : renderTopDecls rest

renderTopDecl :: TopDecl -> String
renderTopDecl decl = case decl of
  Function _ name params body ->
    "function " ++ name ++ " params=" ++ show (length params) ++ " stmts=" ++ show (length body)
  Prototype _ name params ->
    "prototype " ++ name ++ " params=" ++ show (length params)
  Global _ name initExpr ->
    "global " ++ name ++ " init=" ++ renderMaybe initExpr
  Globals globals ->
    "globals count=" ++ show (length globals)
  ExternGlobals globals ->
    "extern_globals count=" ++ show (length globals)
  StructDecl isUnion name fields ->
    renderStructKind isUnion ++ " " ++ name ++ " fields=" ++ show (length fields)
  EnumConstants constants ->
    "enum_constants count=" ++ show (length constants)
  TypeDecl -> "typedef"

renderMaybe :: Maybe a -> String
renderMaybe value = case value of
  Nothing -> "no"
  Just _ -> "yes"

renderStructKind :: Bool -> String
renderStructKind isUnion =
  if isUnion then "union" else "struct"

renderIrSummary :: ModuleIr -> [String]
renderIrSummary (ModuleIr dataItems functions) =
  [ "data_items " ++ show (length dataItems)
  , "functions " ++ show (length functions)
  ]
  ++ renderDataItems dataItems
  ++ renderFunctions functions

renderDataItems :: [DataItem] -> [String]
renderDataItems items = case items of
  [] -> []
  DataItem name values:rest ->
    ("data " ++ name ++ " values=" ++ show (length values)) : renderDataItems rest

renderFunctions :: [FunctionIr] -> [String]
renderFunctions functions = case functions of
  [] -> []
  FunctionIr name params blocks:rest ->
    ("function " ++ name ++ " params=" ++ show (length params) ++ " blocks=" ++ show (length blocks) ++ " instrs=" ++ show (countBlockInstrs blocks)) : renderFunctions rest

countBlockInstrs :: [BasicBlock] -> Int
countBlockInstrs blocks = case blocks of
  [] -> 0
  BasicBlock _ instrs _:rest -> length instrs + countBlockInstrs rest

compileErrorText :: CompileError -> String
compileErrorText (CompileError msg) = msg
