module Main where

import Base
import DriverCommon
import HccSystem
import IncludeExpand
import TypesToken

main :: IO ()
main = do
  hccInit
  args <- hccArgs
  case args of
    [] -> die "hcpp: no input files"
    ["--help"] -> usage
    _ -> preprocessFile args
  hccExitSuccess

usage :: IO ()
usage = hccPutStrLn "usage: hcpp [CC-ARGS...] INPUT.c"

preprocessFile :: [String] -> IO ()
preprocessFile args = case driverArgs args of
  Left msg -> die msg
  Right opts -> do
    toks <- preprocessFileTokens (driverIncludeDirs opts) (driverDefines opts) (driverInput opts)
    hccPutStr (foldr renderToken "\n" toks)

renderToken :: Token -> String -> String
renderToken (Token _ kind) rest = tokenText kind ++ ' ' : rest
