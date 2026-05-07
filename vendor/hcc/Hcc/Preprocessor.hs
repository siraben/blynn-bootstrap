module Hcc.Preprocessor
  ( PreprocessError(..)
  , preprocess
  ) where

import Data.Char (isAlpha, isAlphaNum, isDigit, isSpace)

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
    _ ->
      if currentActive frames
      then do
        (expanded, rest') <- expandNext macros False [] rest
        go macros frames rest' (reverse expanded ++ acc)
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

dropInactiveToken :: [Token] -> [Token]
dropInactiveToken toks = case toks of
  [] -> []
  _:xs -> xs

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

defineMacro :: [Macro] -> Span -> String -> Either PreprocessError [Macro]
defineMacro macros sp text =
  case parseMacroDefinition sp text of
    Left err -> Left err
    Right macro -> Right (macro : undefObject (macroName macro) macros)

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

expandNext :: [Macro] -> Bool -> [String] -> [Token] -> Either PreprocessError ([Token], [Token])
expandNext macros protectDefined disabled toks = case toks of
  [] -> Right ([], [])
  tok@(Token _ (TokIdent "defined")):xs | protectDefined ->
    let (protected, rest) = takeDefinedOperand xs
    in Right (tok:protected, rest)
  tok@(Token sp (TokIdent name)):xs ->
    if name `elem` disabled
    then Right ([tok], xs)
    else case lookupMacro name macros of
      Nothing -> Right ([tok], xs)
      Just macro -> expandMacro macros protectDefined disabled tok sp name macro xs
  tok:xs -> Right ([tok], xs)

expandTokens :: [Macro] -> Bool -> [String] -> [Token] -> Either PreprocessError [Token]
expandTokens macros protectDefined disabled toks = go toks [] where
  go rest acc = case rest of
    [] -> Right (reverse acc)
    _ -> do
      (expanded, rest') <- expandNext macros protectDefined disabled rest
      go rest' (reverse expanded ++ acc)

expandMacro :: [Macro] -> Bool -> [String] -> Token -> Span -> String -> Macro -> [Token] -> Either PreprocessError ([Token], [Token])
expandMacro macros protectDefined disabled original sp name macro rest = case macro of
  ObjectMacro _ body -> do
    let replacement = relocate sp body
    if replacement == [original]
      then Right ([original], rest)
      else Right ([], replacement ++ rest)
  FunctionMacro _ params variadic body -> case rest of
    Token _ (TokPunct "("):afterOpen -> do
      (args, rest') <- collectInvocationArgs sp afterOpen
      expanded <- expandFunctionMacro macros protectDefined disabled sp name params variadic body args
      Right (expanded, rest')
    _ -> Right ([original], rest)

takeDefinedOperand :: [Token] -> ([Token], [Token])
takeDefinedOperand toks = case toks of
  Token _ (TokPunct "("):Token _ (TokIdent _):Token _ (TokPunct ")"):rest ->
    (take 3 toks, rest)
  Token _ (TokIdent _):rest -> (take 1 toks, rest)
  _ -> ([], toks)

collectInvocationArgs :: Span -> [Token] -> Either PreprocessError ([[Token]], [Token])
collectInvocationArgs sp toks = go 1 [] [] toks where
  go :: Int -> [Token] -> [[Token]] -> [Token] -> Either PreprocessError ([[Token]], [Token])
  go depth current args rest = case rest of
    [] -> Left (PreprocessError (spanStart sp) "unterminated macro invocation")
    Token _ (TokPunct ")"):xs | depth == 1 ->
      let finalArgs = if null args && null current then [] else reverse (reverse current : args)
      in Right (finalArgs, xs)
    tok@(Token _ (TokPunct ")")):xs ->
      go (depth - 1) (tok:current) args xs
    tok@(Token _ (TokPunct "(")):xs ->
      go (depth + 1) (tok:current) args xs
    Token _ (TokPunct ","):xs | depth == 1 ->
      go depth [] (reverse current : args) xs
    tok:xs ->
      go depth (tok:current) args xs

expandFunctionMacro :: [Macro] -> Bool -> [String] -> Span -> String -> [String] -> Maybe String -> [Token] -> [[Token]] -> Either PreprocessError [Token]
expandFunctionMacro macros protectDefined disabled sp name params variadic body args = do
  argMap <- bindMacroArgs macros protectDefined sp params variadic args
  replaced <- substituteMacroBody sp argMap body
  expandTokens macros protectDefined (name:disabled) replaced

bindMacroArgs :: [Macro] -> Bool -> Span -> [String] -> Maybe String -> [[Token]] -> Either PreprocessError [(String, MacroArg)]
bindMacroArgs macros protectDefined sp params variadic args = do
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
      expanded <- expandTokens macros protectDefined [] raw
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

evalIf :: [Macro] -> String -> Either PreprocessError Bool
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

replaceDefinedOperators :: [Macro] -> [Token] -> Either PreprocessError [Token]
replaceDefinedOperators macros toks = go toks [] where
  go rest acc = case rest of
    [] -> Right (reverse acc)
    Token sp (TokIdent "defined"):Token _ (TokPunct "("):Token _ (TokIdent name):Token _ (TokPunct ")"):xs ->
      go xs (definedToken sp name:acc)
    Token sp (TokIdent "defined"):Token _ (TokIdent name):xs ->
      go xs (definedToken sp name:acc)
    Token sp (TokIdent "defined"):_ ->
      Left (PreprocessError (spanStart sp) "bad defined operator in #if expression")
    tok:xs ->
      go xs (tok:acc)

  definedToken sp name = Token sp (TokInt (if isDefined name macros then "1" else "0"))

stripLineComment :: String -> String
stripLineComment text = case text of
  [] -> []
  '/':'/':_ -> []
  c:rest -> c : stripLineComment rest

lookupMacro :: String -> [Macro] -> Maybe Macro
lookupMacro name macros = case macros of
  [] -> Nothing
  macro:rest ->
    if name == macroName macro then Just macro else lookupMacro name rest

macroName :: Macro -> String
macroName macro = case macro of
  ObjectMacro name _ -> name
  FunctionMacro name _ _ _ -> name

isDefined :: String -> [Macro] -> Bool
isDefined name macros = case lookupMacro name macros of
  Just _ -> True
  Nothing -> False

undefObject :: String -> [Macro] -> [Macro]
undefObject name macros = case macros of
  [] -> []
  macro:rest ->
    if name == macroName macro
    then undefObject name rest
    else macro : undefObject name rest

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
