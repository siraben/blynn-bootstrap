module DriverCommon where

import Base
import HccSystem
import Lexer hiding (charCode, isAsciiAlpha, isAsciiAlphaNum, isDigit, isHexDigit, isIdentChar, isIdentStart, lexerIsSpace)
import Token

die :: String -> IO ()
die msg = hccPutErrLine msg >> hccExitFailure

lexPlainSource :: String -> Either String [Token]
lexPlainSource source = case lexC (stripComments (spliceContinuations source)) of
  Left (LexError pos msg) -> Left (showPos pos ++ ": " ++ msg)
  Right toks -> Right toks

spliceContinuations :: String -> String
spliceContinuations source = case source of
  [] -> []
  '\\':c:'\n':rest ->
    if charCode c == 13
      then spliceContinuations rest
      else '\\' : c : '\n' : spliceContinuations rest
  '\\':'\n':rest -> spliceContinuations rest
  c:rest -> c : spliceContinuations rest

stripComments :: String -> String
stripComments source = normal source where
  normal text = case text of
    [] -> []
    '/':'/':rest -> lineComment rest
    '/':'*':rest -> blockComment 1 rest
    '"':rest -> '"' : stringLiteral rest
    '\'':rest -> '\'' : charLiteral rest
    c:rest -> c : normal rest

  lineComment text = case text of
    [] -> []
    '\n':rest -> '\n' : normal rest
    _:rest -> lineComment rest

  blockComment :: Int -> String -> String
  blockComment depth text = case text of
    [] -> []
    '/':'*':rest -> blockComment (depth + 1) rest
    '*':'/':rest ->
      if depth == 1
        then ' ' : normal rest
        else blockComment (depth - 1) rest
    '\n':rest -> '\n' : blockComment depth rest
    _:rest -> blockComment depth rest

  stringLiteral text = case text of
    [] -> []
    '\\':c:rest -> '\\' : c : stringLiteral rest
    '"':rest -> '"' : normal rest
    c:rest -> c : stringLiteral rest

  charLiteral text = case text of
    [] -> []
    '\\':c:rest -> '\\' : c : charLiteral rest
    '\'':rest -> '\'' : normal rest
    c:rest -> c : charLiteral rest

hccWriteAndFlushLines :: Int -> [String] -> IO ()
hccWriteAndFlushLines handle lines' = do
  hccWriteHandleLines handle lines'
  hccHandleFlush handle

dataLabelPrefix :: String -> String
dataLabelPrefix path =
  "HCC_DATA_" ++ sanitized
  where
    sanitized = case sanitizeLabel (hccTakeFileName path) of
      [] -> "unit"
      text -> text

sanitizeLabel :: String -> String
sanitizeLabel text = case text of
  [] -> []
  c:rest -> sanitizeChar c ++ sanitizeLabel rest
  where
    sanitizeChar c =
      if isAsciiAlphaNum c then [c] else "_"

isAsciiAlphaNum :: Char -> Bool
isAsciiAlphaNum c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

data AsmOptions = AsmOptions
  { asmInput :: String
  , asmOutput :: String
  , asmIncludeDirs :: [String]
  , asmDefines :: [(String, String)]
  }

assemblyArgs :: [String] -> Either String AsmOptions
assemblyArgs args = finish (go args Nothing Nothing [] []) where
  finish parsed = case parsed of
    Left msg -> Left msg
    Right (out, input, includes, defines) -> case input of
      Nothing -> Left "hcc: no input files"
      Just path -> Right (AsmOptions path (maybe (replaceExt path ".M1") id out) (reverse includes) (reverse defines))

  go rest out input includes defines = case rest of
    [] -> Right (out, input, includes, defines)
    "-S":xs -> go xs out input includes defines
    "-o":path:xs -> go xs (Just path) input includes defines
    "-I":path:xs -> go xs out input (path:includes) defines
    "-D":def:xs -> go xs out input includes (parseDefine def:defines)
    flag:xs | "-I" `prefixOf` flag && length flag > 2 ->
      go xs out input (drop 2 flag:includes) defines
    flag:xs | "-D" `prefixOf` flag && length flag > 2 ->
      go xs out input includes (parseDefine (drop 2 flag):defines)
    flag:xs | ignoredAssemblyFlag flag ->
      go xs out input includes defines
    flag:_ | take 1 flag == "-" -> Left ("hcc: unsupported option: " ++ flag)
    path:xs -> go xs out (Just path) includes defines

ignoredAssemblyFlag :: String -> Bool
ignoredAssemblyFlag flag =
  flag `elem` ["-c", "-pipe", "-nostdinc", "-nostdlib", "-static", "--tokens", "--ast-summary", "--ir-summary", "--m1-ir", "--trace"]

parseDefine :: String -> (String, String)
parseDefine def = case break (== '=') def of
  (name, "") -> (name, "1")
  (name, _:value) -> (name, unescapeDefineValue value)

unescapeDefineValue :: String -> String
unescapeDefineValue value = case value of
  [] -> []
  '\\':'"':rest -> '"' : unescapeDefineValue rest
  c:rest -> c : unescapeDefineValue rest

renderDefines :: [(String, String)] -> String
renderDefines defs = renderDefinesBuilder defs ""

renderDefinesBuilder :: [(String, String)] -> String -> String
renderDefinesBuilder defs = case defs of
  [] -> id
  (name, value):rest ->
    ("#define "++)
    . (name++)
    . (' ':)
    . (value++)
    . ('\n':)
    . renderDefinesBuilder rest

replaceExt :: String -> String -> String
replaceExt path ext = reverse (dropExt (reverse path)) ++ ext where
  dropExt xs = case xs of
    [] -> []
    '.':_ -> []
    c:rest -> c : dropExt rest

prefixOf :: String -> String -> Bool
prefixOf prefix text = take (length prefix) text == prefix

showPos :: SrcPos -> String
showPos (SrcPos line col) = show line ++ ":" ++ show col

charCode :: Char -> Int
charCode = fromEnum
