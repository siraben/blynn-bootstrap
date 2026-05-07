module Hcc.Preprocessor
  ( PreprocessError(..)
  , preprocess
  ) where

import Data.Char (isAlpha, isAlphaNum, isDigit, isSpace)
import qualified Data.Map as Map

import Hcc.ConstExpr
import Hcc.Lexer
import Hcc.Token

data PreprocessError = PreprocessError SrcPos String
  deriving (Eq, Show)

data Macro
  = ObjectMacro String [Token]
  | FunctionMacro String [String] (Maybe String) [Token]
  deriving (Eq, Show)

data MacroArg = MacroArg
  { argRaw :: [Token]
  , argExpanded :: [Token]
  }
  deriving (Eq, Show)

type Macros = Map.Map String Macro
type Tokens = [Token] -> [Token]

data Chunk = Chunk [String] [Token]
  deriving (Eq, Show)

type Source = [Chunk]

data IfFrame = IfFrame
  { ifParentActive :: Bool
  , ifBranchTaken :: Bool
  , ifActive :: Bool
  }
  deriving (Eq, Show)

preprocess :: [Token] -> Either PreprocessError [Token]
preprocess toks = go Map.empty [] (sourceFromTokens toks) id where
  go macros frames rest acc = case rest of
    [] ->
      if null frames
      then Right (acc [])
      else Left (PreprocessError (SrcPos 1 1) "unterminated conditional directive")
    _ -> case popSource rest of
      Nothing ->
        if null frames
        then Right (acc [])
        else Left (PreprocessError (SrcPos 1 1) "unterminated conditional directive")
      Just (_, Token sp (TokDirective text), xs) -> handleDirective macros frames sp text xs acc
      Just _ ->
        if currentActive frames
        then do
          (expanded, rest') <- expandNextSource macros False [] rest
          go macros frames rest' (acc . tokens expanded)
        else go macros frames (dropInactiveToken rest) acc

  handleDirective macros frames sp text xs acc = case parseDirective text of
    Directive "define" rest ->
      if currentActive frames
      then defineMacro macros sp rest >>= \macros' -> go macros' frames xs acc
      else go macros frames xs acc
    Directive "undef" rest ->
      if currentActive frames
      then case directiveName rest of
        Just name -> go (undefObject name macros) frames xs acc
        Nothing -> Left (PreprocessError (spanStart sp) "#undef without macro name")
      else go macros frames xs acc
    Directive "include" _ ->
      go macros frames xs acc
    Directive "ifdef" rest ->
      case directiveName rest of
        Just name -> go macros (pushIf frames (isDefined name macros)) xs acc
        Nothing -> Left (PreprocessError (spanStart sp) "#ifdef without macro name")
    Directive "ifndef" rest ->
      case directiveName rest of
        Just name -> go macros (pushIf frames (not (isDefined name macros))) xs acc
        Nothing -> Left (PreprocessError (spanStart sp) "#ifndef without macro name")
    Directive "if" rest ->
      evalIf macros rest >>= \cond -> go macros (pushIf frames cond) xs acc
    Directive "elif" rest ->
      evalIf macros rest >>= \cond -> replaceElif sp frames cond >>= \frames' -> go macros frames' xs acc
    Directive "else" _ ->
      replaceElse sp frames >>= \frames' -> go macros frames' xs acc
    Directive "endif" _ ->
      popIf sp frames >>= \frames' -> go macros frames' xs acc
    Directive "" _ -> go macros frames xs acc
    Directive name _ | ("#" ++ name) `elem` ignoredDirectives -> go macros frames xs acc
    Directive name _ | all isDigit name -> go macros frames xs acc
    Directive name _ ->
      if currentActive frames
      then Left (PreprocessError (spanStart sp) ("unsupported directive: #" ++ name))
      else go macros frames xs acc

dropInactiveToken :: Source -> Source
dropInactiveToken toks = case toks of
  [] -> []
  Chunk _ []:xs -> dropInactiveToken xs
  Chunk hidden (_:xs):rest -> prependChunk hidden xs rest

data Directive = Directive String String
  deriving (Eq, Show)

parseDirective :: String -> Directive
parseDirective text = case dropSpaces text of
  '#':rest ->
    let rest' = dropSpaces rest
        (name, body) = span isDirectiveChar rest'
    in Directive name (dropSpaces body)
  _ -> Directive "" ""

isDirectiveChar :: Char -> Bool
isDirectiveChar c = isAlphaNum c || c == '_'

directiveName :: String -> Maybe String
directiveName text = case dropSpaces text of
  c:_ | isIdentStart c -> Just (takeWhile isIdentChar text)
  _ -> Nothing

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

defineMacro :: Macros -> Span -> String -> Either PreprocessError Macros
defineMacro macros sp text =
  case parseMacroDefinition sp text of
    Left err -> Left err
    Right macro -> Right (Map.insert (macroName macro) macro macros)

parseMacroDefinition :: Span -> String -> Either PreprocessError Macro
parseMacroDefinition sp text = case dropSpaces text of
  c:_ | isIdentStart c ->
    let (name, afterName) = span isIdentChar (dropSpaces text)
    in case afterName of
      '(':rest -> parseFunctionMacro sp name rest
      _ -> ObjectMacro name <$> lexReplacement sp afterName
  _ -> Left (PreprocessError (spanStart sp) "#define without macro name")

parseFunctionMacro :: Span -> String -> String -> Either PreprocessError Macro
parseFunctionMacro sp name text = do
  (paramText, bodyText) <- takeMacroParams sp text
  (params, variadic) <- parseMacroParams sp paramText
  body <- lexReplacement sp bodyText
  Right (FunctionMacro name params variadic body)

takeMacroParams :: Span -> String -> Either PreprocessError (String, String)
takeMacroParams sp text = go 1 [] text where
  go :: Int -> String -> String -> Either PreprocessError (String, String)
  go depth acc rest = case rest of
    [] -> Left (PreprocessError (spanStart sp) "unterminated macro parameter list")
    ')':xs | depth == 1 -> Right (reverse acc, xs)
    ')':xs -> go (depth - 1) (')':acc) xs
    '(':xs -> go (depth + 1) ('(':acc) xs
    c:xs -> go depth (c:acc) xs

parseMacroParams :: Span -> String -> Either PreprocessError ([String], Maybe String)
parseMacroParams sp text =
  let pieces = splitCommas text
      trimmed = filter (not . null) (map trim pieces)
  in parsePieces [] Nothing trimmed
  where
    parsePieces params variadic pieces = case pieces of
      [] -> Right (reverse params, variadic)
      piece:rest -> case rest of
        _ | piece == "..." -> parsePieces params (Just "__VA_ARGS__") rest
        _ | "..." `suffixOf` piece ->
          let name = trim (take (length piece - 3) piece)
          in if all isIdentChar name && not (null name)
             then parsePieces params (Just name) rest
             else Left (PreprocessError (spanStart sp) ("bad variadic macro parameter: " ++ piece))
        _ | all isIdentChar piece && not (null piece) ->
          parsePieces (piece:params) variadic rest
        _ -> Left (PreprocessError (spanStart sp) ("bad macro parameter: " ++ piece))

splitCommas :: String -> [String]
splitCommas text = go 0 [] [] text where
  go :: Int -> String -> [String] -> String -> [String]
  go depth current acc rest = case rest of
    [] -> reverse (reverse current : acc)
    ',':xs | depth == 0 -> go depth [] (reverse current : acc) xs
    '(':xs -> go (depth + 1) ('(':current) acc xs
    ')':xs -> go (max 0 (depth - 1)) (')':current) acc xs
    c:xs -> go depth (c:current) acc xs

lexReplacement :: Span -> String -> Either PreprocessError [Token]
lexReplacement sp text = case lexC ("__hcc_macro_dummy " ++ dropSpaces text) of
  Left (LexError _ msg) -> Left (PreprocessError (spanStart sp) msg)
  Right (_:toks) -> Right toks
  Right [] -> Right []

expandNextSource :: Macros -> Bool -> [String] -> Source -> Either PreprocessError ([Token], Source)
expandNextSource macros protectDefined disabled toks = case popSource toks of
  Nothing -> Right ([], [])
  Just (_, tok@(Token _ (TokIdent "defined")), xs) | protectDefined ->
    let (protected, rest) = takeDefinedOperandSource xs
    in Right (tok:protected, rest)
  Just (hidden, tok@(Token sp (TokIdent name)), xs) ->
    if name `elem` (hidden ++ disabled)
    then Right ([tok], xs)
    else case lookupMacro name macros of
      Nothing -> Right ([tok], xs)
      Just macro -> expandMacro macros protectDefined (hidden ++ disabled) tok sp name macro xs
  Just (_, tok, xs) -> Right ([tok], xs)

expandTokens :: Macros -> Bool -> [String] -> [Token] -> Either PreprocessError [Token]
expandTokens macros protectDefined disabled toks = go (sourceFromTokens toks) id where
  go rest acc = case rest of
    [] -> Right (acc [])
    _ -> do
      (expanded, rest') <- expandNextSource macros protectDefined disabled rest
      go rest' (acc . tokens expanded)

expandMacro :: Macros -> Bool -> [String] -> Token -> Span -> String -> Macro -> Source -> Either PreprocessError ([Token], Source)
expandMacro macros protectDefined disabled original sp name macro rest = case macro of
  ObjectMacro _ body -> do
    let replacement = relocate sp body
    if replacement == [original]
      then Right ([original], rest)
      else Right ([], prependChunk [name] replacement rest)
  FunctionMacro _ params variadic body -> case popSource rest of
    Just (_, Token _ (TokPunct "("), afterOpen) -> do
      (args, rest') <- collectInvocationArgs sp afterOpen
      expanded <- expandFunctionMacro macros protectDefined disabled sp name params variadic body args
      Right (expanded, rest')
    _ -> Right ([original], rest)

takeDefinedOperandSource :: Source -> ([Token], Source)
takeDefinedOperandSource toks = case popSource toks of
  Just (_, open@(Token _ (TokPunct "(")), afterOpen) ->
    case popSource afterOpen of
      Just (_, name@(Token _ (TokIdent _)), afterName) ->
        case popSource afterName of
          Just (_, close@(Token _ (TokPunct ")")), rest) -> ([open, name, close], rest)
          _ -> ([], toks)
      _ -> ([], toks)
  Just (_, name@(Token _ (TokIdent _)), rest) -> ([name], rest)
  _ -> ([], toks)

collectInvocationArgs :: Span -> Source -> Either PreprocessError ([[Token]], Source)
collectInvocationArgs sp toks = go 1 [] [] toks where
  go :: Int -> [Token] -> [[Token]] -> Source -> Either PreprocessError ([[Token]], Source)
  go depth current args rest = case popSource rest of
    Nothing -> Left (PreprocessError (spanStart sp) "unterminated macro invocation")
    Just (_, Token _ (TokPunct ")"), xs) | depth == 1 ->
      let finalArgs = if null args && null current then [] else reverse (reverse current : args)
      in Right (finalArgs, xs)
    Just (_, tok@(Token _ (TokPunct ")")), xs) ->
      go (depth - 1) (tok:current) args xs
    Just (_, tok@(Token _ (TokPunct "(")), xs) ->
      go (depth + 1) (tok:current) args xs
    Just (_, Token _ (TokPunct ","), xs) | depth == 1 ->
      go depth [] (reverse current : args) xs
    Just (_, tok, xs) ->
      go depth (tok:current) args xs

expandFunctionMacro :: Macros -> Bool -> [String] -> Span -> String -> [String] -> Maybe String -> [Token] -> [[Token]] -> Either PreprocessError [Token]
expandFunctionMacro macros protectDefined disabled sp name params variadic body args = do
  argMap <- bindMacroArgs macros protectDefined disabled sp params variadic args
  replaced <- substituteMacroBody sp argMap body
  let argHidden = concatMap (argumentMacroNames macros . argRaw . snd) argMap
  expandTokens macros protectDefined (name:argHidden ++ disabled) replaced

argumentMacroNames :: Macros -> [Token] -> [String]
argumentMacroNames macros toks = case toks of
  [] -> []
  Token _ (TokIdent name):rest ->
    if isDefined name macros
    then name : argumentMacroNames macros rest
    else argumentMacroNames macros rest
  _:rest -> argumentMacroNames macros rest

bindMacroArgs :: Macros -> Bool -> [String] -> Span -> [String] -> Maybe String -> [[Token]] -> Either PreprocessError [(String, MacroArg)]
bindMacroArgs macros protectDefined disabled sp params variadic args = do
  let fixedCount = length params
  if length args < fixedCount || (variadic == Nothing && length args /= fixedCount)
    then Left (PreprocessError (spanStart sp) "wrong number of macro arguments")
    else do
      fixed <- bindFixed params (take fixedCount args)
      variadicBinding <- case variadic of
        Nothing -> Right []
        Just name -> do
          let restArgs = drop fixedCount args
          arg <- makeArg (joinVariadicArgs sp restArgs)
          Right [(name, arg)]
      Right (fixed ++ variadicBinding)
  where
    bindFixed ps as = case (ps, as) of
      ([], []) -> Right []
      (p:ps', a:as') -> do
        arg <- makeArg a
        rest <- bindFixed ps' as'
        Right ((p, arg):rest)
      _ -> Left (PreprocessError (spanStart sp) "wrong number of macro arguments")

    makeArg raw = do
      expanded <- expandTokens macros protectDefined disabled raw
      Right (MacroArg raw expanded)

joinVariadicArgs :: Span -> [[Token]] -> [Token]
joinVariadicArgs sp args = case args of
  [] -> []
  first:rest -> first ++ concatMap ((commaToken sp :) . id) rest

commaToken :: Span -> Token
commaToken sp = Token sp (TokPunct ",")

substituteMacroBody :: Span -> [(String, MacroArg)] -> [Token] -> Either PreprocessError [Token]
substituteMacroBody sp args body = go body [] where
  go rest acc = case rest of
    [] -> Right (reverse acc)
    Token _ (TokPunct "#"):Token argSp (TokIdent name):xs
      | Just arg <- lookup name args ->
          go xs (Token argSp (TokString (stringifyTokens (argRaw arg))) : acc)
    Token pasteSp (TokPunct "##"):xs ->
      case acc of
        [] -> pasteWithPrevious pasteSp [] xs acc
        previous:before -> pasteWithPrevious pasteSp [previous] xs before
    Token _ (TokIdent name):xs
      | Just arg <- lookup name args ->
          go xs (reverse (argExpanded arg) ++ acc)
    tok:xs ->
      go xs (tok:acc)

  pasteWithPrevious pasteSp previous xs before = do
    (next, rest') <- nextPasteOperand xs
    case (previous, next) of
      ([Token _ (TokPunct ",")], []) ->
        go rest' before
      ([comma@(Token _ (TokPunct ","))], _) ->
        go rest' (reverse next ++ comma:before)
      (_, []) ->
        go rest' (reverse previous ++ before)
      ([], _) ->
        go rest' (reverse next ++ before)
      ([prev], n:ns) -> do
        pasted <- pasteTokens pasteSp prev n
        go rest' (reverse ns ++ pasted:before)
      _ ->
        Left (PreprocessError (spanStart sp) "invalid token paste")

  nextPasteOperand xs = case xs of
    Token _ (TokIdent name):rest
      | Just arg <- lookup name args -> Right (argRaw arg, rest)
    tok:rest -> Right ([tok], rest)
    [] -> Right ([], [])

pasteTokens :: Span -> Token -> Token -> Either PreprocessError Token
pasteTokens sp left right =
  case lexC (tokenText (tokenKind left) ++ tokenText (tokenKind right)) of
    Right [Token _ kind] -> Right (Token sp kind)
    Right _ -> Left (PreprocessError (spanStart sp) "token paste did not form one token")
    Left (LexError _ msg) -> Left (PreprocessError (spanStart sp) msg)

stringifyTokens :: [Token] -> String
stringifyTokens toks = "\"" ++ escapeString (unwords (map (tokenText . tokenKind) toks)) ++ "\""

escapeString :: String -> String
escapeString text = case text of
  [] -> []
  '\\':xs -> '\\':'\\':escapeString xs
  '"':xs -> '\\':'"':escapeString xs
  c:xs -> c : escapeString xs

evalIf :: Macros -> String -> Either PreprocessError Bool
evalIf macros text = do
  toks <- case lexC (stripLineComment text) of
    Left (LexError pos msg) -> Left (PreprocessError pos msg)
    Right result -> Right result
  replaced <- replaceDefinedOperators macros toks
  expanded <- expandTokens macros False [] replaced
  case parseConstExpr [] expanded of
    Right (value, []) -> Right (value /= 0)
    Right (_, tok:_) -> Left (PreprocessError (tokenStart tok) ("trailing tokens in #if expression near " ++ show (tokenText (tokenKind tok))))
    Left msg -> Left (PreprocessError (SrcPos 1 1) msg)

replaceDefinedOperators :: Macros -> [Token] -> Either PreprocessError [Token]
replaceDefinedOperators macros toks = go toks id where
  go rest acc = case rest of
    [] -> Right (acc [])
    Token sp (TokIdent "defined"):Token _ (TokPunct "("):Token _ (TokIdent name):Token _ (TokPunct ")"):xs ->
      go xs (acc . token (definedToken sp name))
    Token sp (TokIdent "defined"):Token _ (TokIdent name):xs ->
      go xs (acc . token (definedToken sp name))
    Token sp (TokIdent "defined"):_ ->
      Left (PreprocessError (spanStart sp) "bad defined operator in #if expression")
    tok:xs ->
      go xs (acc . token tok)

  definedToken sp name = Token sp (TokInt (if isDefined name macros then "1" else "0"))

tokens :: [Token] -> Tokens
tokens xs = (xs ++)

token :: Token -> Tokens
token x = (x :)

sourceFromTokens :: [Token] -> Source
sourceFromTokens toks =
  if null toks then [] else [Chunk [] toks]

prependChunk :: [String] -> [Token] -> Source -> Source
prependChunk hidden toks source =
  if null toks then source else Chunk hidden toks : source

popSource :: Source -> Maybe ([String], Token, Source)
popSource source = case source of
  [] -> Nothing
  Chunk _ []:rest -> popSource rest
  Chunk hidden (tok:toks):rest -> Just (hidden, tok, prependChunk hidden toks rest)

stripLineComment :: String -> String
stripLineComment text = case text of
  [] -> []
  '/':'/':_ -> []
  c:rest -> c : stripLineComment rest

lookupMacro :: String -> Macros -> Maybe Macro
lookupMacro = Map.lookup

macroName :: Macro -> String
macroName macro = case macro of
  ObjectMacro name _ -> name
  FunctionMacro name _ _ _ -> name

isDefined :: String -> Macros -> Bool
isDefined = Map.member

undefObject :: String -> Macros -> Macros
undefObject = Map.delete

relocate :: Span -> [Token] -> [Token]
relocate sp toks = map replaceSpan toks where
  replaceSpan (Token _ kind) = Token sp kind

spanStart :: Span -> SrcPos
spanStart (Span start _) = start

tokenStart :: Token -> SrcPos
tokenStart (Token sp _) = spanStart sp

tokenKind :: Token -> TokenKind
tokenKind (Token _ kind) = kind

dropSpaces :: String -> String
dropSpaces = dropWhile isSpace

trim :: String -> String
trim = reverse . dropSpaces . reverse . dropSpaces

suffixOf :: String -> String -> Bool
suffixOf suffix text = reverse suffix `prefixOf` reverse text

prefixOf :: String -> String -> Bool
prefixOf prefix text = take (length prefix) text == prefix

isIdentStart :: Char -> Bool
isIdentStart c = isAlpha c || c == '_'

isIdentChar :: Char -> Bool
isIdentChar c = isAlphaNum c || c == '_'
