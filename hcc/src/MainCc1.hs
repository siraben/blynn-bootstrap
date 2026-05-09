module Main where

import Base
import CodegenM1 hiding (line, mapCompileError)
import DriverCommon
import HccSystem
import M1Ir
import Parser hiding (stringLiteral)

main :: IO ()
main = do
  hccInit
  args <- hccArgs
  case args of
    [] -> die "hcc1: no input files"
    ["--help"] -> usage >> hccExitSuccess
    "--check":files -> checkFiles files
    _ | "--m1-ir" `elem` args -> compileM1Ir args
    _ | "-S" `elem` args -> compileAssembly args
    _ -> die "hcc1: expected -S or --check"

usage :: IO ()
usage = hccPutStrLn "usage: hcc1 -S [-o FILE] INPUT.i\n       hcc1 --m1-ir [-o FILE] INPUT.i\n       hcc1 --check FILE..."

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
