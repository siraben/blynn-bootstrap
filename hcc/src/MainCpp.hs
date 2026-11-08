module Main where

import Base
import DriverCommon
import HccSystem
import IncludeExpand
import Preprocessor
import TypesToken

main :: IO ()
main = do
  hccInit
  args <- hccArgs
  case args of
    [] -> die "hcpp: no input files"
    ["--help"] -> usage >> hccExitSuccess
    _ -> preprocessFile args
  hccExitSuccess

usage :: IO ()
usage = hccPutStrLn "usage: hcpp [CC-ARGS...] INPUT.c"

preprocessFile :: [String] -> IO ()
preprocessFile args = case driverArgs args of
  Left msg -> die msg
  Right opts -> do
    source <- readSourceWithIncludes (driverIncludeDirs opts) (driverDefines opts) (driverInput opts)
    let sourceWithDefines = renderDefines (driverDefines opts) ++ source
    case lexPlainSource sourceWithDefines >>= mapPreprocessError . preprocess of
      Left msg -> die (driverInput opts ++ ":" ++ msg)
      Right toks -> hccPutStr (foldr renderToken "\n" toks)

mapPreprocessError :: Either PreprocessError a -> Either String a
mapPreprocessError (Left (PreprocessError pos msg)) = Left (showPos pos ++ ": " ++ msg)
mapPreprocessError (Right toks) = Right toks

renderToken :: Token -> String -> String
renderToken (Token _ kind) rest = tokenText kind ++ ' ' : rest
