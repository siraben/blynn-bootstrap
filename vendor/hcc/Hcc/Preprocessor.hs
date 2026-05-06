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

data IfFrame = IfFrame
  { ifParentActive :: Bool
  , ifBranchTaken :: Bool
  , ifActive :: Bool
  }
  deriving (Eq, Show)

preprocess :: [Token] -> Either PreprocessError [Token]
preprocess toks = go [] [] toks [] where
  go macros frames rest acc = case rest of
    [] ->
      if null frames
      then Right (reverse acc)
      else Left (PreprocessError (SrcPos 1 1) "unterminated conditional directive")
    Token sp (TokDirective text):xs -> handleDirective macros frames sp text xs acc
    Token sp (TokIdent name):xs ->
      if currentActive frames
      then case lookupObject name macros of
        Just body -> go macros frames xs (reverse (relocate sp body) ++ acc)
        Nothing -> go macros frames xs (Token sp (TokIdent name):acc)
      else go macros frames xs acc
    x:xs ->
      if currentActive frames
      then go macros frames xs (x:acc)
      else go macros frames xs acc

  handleDirective macros frames sp text xs acc = case directiveWords text of
    "#define":name:body ->
      if currentActive frames
      then defineObject macros sp name (unwords body) >>= \macros' -> go macros' frames xs acc
      else go macros frames xs acc
    "#undef":name:_ ->
      if currentActive frames
      then go (undefObject name macros) frames xs acc
      else go macros frames xs acc
    "#ifdef":name:_ ->
      go macros (pushIf frames (isDefined name macros)) xs acc
    "#ifndef":name:_ ->
      go macros (pushIf frames (not (isDefined name macros))) xs acc
    "#if":expr ->
      evalIf macros expr >>= \cond -> go macros (pushIf frames cond) xs acc
    "#elif":expr ->
      evalIf macros expr >>= \cond -> replaceElif sp frames cond >>= \frames' -> go macros frames' xs acc
    "#else":_ ->
      replaceElse sp frames >>= \frames' -> go macros frames' xs acc
    "#endif":_ ->
      popIf sp frames >>= \frames' -> go macros frames' xs acc
    "#":_ -> go macros frames xs acc
    [] -> go macros frames xs acc
    word:_ | word `elem` ignoredDirectives -> go macros frames xs acc
    word:_ ->
      if currentActive frames
      then Left (PreprocessError (spanStart sp) ("unsupported directive: " ++ word))
      else go macros frames xs acc

ignoredDirectives :: [String]
ignoredDirectives = ["#line", "#pragma"]

currentActive :: [IfFrame] -> Bool
currentActive frames = case frames of
  [] -> True
  frame:_ -> ifActive frame

pushIf :: [IfFrame] -> Bool -> [IfFrame]
pushIf frames cond = IfFrame parent cond (parent && cond) : frames where
  parent = currentActive frames

replaceElse :: Span -> [IfFrame] -> Either PreprocessError [IfFrame]
replaceElse sp frames = case frames of
  [] -> Left (PreprocessError (spanStart sp) "#else without #if")
  IfFrame parent taken _:rest ->
    Right (IfFrame parent True (parent && not taken) : rest)

replaceElif :: Span -> [IfFrame] -> Bool -> Either PreprocessError [IfFrame]
replaceElif sp frames cond = case frames of
  [] -> Left (PreprocessError (spanStart sp) "#elif without #if")
  IfFrame parent taken _:rest ->
    Right (IfFrame parent (taken || cond) (parent && not taken && cond) : rest)

popIf :: Span -> [IfFrame] -> Either PreprocessError [IfFrame]
popIf sp frames = case frames of
  [] -> Left (PreprocessError (spanStart sp) "#endif without #if")
  _:rest -> Right rest

evalIf :: [Macro] -> [String] -> Either PreprocessError Bool
evalIf macros wordsAfterIf = case wordsAfterIf of
  ["0"] -> Right False
  ["1"] -> Right True
  ["defined", name] -> Right (isDefined name macros)
  [word] | "defined(" `startsWith` word && last word == ')' ->
    Right (isDefined (take (length word - 9) (drop 8 word)) macros)
  [name] -> case lookupObject name macros of
    Just [Token _ (TokInt "0")] -> Right False
    Just _ -> Right True
    Nothing -> Right False
  _ -> Left (PreprocessError (SrcPos 1 1) ("unsupported #if expression: " ++ unwords wordsAfterIf))

startsWith :: String -> String -> Bool
startsWith prefix text = take (length prefix) text == prefix

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

isDefined :: String -> [Macro] -> Bool
isDefined name macros = case lookupObject name macros of
  Just _ -> True
  Nothing -> False

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
