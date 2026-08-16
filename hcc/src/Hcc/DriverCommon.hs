module DriverCommon
  ( AsmOptions(..)
  , die
  , lexPlainSource
  , spliceContinuations
  , stripComments
  , stripLineComment
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

lexPlainSource :: String -> Either String [Token]
lexPlainSource source = case lexC (stripComments (spliceContinuations source)) of
  Left (LexError pos msg) -> Left (showPos pos ++ ": " ++ msg)
  Right toks -> Right toks

spliceContinuations :: String -> String
spliceContinuations [] = []
spliceContinuations ('\\':rest) =
  case continuationTail rest of
    Just rest' -> spliceContinuations rest'
    Nothing -> '\\' : spliceContinuations rest
spliceContinuations (c:rest) = c : spliceContinuations rest

continuationTail :: String -> Maybe String
continuationTail text = case text of
  '\n':rest -> Just rest
  '\x0d':'\n':rest -> Just rest
  c:rest | isContinuationSpace c -> continuationTail rest
  _ -> Nothing

isContinuationSpace :: Char -> Bool
isContinuationSpace c =
  c == ' ' || c == '\x09' || c == '\x0b' || c == '\x0c'

stripComments :: String -> String
stripComments = stripCommentNormal

stripCommentNormal :: String -> String
stripCommentNormal [] = []
stripCommentNormal ('/':'/':rest) = stripLineComment rest
stripCommentNormal ('/':'*':rest) = stripBlockComment rest
stripCommentNormal ('"':rest) = '"' : stripStringLiteral rest
stripCommentNormal ('\'':rest) = '\'' : stripCharLiteral rest
stripCommentNormal (c:rest) = c : stripCommentNormal rest

stripLineComment :: String -> String
stripLineComment [] = []
stripLineComment ('\n':rest) = '\n' : stripCommentNormal rest
stripLineComment (_:rest) = stripLineComment rest

stripBlockComment :: String -> String
stripBlockComment [] = []
stripBlockComment ('*':'/':rest) = ' ' : stripCommentNormal rest
stripBlockComment ('\n':rest) = '\n' : stripBlockComment rest
stripBlockComment (_:rest) = stripBlockComment rest

stripStringLiteral :: String -> String
stripStringLiteral = stripQuotedLiteral '"'

stripCharLiteral :: String -> String
stripCharLiteral = stripQuotedLiteral '\''

stripQuotedLiteral :: Char -> String -> String
stripQuotedLiteral _ [] = []
stripQuotedLiteral quote ('\\':c:rest) = '\\' : c : stripQuotedLiteral quote rest
stripQuotedLiteral quote (c:rest) =
  if c == quote
    then c : stripCommentNormal rest
    else c : stripQuotedLiteral quote rest

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
replaceExt path ext = reverse (takeWhile (/= '.') (reverse path)) ++ ext

showPos :: SrcPos -> String
showPos (SrcPos line col) = show line ++ ":" ++ show col
