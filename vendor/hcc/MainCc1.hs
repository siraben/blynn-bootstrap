module Main where

import Base
import CodegenM1 hiding (line, mapCompileError)
import DriverCommon
import HccSystem
import Parser hiding (stringLiteral)

main :: IO ()
main = do
  hccInit
  args <- hccArgs
  case args of
    [] -> die "hcc1: no input files"
    ["--help"] -> usage >> hccExitSuccess
    "--check":files -> checkFiles files
    _ | "-S" `elem` args -> compileAssembly args
    _ -> die "hcc1: expected -S or --check"

usage :: IO ()
usage = hccPutStrLn "usage: hcc1 -S [-o FILE] INPUT.i\n       hcc1 --check FILE..."

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
      source <- hccReadFile (asmInput opts)
      case lexPlainSource source of
        Left msg -> die (asmInput opts ++ ":" ++ msg)
        Right toks -> do
          case mapParseError (parseProgram toks) of
            Left msg -> die (asmInput opts ++ ":" ++ msg)
            Right ast -> do
              handle <- hccOpenWriteFile (asmOutput opts)
              case handle == 0 of
                True -> die ("hcc1: cannot write " ++ asmOutput opts)
                False -> do
                  result <- codegenM1WriteWithDataPrefix (hccWriteAndFlushLines handle) (dataLabelPrefix (asmInput opts)) ast
                  hccClose handle
                  case result of
                    Left (CodegenError msg) -> die (asmInput opts ++ ":" ++ msg)
                    Right _ -> pure ()

mapParseError :: Either ParseError a -> Either String a
mapParseError result = case result of
  Left (ParseError pos msg) -> Left (showPos pos ++ ": " ++ msg)
  Right ast -> Right ast
