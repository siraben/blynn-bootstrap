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
spliceContinuations ('\\':c:'\n':rest) =
  if charCode c == 13
    then spliceContinuations rest
    else '\\' : c : '\n' : spliceContinuations rest
spliceContinuations ('\\':'\n':rest) = spliceContinuations rest
spliceContinuations (c:rest) = c : spliceContinuations rest

stripComments :: String -> String
stripComments = stripCommentNormal

stripCommentNormal :: String -> String
stripCommentNormal [] = []
stripCommentNormal ('/':'/':rest) = stripLineComment rest
stripCommentNormal ('/':'*':rest) = stripBlockComment 1 rest
stripCommentNormal ('"':rest) = '"' : stripStringLiteral rest
stripCommentNormal ('\'':rest) = '\'' : stripCharLiteral rest
stripCommentNormal (c:rest) = c : stripCommentNormal rest

stripLineComment :: String -> String
stripLineComment [] = []
stripLineComment ('\n':rest) = '\n' : stripCommentNormal rest
stripLineComment (_:rest) = stripLineComment rest

stripBlockComment :: Int -> String -> String
stripBlockComment _ [] = []
stripBlockComment depth ('/':'*':rest) = stripBlockComment (depth + 1) rest
stripBlockComment depth ('*':'/':rest) =
  if depth == 1
    then ' ' : stripCommentNormal rest
    else stripBlockComment (depth - 1) rest
stripBlockComment depth ('\n':rest) = '\n' : stripBlockComment depth rest
stripBlockComment depth (_:rest) = stripBlockComment depth rest

stripStringLiteral :: String -> String
stripStringLiteral [] = []
stripStringLiteral ('\\':c:rest) = '\\' : c : stripStringLiteral rest
stripStringLiteral ('"':rest) = '"' : stripCommentNormal rest
stripStringLiteral (c:rest) = c : stripStringLiteral rest

stripCharLiteral :: String -> String
stripCharLiteral [] = []
stripCharLiteral ('\\':c:rest) = '\\' : c : stripCharLiteral rest
stripCharLiteral ('\'':rest) = '\'' : stripCommentNormal rest
stripCharLiteral (c:rest) = c : stripCharLiteral rest

dataLabelPrefix :: String -> String
dataLabelPrefix path =
  "HCC_DATA_" ++ sanitized
  where
    sanitized = case sanitizeLabel (hccTakeFileName path) of
      [] -> "unit"
      text -> text

sanitizeLabel :: String -> String
sanitizeLabel [] = []
sanitizeLabel (c:rest) = sanitizeLabelChar c ++ sanitizeLabel rest

sanitizeLabelChar :: Char -> String
sanitizeLabelChar c =
  if isAsciiAlphaNum c then [c] else "_"

data AsmOptions = AsmOptions
  { asmInput :: String
  , asmOutput :: String
  , asmIncludeDirs :: [String]
  , asmDefines :: [(String, String)]
  , asmTargetBits :: Int
  }

assemblyArgs :: [String] -> Either String AsmOptions
assemblyArgs args = finish (go args Nothing Nothing [] [] 64)
  where
    finish (Left msg) = Left msg
    finish (Right (_, Nothing, _, _, _)) = Left "hcc: no input files"
    finish (Right (out, Just path, includes, defines, target)) =
      Right (AsmOptions path (maybe (replaceExt path ".hccir") id out) (reverse includes) (reverse defines) target)

    go [] out input includes defines target =
      Right (out, input, includes, defines, target)
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
    go (flag:xs) out input includes defines target
      | "-I" `prefixOf` flag && length flag > 2 =
          go xs out input (drop 2 flag:includes) defines target
      | "-D" `prefixOf` flag && length flag > 2 =
          go xs out input includes (parseDefine (drop 2 flag):defines) target
      | ignoredAssemblyFlag flag =
          go xs out input includes defines target
      | take 1 flag == "-" =
          Left ("hcc: unsupported option: " ++ flag)
      | otherwise =
          go xs out (Just flag) includes defines target

parseTargetBits :: String -> Maybe Int
parseTargetBits target = case target of
  "amd64" -> Just 64
  "x86_64" -> Just 64
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
replaceExt path ext = reverse (dropExt (reverse path)) ++ ext where
  dropExt xs = case xs of
    [] -> []
    '.':_ -> []
    c:rest -> c : dropExt rest

showPos :: SrcPos -> String
showPos (SrcPos line col) = show line ++ ":" ++ show col
