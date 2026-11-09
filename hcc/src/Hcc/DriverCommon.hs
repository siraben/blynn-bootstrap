module DriverCommon
  ( AsmOptions(..)
  , die
  , lexPlainSource
  , normalizeSource
  , lexNormalizedSource
  , dataLabelPrefix
  , assemblyArgs
  , renderDefines
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
spliceContinuations [] = []
spliceContinuations ('\\':c:'\n':rest) =
  if fromEnum c == 13
    then spliceContinuations rest
    else '\\' : c : '\n' : spliceContinuations rest
spliceContinuations ('\\':'\n':rest) = spliceContinuations rest
spliceContinuations (c:rest) = c : spliceContinuations rest

-- Keep comment columns/newlines as whitespace: macro adjacency and diagnostics
-- must not depend on the length of a removed comment. Positions are post-splice.
normalizeSource :: String -> Either String String
normalizeSource source = normal (SrcPos 1 1) (spliceContinuations source)
  where
  next (SrcPos line col) c = if c == '\n' then SrcPos (line + 1) 1 else SrcPos line (col + 1)
  normal pos text = case text of
    [] -> Right []
    '/':'/':rest -> ("  " ++) <$> lineComment (next (next pos '/') '/') rest
    '/':'*':rest -> ("  " ++) <$> blockComment pos (next (next pos '/') '*') rest
    '"':rest -> ('"':) <$> quoted '"' (next pos '"') rest
    '\'':rest -> ('\'':) <$> quoted '\'' (next pos '\'') rest
    c:rest -> (c:) <$> normal (next pos c) rest
  lineComment pos text = case text of
    [] -> Right []
    '\n':rest -> ('\n':) <$> normal (next pos '\n') rest
    c:rest -> (' ':) <$> lineComment (next pos c) rest
  blockComment start pos text = case text of
    [] -> Left (showPos start ++ ": unterminated block comment")
    '*':'/':rest -> ("  " ++) <$> normal (next (next pos '*') '/') rest
    c:rest -> ((if c == '\n' then '\n' else ' '):) <$> blockComment start (next pos c) rest
  quoted quote pos text = case text of
    [] -> Right []
    '\\':c:rest -> ('\\':) . (c:) <$> quoted quote (next (next pos '\\') c) rest
    c:rest -> (c:) <$> (if c == quote then normal else quoted quote) (next pos c) rest

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

data AsmOptions = AsmOptions
  { asmInput :: String
  , asmOutput :: String
  , asmIncludeDirs :: [String]
  , asmDefines :: [(String, String)]
  , asmTargetBits :: Int
  , asmTrace :: Bool
  }

assemblyArgs :: [String] -> Either String AsmOptions
assemblyArgs args = finish (go args Nothing Nothing [] [] 64)
  where
    finish (Left msg) = Left msg
    finish (Right (_, Nothing, _, _, _)) = Left "hcc: no input files"
    finish (Right (out, Just path, includes, defines, target)) =
      Right (AsmOptions path (maybe (replaceExt path ".hccir") id out) (reverse includes) (reverse defines) target ("--trace" `elem` args))

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
        | ignoredAssemblyFlag flag ->
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

ignoredAssemblyFlag :: String -> Bool
ignoredAssemblyFlag flag =
  flag `elem` ["-c", "-pipe", "-nostdinc", "-nostdlib", "-static", "--m1-ir", "--trace"]

parseDefine :: String -> (String, String)
parseDefine def = case break (== '=') def of
  (name, "") -> (name, "1")
  (name, _:value) -> (name, unescapeDefineValue value)

unescapeDefineValue :: String -> String
unescapeDefineValue [] = []
unescapeDefineValue ('\\':'"':rest) = '"' : unescapeDefineValue rest
unescapeDefineValue (c:rest) = c : unescapeDefineValue rest

renderDefines :: [(String, String)] -> String
renderDefines defs = go defs ""
  where
    go rest = case rest of
      [] -> id
      (name, value):rest' ->
        ("#define "++)
        . (name++)
        . (' ':)
        . (value++)
        . ('\n':)
        . go rest'

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
