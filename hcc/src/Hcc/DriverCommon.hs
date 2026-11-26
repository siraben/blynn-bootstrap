module DriverCommon
  ( DriverOptions(..)
  , die
  , lexPlainSource
  , normalizeSource
  , lexNormalizedSource
  , dataLabelPrefix
  , driverArgs
  , replaceExt
  , showPos
  ) where

import Base
import HccSystem
import Lexer
import TextUtil
import TypesToken

die :: String -> IO ()
die msg = hccPutErrLine msg >> hccExitFailure

-- Translation phases run once per physical input, before directive recognition.
lexPlainSource :: String -> Either String [Token]
lexPlainSource source = normalizeSource source >>= lexNormalizedSource

lexNormalizedSource :: String -> Either String [Token]
lexNormalizedSource source = case lexC source of
  Left (LexError pos msg) -> Left (showPos pos ++ ": " ++ msg)
  Right toks -> Right toks

spliceContinuations :: String -> String
spliceContinuations text = case text of
  [] -> []
  '\\':rest -> case rest of
    '\n':more -> spliceContinuations more
    '\x0d':'\n':more -> spliceContinuations more
    _ -> '\\' : spliceContinuations rest
  c:rest -> c : spliceContinuations rest

-- Keep comment columns/newlines as whitespace: macro adjacency and diagnostics
-- must not depend on the length of a removed comment. Positions are post-splice.
normalizeSource :: String -> Either String String
normalizeSource source = normal [] (spliceContinuations source)
  where
  normal out text = case text of
    [] -> Right (reverse out)
    -- A comment or a quoted text starts with '/', '"' or '\''. These are
    -- after ' ' and before '0': most characters need no more comparisons.
    c:rest | '0' <= c || c <= ' ' -> normal (c:out) rest
    '/':'/':rest -> lineComment (' ':' ':out) rest
    '/':'*':rest -> blockComment out (' ':' ':out) rest
    '"':rest -> quoted '"' ('"':out) rest
    '\'':rest -> quoted '\'' ('\'':out) rest
    c:rest -> normal (c:out) rest
  lineComment out text = case text of
    [] -> Right (reverse out)
    '\n':rest -> normal ('\n':out) rest
    _:rest -> lineComment (' ':out) rest
  blockComment start out text = case text of
    [] -> Left (showPos (posAfter start) ++ ": unterminated block comment")
    '*':'/':rest -> normal (' ':' ':out) rest
    -- A block comment is whitespace even across physical lines.
    _:rest -> blockComment start (' ':out) rest
  quoted quote out text = case text of
    [] -> Right (reverse out)
    '\\':c:rest -> quoted quote (c:'\\':out) rest
    c:rest -> (if c == quote then normal else quoted quote) (c:out) rest
  posAfter out =
    SrcPos (1 + length (filter (== '\n') out)) (1 + length (takeWhile (/= '\n') out))

dataLabelPrefix :: String -> String
dataLabelPrefix path =
  "HCC_DATA_" ++ sanitized
  where
    sanitized = case sanitizeLabel (hccTakeFileName path) of
      [] -> "unit"
      text -> text

sanitizeLabel :: String -> String
sanitizeLabel = concatMap sanitizeLabelChar

sanitizeLabelChar :: Char -> String
sanitizeLabelChar c =
  if isAsciiAlphaNum c then [c] else "_"

data DriverOptions = DriverOptions
  { driverInput :: String
  , driverOutput :: String
  , driverIncludeDirs :: [String]
  , driverDefines :: [(String, String)]
  , driverTargetBits :: Int
  , driverTrace :: Bool
  }

driverArgs :: [String] -> Either String DriverOptions
driverArgs args = finish (go args Nothing Nothing [] [] 64)
  where
    finish (Left msg) = Left msg
    finish (Right (_, Nothing, _, _, _)) = Left "hcc: no input files"
    finish (Right (out, Just path, includes, defines, target)) =
      Right (DriverOptions path (maybe (replaceExt path ".hccir") id out) (reverse includes) (reverse defines) target ("--trace" `elem` args))

    go [] out input includes defines target =
      Right (out, input, includes, defines, target)
    go ["-o"] _ _ _ _ _ = Left "hcc: option -o requires an argument"
    go ["-I"] _ _ _ _ _ = Left "hcc: option -I requires an argument"
    go ["-D"] _ _ _ _ _ = Left "hcc: option -D requires an argument"
    go ["--target"] _ _ _ _ _ = Left "hcc: option --target requires an argument"
    go ("-S":xs) out input includes defines target =
      go xs out input includes defines target
    go ("-o":path:xs) _ input includes defines target =
      go xs (Just path) input includes defines target
    go ("-I":path:xs) out input includes defines target =
      go xs out input (path:includes) defines target
    go ("-D":def:xs) out input includes defines target =
      go xs out input includes (parseDefine def:defines) target
    go ("--target":targetName:xs) out input includes defines _ =
      case parseTargetBits targetName of
        Just bits -> go xs out input includes defines bits
        Nothing -> Left ("hcc: unsupported target: " ++ targetName)
    go (flag:xs) out input includes defines target = case flag of
      '-':'I':path@(_:_) ->
        go xs out input (path:includes) defines target
      '-':'D':def@(_:_) ->
        go xs out input includes (parseDefine def:defines) target
      _
        | ignoredDriverFlag flag ->
            go xs out input includes defines target
        | take 1 flag == "-" ->
            Left ("hcc: unsupported option: " ++ flag)
        | otherwise ->
            go xs out (Just flag) includes defines target

parseTargetBits :: String -> Maybe Int
parseTargetBits target = case target of
  "amd64" -> Just 64
  "x86_64" -> Just 64
  "aarch64" -> Just 64
  "arm64" -> Just 64
  "riscv64" -> Just 64
  "i386" -> Just 32
  "x86" -> Just 32
  _ -> Nothing

ignoredDriverFlag :: String -> Bool
ignoredDriverFlag flag =
  flag `elem` ["-c", "-pipe", "-nostdinc", "-nostdlib", "-static", "--m1-ir", "--trace"]

parseDefine :: String -> (String, String)
parseDefine def = case break (== '=') def of
  (name, "") -> (name, "1")
  (name, _:value) -> (name, unescapeDefineValue value)

unescapeDefineValue :: String -> String
unescapeDefineValue [] = []
unescapeDefineValue ('\\':'"':rest) = '"' : unescapeDefineValue rest
unescapeDefineValue (c:rest) = c : unescapeDefineValue rest

replaceExt :: String -> String -> String
-- Like a compiler's -c default, write in the working directory, not beside
-- the input. Only the filename's final extension is replaced; a leading dot
-- alone is part of the stem. Explicit -o paths are left untouched.
replaceExt path ext =
  let name = hccTakeFileName path
  in case break (== '.') (reverse name) of
    (_, '.':rest@(_:_)) -> reverse rest ++ ext
    _ -> name ++ ext

showPos :: SrcPos -> String
showPos (SrcPos line col) = show line ++ ":" ++ show col
