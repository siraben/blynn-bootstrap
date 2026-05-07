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
    "#include":_ ->
      go macros frames xs acc
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
evalIf macros wordsAfterIf = do
  toks <- case lexC (stripLineComment (unwords wordsAfterIf)) of
    Left (LexError pos msg) -> Left (PreprocessError pos msg)
    Right result -> Right result
  case parseIfOr macros toks of
    Right (value, []) -> Right value
    Right (_, tok:_) -> Left (PreprocessError (tokenStart tok) "trailing tokens in #if expression")
    Left msg -> Left (PreprocessError (SrcPos 1 1) msg)

parseIfOr :: [Macro] -> [Token] -> Either String (Bool, [Token])
parseIfOr macros toks = do
  (lhs, rest) <- parseIfAnd macros toks
  parseTail lhs rest
  where
    parseTail lhs rest = case rest of
      Token _ (TokPunct "||"):xs -> do
        (rhs, xs') <- parseIfAnd macros xs
        parseTail (lhs || rhs) xs'
      _ -> Right (lhs, rest)

parseIfAnd :: [Macro] -> [Token] -> Either String (Bool, [Token])
parseIfAnd macros toks = do
  (lhs, rest) <- parseIfEq macros toks
  parseTail lhs rest
  where
    parseTail lhs rest = case rest of
      Token _ (TokPunct "&&"):xs -> do
        (rhs, xs') <- parseIfEq macros xs
        parseTail (lhs && rhs) xs'
      _ -> Right (lhs, rest)

parseIfEq :: [Macro] -> [Token] -> Either String (Bool, [Token])
parseIfEq macros toks = do
  (lhs, rest) <- parseIfRel macros toks
  case rest of
    Token _ (TokPunct "=="):xs -> do
      (rhs, xs') <- parseIfRel macros xs
      Right (lhs == rhs, xs')
    Token _ (TokPunct "!="):xs -> do
      (rhs, xs') <- parseIfRel macros xs
      Right (lhs /= rhs, xs')
    _ -> Right (lhs, rest)

parseIfRel :: [Macro] -> [Token] -> Either String (Bool, [Token])
parseIfRel macros toks = do
  (lhs, rest) <- parseIfUnary macros toks
  case rest of
    Token _ (TokPunct "<"):xs -> rel (<) lhs xs
    Token _ (TokPunct "<="):xs -> rel (<=) lhs xs
    Token _ (TokPunct ">"):xs -> rel (>) lhs xs
    Token _ (TokPunct ">="):xs -> rel (>=) lhs xs
    _ -> Right (lhs, rest)
  where
    rel op lhs xs = do
      (rhs, xs') <- parseIfUnary macros xs
      Right (boolInt lhs `op` boolInt rhs, xs')

boolInt :: Bool -> Int
boolInt value = if value then 1 else 0

parseIfUnary :: [Macro] -> [Token] -> Either String (Bool, [Token])
parseIfUnary macros toks = case toks of
  Token _ (TokPunct "!"):rest -> do
    (value, rest') <- parseIfUnary macros rest
    Right (not value, rest')
  _ -> parseIfPrimary macros toks

parseIfPrimary :: [Macro] -> [Token] -> Either String (Bool, [Token])
parseIfPrimary macros toks = case toks of
  Token _ (TokPunct "("):rest -> do
    (value, rest') <- parseIfOr macros rest
    case rest' of
      Token _ (TokPunct ")"):xs -> Right (value, xs)
      _ -> Left "expected ')' in #if expression"
  Token _ (TokIdent "defined"):Token _ (TokPunct "("):Token _ (TokIdent name):Token _ (TokPunct ")"):rest ->
    Right (isDefined name macros, rest)
  Token _ (TokIdent "defined"):Token _ (TokIdent name):rest ->
    Right (isDefined name macros, rest)
  Token _ (TokIdent name):rest ->
    Right (macroTruth name macros, rest)
  Token _ (TokInt value):rest ->
    Right (intTruth value, rest)
  [] -> Left "empty #if expression"
  _ -> Left "unsupported token in #if expression"

macroTruth :: String -> [Macro] -> Bool
macroTruth name macros = case lookupObject name macros of
  Just [Token _ (TokInt value)] -> intTruth value
  Just _ -> True
  Nothing -> False

intTruth :: String -> Bool
intTruth value = stripIntSuffix value /= "0"

stripIntSuffix :: String -> String
stripIntSuffix text = reverse (dropWhile isSuffix (reverse text)) where
  isSuffix c = c `elem` "uUlL"

stripLineComment :: String -> String
stripLineComment text = case text of
  [] -> []
  '/':'/':_ -> []
  c:rest -> c : stripLineComment rest

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

tokenStart :: Token -> SrcPos
tokenStart (Token sp _) = spanStart sp
