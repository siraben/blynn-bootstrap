module Hcc.Preprocessor
  ( PreprocessError(..)
  , preprocess
  ) where

import Data.Char (isSpace)

import Hcc.Lexer
import Hcc.Token

data PreprocessError = PreprocessError SrcPos String
  deriving (Eq, Show)

data Macro = ObjectMacro String [Token]
  deriving (Eq, Show)

preprocess :: [Token] -> Either PreprocessError [Token]
preprocess toks = go [] toks [] where
  go macros rest acc = case rest of
    [] -> Right (reverse acc)
    Token sp (TokDirective text):xs -> handleDirective macros sp text xs acc
    Token sp (TokIdent name):xs -> case lookupObject name macros of
      Just body -> go macros xs (reverse (relocate sp body) ++ acc)
      Nothing -> go macros xs (Token sp (TokIdent name):acc)
    x:xs -> go macros xs (x:acc)

  handleDirective macros sp text xs acc = case directiveWords text of
    "#define":name:body ->
      defineObject macros sp name (unwords body) >>= \macros' -> go macros' xs acc
    "#undef":name:_ -> go (undefObject name macros) xs acc
    "#":_ -> go macros xs acc
    [] -> go macros xs acc
    word:_ | word `elem` ignoredDirectives -> go macros xs acc
    word:_ -> Left (PreprocessError (spanStart sp) ("unsupported directive: " ++ word))

ignoredDirectives :: [String]
ignoredDirectives = ["#line", "#pragma"]

defineObject :: [Macro] -> Span -> String -> String -> Either PreprocessError [Macro]
defineObject macros sp name body =
  case lexC body of
    Left (LexError _ msg) -> Left (PreprocessError (spanStart sp) msg)
    Right toks -> Right (ObjectMacro name toks : undefObject name macros)

lookupObject :: String -> [Macro] -> Maybe [Token]
lookupObject name macros = case macros of
  [] -> Nothing
  ObjectMacro macroName body:rest ->
    if name == macroName then Just body else lookupObject name rest

undefObject :: String -> [Macro] -> [Macro]
undefObject name macros = case macros of
  [] -> []
  ObjectMacro macroName body:rest ->
    if name == macroName
    then undefObject name rest
    else ObjectMacro macroName body : undefObject name rest

directiveWords :: String -> [String]
directiveWords text = words (trim text)

trim :: String -> String
trim = dropWhile isSpace

relocate :: Span -> [Token] -> [Token]
relocate sp toks = map replaceSpan toks where
  replaceSpan (Token _ kind) = Token sp kind

spanStart :: Span -> SrcPos
spanStart (Span start _) = start
