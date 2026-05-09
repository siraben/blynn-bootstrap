module Main where

import Base
import DriverCommon
import HccSystem
import IncludeExpand
import Preprocessor hiding (charCode, directiveName, dropSpaces, isAsciiAlpha, isAsciiAlphaNum, isDigitChar, isIdentChar, isIdentStart, ppIsSpace, prefixOf, spanStart, suffixOf, token, tokenKind, tokenStart, tokens, trim)
import Token

main :: IO ()
main = do
  hccInit
  args <- hccArgs
  case args of
    [] -> die "hcpp: no input files"
    ["--help"] -> usage >> hccExitSuccess
    _ -> preprocessFile args

usage :: IO ()
usage = hccPutStrLn "usage: hcpp [CC-ARGS...] INPUT.c"

preprocessFile :: [String] -> IO ()
preprocessFile args = case assemblyArgs ("-S":args) of
  Left msg -> die msg
  Right opts -> do
    source <- readSourceWithIncludes (asmIncludeDirs opts) (asmDefines opts) (asmInput opts)
    let sourceWithDefines = renderDefines (asmDefines opts) ++ source
    case lexPlainSource sourceWithDefines >>= mapPreprocessError . preprocess of
      Left msg -> die (asmInput opts ++ ":" ++ msg)
      Right toks -> hccPutStr (renderTokens toks)

mapPreprocessError :: Either PreprocessError a -> Either String a
mapPreprocessError result = case result of
  Left (PreprocessError pos msg) -> Left (showPos pos ++ ": " ++ msg)
  Right toks -> Right toks

renderTokens :: [Token] -> String
renderTokens toks = go toks "\n"
  where
    go rest = case rest of
      [] -> id
      Token _ kind:rest' ->
        (tokenText kind++)
        . (' ':)
        . go rest'
