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

usage :: IO ()
usage = hccPutStrLn "usage: hcc1 [--m1-ir] [--soft-float-runtime] [--data-prefix UNIT] [-o FILE] INPUT.i\n       hcc1 --check FILE..."

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
  case extractDataPrefix args of
    Left msg -> die msg
    Right (unit, remainingArgs) -> case extractSoftFloatRuntime remainingArgs of
      Left msg -> die msg
      Right (softFloatRuntime, assemblyArgList) -> case assemblyArgs assemblyArgList of
        Left msg -> die msg
        Right opts -> do
          let trace = hccTraceIf (asmTrace opts)
          trace ("read " ++ asmInput opts)
          source <- hccReadFile (asmInput opts)
          trace "lex"
          case lexPlainSource source of
            Left msg -> die (asmInput opts ++ ":" ++ msg)
            Right toks -> do
              trace "parse"
              case mapParseError (parseProgram toks) of
                Left msg -> dieInputFile opts msg
                Right ast -> writeM1Ir unit softFloatRuntime opts trace ast

extractDataPrefix :: [String] -> Either String (Maybe String, [String])
extractDataPrefix args = go Nothing args where
  go unit rest = case rest of
    [] -> Right (unit, [])
    ["--data-prefix"] -> Left "hcc1: option --data-prefix requires an argument"
    "--data-prefix":value:xs -> case unit of
      Just _ -> Left "hcc1: option --data-prefix specified more than once"
      Nothing -> go (Just value) xs
    arg:xs -> do
      (found, remaining) <- go unit xs
      Right (found, arg:remaining)

extractSoftFloatRuntime :: [String] -> Either String (Bool, [String])
extractSoftFloatRuntime args = go False args where
  go enabled rest = case rest of
    [] -> Right (enabled, [])
    "--soft-float-runtime":xs ->
      if enabled
        then Left "hcc1: option --soft-float-runtime specified more than once"
        else go True xs
    arg:xs -> do
      (found, remaining) <- go enabled xs
      Right (found, arg:remaining)

dieInputFile :: AsmOptions -> String -> IO ()
dieInputFile opts msg = die (asmInput opts ++ ":" ++ msg)

writeM1Ir :: Maybe String -> Bool -> AsmOptions -> (String -> IO ()) -> Program -> IO ()
writeM1Ir unit softFloatRuntime opts trace ast = do
  trace ("open " ++ asmOutput opts)
  opened <- hccWithOpenWriteFile (asmOutput opts) $ \handle -> do
    trace "m1-ir start"
    result <- hccWithHandleLineWriter handle $ \writeLines ->
      emitM1IrWithDataPrefixTarget
        writeLines
        (case unit of
          Nothing -> dataLabelPrefix (asmInput opts)
          Just name -> dataLabelPrefixForUnit name)
        (asmTargetBits opts)
        softFloatRuntime
        ast
    trace "m1-ir done"
    pure result
  case opened of
    Nothing -> die ("hcc1: cannot write " ++ asmOutput opts)
    Just result -> case result of
      Left (CodegenError msg) -> dieInputFile opts msg
      Right _ -> pure ()

mapParseError :: Either ParseError a -> Either String a
mapParseError (Left (ParseError pos msg)) = Left (showPos pos ++ ": " ++ msg)
mapParseError (Right ast) = Right ast

hccTraceIf :: Bool -> String -> IO ()
hccTraceIf enabled msg =
  when enabled (hccPutErrLine ("hcc1: " ++ msg))
