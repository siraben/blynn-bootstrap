module Main where

import Base
import DriverCommon
import HccSystem
import M1Ir
import Parser
import TypesAst

main :: IO ()
main = do
  hccInit
  args <- hccArgs
  case args of
    [] -> die "hcc1: no input files"
    ["--help"] -> usage >> hccExitSuccess
    "--check":files -> checkFiles files
    _ -> compileM1Ir args
  hccExitSuccess

usage :: IO ()
usage = hccPutStrLn "usage: hcc1 [--m1-ir] [-o FILE] INPUT.i\n       hcc1 --check FILE..."

checkFiles :: [String] -> IO ()
checkFiles [] = die "hcc1: no input files"
checkFiles files = mapM_ checkFile files

checkFile :: String -> IO ()
checkFile path = do
  source <- hccReadFile path
  case lexPlainSource source >>= mapParseError . parseProgram of
    Left msg -> die (path ++ ":" ++ msg)
    Right _ -> pure ()

compileM1Ir :: [String] -> IO ()
compileM1Ir args = do
  case driverArgs args of
    Left msg -> die msg
    Right opts -> do
      let trace = hccTraceIf (driverTrace opts)
      trace ("read " ++ driverInput opts)
      source <- hccReadFile (driverInput opts)
      trace "lex"
      case lexPlainSource source of
        Left msg -> die (driverInput opts ++ ":" ++ msg)
        Right toks -> do
          trace "parse"
          case mapParseError (parseProgramTarget (driverTargetBits opts) toks) of
            Left msg -> dieInputFile opts msg
            Right ast -> writeM1Ir opts trace ast

dieInputFile :: DriverOptions -> String -> IO ()
dieInputFile opts msg = die (driverInput opts ++ ":" ++ msg)

writeM1Ir :: DriverOptions -> (String -> IO ()) -> Program -> IO ()
writeM1Ir opts trace ast = do
  samePath <- hccPathsLexicallyEqual (driverInput opts) (driverOutput opts)
  when samePath (die "hcc1: input and output paths coincide")
  trace ("open " ++ driverOutput opts)
  opened <- hccWithOpenWriteFile (driverOutput opts) $ \handle -> do
    trace "m1-ir start"
    result <- hccWithTransactionalLineWriter handle $ \writeLines ->
      emitM1Ir
        writeLines
        (dataLabelPrefix (driverInput opts))
        (driverTargetBits opts)
        ast
    trace "m1-ir done"
    pure result
  case opened of
    Nothing -> die ("hcc1: cannot write " ++ driverOutput opts)
    Just result -> case result of
      Left (CodegenError msg) -> dieInputFile opts msg
      Right _ -> pure ()

mapParseError :: Either ParseError a -> Either String a
mapParseError (Left (ParseError pos msg)) = Left (showPos pos ++ ": " ++ msg)
mapParseError (Right ast) = Right ast

hccTraceIf :: Bool -> String -> IO ()
hccTraceIf enabled msg =
  when enabled (hccPutErrLine ("hcc1: " ++ msg))
