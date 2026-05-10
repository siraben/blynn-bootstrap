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
    _ | "--m1-ir" `elem` args -> compileM1Ir args
    _ -> die "hcc1: expected --m1-ir or --check"

usage :: IO ()
usage = hccPutStrLn "usage: hcc1 --m1-ir [-o FILE] INPUT.i\n       hcc1 --check FILE..."

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
            Left msg -> dieInputFile opts msg
            Right ast -> writeM1Ir opts trace ast

dieInputFile :: AsmOptions -> String -> IO ()
dieInputFile opts msg = die (asmInput opts ++ ":" ++ msg)

writeM1Ir :: AsmOptions -> (String -> IO ()) -> Program -> IO ()
writeM1Ir opts trace ast = do
  traceLine trace ("open " ++ asmOutput opts)
  opened <- hccWithOpenWriteFile (asmOutput opts) $ \handle -> do
    traceLine trace "m1-ir start"
    result <- hccWithHandleLineWriter handle $ \writeLines ->
      emitM1IrWithDataPrefixTarget
        writeLines
        (dataLabelPrefix (asmInput opts))
        (asmTargetBits opts)
        ast
    traceLine trace "m1-ir done"
    pure result
  case opened of
    Nothing -> die ("hcc1: cannot write " ++ asmOutput opts)
    Just result -> case result of
      Left (CodegenError msg) -> dieInputFile opts msg
      Right _ -> pure ()

traceLine :: (String -> IO a) -> String -> IO ()
traceLine trace msg = trace msg >> pure ()

mapParseError :: Either ParseError a -> Either String a
mapParseError (Left (ParseError pos msg)) = Left (showPos pos ++ ": " ++ msg)
mapParseError (Right ast) = Right ast

hccTrace :: String -> IO ()
hccTrace msg = hccPutErrLine ("hcc1: " ++ msg)

hccTraceIf :: Bool -> String -> IO ()
hccTraceIf enabled msg =
  if enabled then hccTrace msg else pure ()
