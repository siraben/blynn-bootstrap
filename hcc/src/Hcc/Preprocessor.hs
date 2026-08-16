module Preprocessor
  ( PreprocessError(..)
  , preprocess
  ) where

import Base
import ConstExpr
import Directive
import IfFrame
import Lexer
import SymbolTable
import TextUtil
import TypesToken

data PreprocessError = PreprocessError SrcPos String

data Macro
  = ObjectMacro String [Token]
  | FunctionMacro String [String] (Maybe String) [Token]

data MacroArg = MacroArg
  { argRaw :: [Token]
  , argExpanded :: [Chunk]
  }

type Macros = SymbolMap Macro

type MacroArgs = SymbolMap MacroArg

data Chunk = Chunk [String] [Token]

preprocess :: [Token] -> Either PreprocessError [Token]
preprocess toks = go symbolMapEmpty [] (sourceFromTokens toks) id where
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
        if ifStackActive frames
        then do
          (expanded, rest') <- expandNextSource macros False [] rest
          go macros frames rest' (acc . (expanded ++))
        else go macros frames (dropInactiveToken rest) acc

  handleDirective macros frames sp text xs acc = case parseDirective text of
    Directive "define" rest ->
      if ifStackActive frames
      then defineMacro macros sp rest >>= \macros' -> go macros' frames xs acc
      else go macros frames xs acc
    Directive "undef" rest ->
      if ifStackActive frames
      then case directiveName rest of
        Just name -> go (symbolMapDelete name macros) frames xs acc
        Nothing -> Left (PreprocessError (spanStart sp) "#undef without macro name")
      else go macros frames xs acc
    Directive "include" _ ->
      go macros frames xs acc
    Directive "ifdef" rest ->
      case directiveName rest of
        Just name -> go macros (startIf frames (symbolMapMember name macros)) xs acc
        Nothing -> Left (PreprocessError (spanStart sp) "#ifdef without macro name")
    Directive "ifndef" rest ->
      case directiveName rest of
        Just name -> go macros (startIf frames (not (symbolMapMember name macros))) xs acc
        Nothing -> Left (PreprocessError (spanStart sp) "#ifndef without macro name")
    Directive "if" rest ->
      evalIf macros sp rest >>= \cond -> go macros (startIf frames cond) xs acc
    Directive "elif" rest ->
      evalIf macros sp rest >>= \cond -> replaceElif sp frames cond >>= \frames' -> go macros frames' xs acc
    Directive "else" _ ->
      replaceElse sp frames >>= \frames' -> go macros frames' xs acc
    Directive "endif" _ ->
      popIf sp frames >>= \frames' -> go macros frames' xs acc
    Directive "" _ -> go macros frames xs acc
    Directive name _ | ("#" ++ name) `elem` ignoredDirectives -> go macros frames xs acc
    Directive name _ | all isDigitChar name -> go macros frames xs acc
    Directive name _ ->
      if ifStackActive frames
      then Left (PreprocessError (spanStart sp) ("unsupported directive: #" ++ name))
      else go macros frames xs acc

dropInactiveToken :: [Chunk] -> [Chunk]
dropInactiveToken toks = case toks of
  [] -> []
  Chunk _ []:xs -> dropInactiveToken xs
  Chunk hidden (_:xs):rest -> prependChunk hidden xs rest

ignoredDirectives :: [String]
ignoredDirectives = ["#line", "#pragma"]

startIf :: [IfFrame] -> Bool -> [IfFrame]
startIf frames cond = case applyIfDirective frames (IfCondition cond) of
  Just frames' -> frames'
  Nothing -> frames

replaceElse :: Span -> [IfFrame] -> Either PreprocessError [IfFrame]
replaceElse sp frames = case applyIfDirective frames ElseCondition of
  Nothing -> Left (PreprocessError (spanStart sp) "#else without #if")
  Just frames' -> Right frames'

replaceElif :: Span -> [IfFrame] -> Bool -> Either PreprocessError [IfFrame]
replaceElif sp frames cond = case applyIfDirective frames (ElifCondition cond) of
  Nothing -> Left (PreprocessError (spanStart sp) "#elif without #if")
  Just frames' -> Right frames'

popIf :: Span -> [IfFrame] -> Either PreprocessError [IfFrame]
popIf sp frames = case applyIfDirective frames EndifCondition of
  Nothing -> Left (PreprocessError (spanStart sp) "#endif without #if")
  Just frames' -> Right frames'

defineMacro :: Macros -> Span -> String -> Either PreprocessError Macros
defineMacro macros sp text = do
  macro <- parseMacroDefinition sp text
  Right (symbolMapInsert (macroName macro) macro macros)

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
takeMacroParams sp = go 1 [] where
  go :: Int -> String -> String -> Either PreprocessError (String, String)
  go depth acc rest = case rest of
    [] -> Left (PreprocessError (spanStart sp) "unterminated macro parameter list")
    ')':xs | depth == 1 -> Right (reverse acc, xs)
    ')':xs -> go (depth - 1) (')':acc) xs
    '(':xs -> go (depth + 1) ('(':acc) xs
    c:xs -> go depth (c:acc) xs

parseMacroParams :: Span -> String -> Either PreprocessError ([String], Maybe String)
parseMacroParams sp text =
  let trimmed = trim text
      pieces = if null trimmed then [] else map trim (splitCommas trimmed)
  in parsePieces [] Nothing pieces
  where
    parsePieces params variadic pieces = case pieces of
      [] -> Right (reverse params, variadic)
      piece:rest -> case rest of
        _ | piece == "..." && null rest && variadic == Nothing ->
          parsePieces params (Just "__VA_ARGS__") rest
        _ | "..." `suffixOf` piece ->
          let name = trim (take (length piece - 3) piece)
          in if validMacroParam name && null rest && variadic == Nothing
             then parsePieces params (Just name) rest
             else Left (PreprocessError (spanStart sp) ("bad variadic macro parameter: " ++ piece))
        _ | validMacroParam piece && not (piece `elem` params) && variadic == Nothing ->
          parsePieces (piece:params) variadic rest
        _ -> Left (PreprocessError (spanStart sp) ("bad macro parameter: " ++ piece))

validMacroParam :: String -> Bool
validMacroParam name = case name of
  c:rest -> isIdentStart c && all isIdentChar rest
  [] -> False

splitCommas :: String -> [String]
splitCommas = go 0 [] [] where
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

expandNextSource :: Macros -> Bool -> [String] -> [Chunk] -> Either PreprocessError ([Token], [Chunk])
expandNextSource macros protectDefined disabled toks = do
  (expanded, rest) <- expandNextSourceChunks macros protectDefined disabled toks
  Right (sourceTokens expanded, rest)

expandNextSourceChunks :: Macros -> Bool -> [String] -> [Chunk] -> Either PreprocessError ([Chunk], [Chunk])
expandNextSourceChunks macros protectDefined disabled toks = case popSource toks of
  Nothing -> Right ([], [])
  Just (hidden, tok@(Token _ (TokIdent "defined")), xs) | protectDefined ->
    let (protected, rest) = takeDefinedOperandSource xs
    in Right (chunk hidden (tok:protected) [], rest)
  Just (hidden, tok@(Token sp (TokIdent name)), xs) ->
    if name `elem` (hidden ++ disabled)
    then Right (chunk (name:hidden) [tok] [], xs)
    else case symbolMapLookup name macros of
      Nothing -> Right (chunk hidden [tok] [], xs)
      Just macro -> expandMacroChunks macros protectDefined hidden disabled tok sp name macro xs
  Just (hidden, tok, xs) -> Right (chunk hidden [tok] [], xs)

expandTokens :: Macros -> Bool -> [String] -> [Token] -> Either PreprocessError [Token]
expandTokens macros protectDefined disabled toks =
  expandSource macros protectDefined disabled (sourceFromTokens toks)

expandSource :: Macros -> Bool -> [String] -> [Chunk] -> Either PreprocessError [Token]
expandSource macros protectDefined disabled source = go source id where
  go rest acc = case rest of
    [] -> Right (acc [])
    _ -> do
      (expanded, rest') <- expandNextSource macros protectDefined disabled rest
      go rest' (acc . (expanded ++))

expandSourceChunks :: Macros -> Bool -> [String] -> [Chunk] -> Either PreprocessError [Chunk]
expandSourceChunks macros protectDefined disabled source = go source id where
  go rest acc = case rest of
    [] -> Right (acc [])
    _ -> do
      (expanded, rest') <- expandNextSourceChunks macros protectDefined disabled rest
      go rest' (acc . (expanded ++))

expandMacroChunks :: Macros -> Bool -> [String] -> [String] -> Token -> Span -> String -> Macro -> [Chunk] -> Either PreprocessError ([Chunk], [Chunk])
expandMacroChunks macros protectDefined hidden disabled original sp name macro rest = case macro of
  ObjectMacro _ body -> do
    let replacement = relocate sp body
    Right ([], prependChunk (name:hidden ++ disabled) replacement rest)
  FunctionMacro _ params variadic body -> case popSource rest of
    Just (_, Token _ (TokPunct "("), afterOpen) -> do
      (args, closingHidden, rest') <- collectInvocationArgs sp afterOpen
      let resultHidden = name : intersect hidden closingHidden ++ disabled
      expanded <- expandFunctionMacro macros protectDefined disabled resultHidden sp name params variadic body args
      Right ([], expanded ++ rest')
    _ -> Right (chunk (hidden ++ disabled) [original] [], rest)

takeDefinedOperandSource :: [Chunk] -> ([Token], [Chunk])
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

collectInvocationArgs :: Span -> [Chunk] -> Either PreprocessError ([[Chunk]], [String], [Chunk])
collectInvocationArgs sp toks = go 1 [] [] toks where
  go :: Int -> [Chunk] -> [[Chunk]] -> [Chunk] -> Either PreprocessError ([[Chunk]], [String], [Chunk])
  go depth current args rest = case popSource rest of
    Nothing -> Left (PreprocessError (spanStart sp) "unterminated macro invocation")
    Just (closingHidden, Token _ (TokPunct ")"), xs) | depth == 1 ->
      let finalArgs = if null args && null current then [] else reverse (reverse current : args)
      in Right (finalArgs, closingHidden, xs)
    Just (hidden, tok@(Token _ (TokPunct ")")), xs) ->
      go (depth - 1) (chunk hidden [tok] current) args xs
    Just (hidden, tok@(Token _ (TokPunct "(")), xs) ->
      go (depth + 1) (chunk hidden [tok] current) args xs
    Just (_, Token _ (TokPunct ","), xs) | depth == 1 ->
      go depth [] (reverse current : args) xs
    Just (hidden, tok, xs) ->
      go depth (chunk hidden [tok] current) args xs

expandFunctionMacro :: Macros -> Bool -> [String] -> [String] -> Span -> String -> [String] -> Maybe String -> [Token] -> [[Chunk]] -> Either PreprocessError [Chunk]
expandFunctionMacro macros protectDefined disabled resultHidden sp name params variadic body args = do
  bound <- bindMacroArgs macros protectDefined disabled sp name params variadic args
  let argMap = boundArgMap bound
  replaced <- substituteMacroBody sp argMap body
  pure (hideSource resultHidden replaced)

hideSource :: [String] -> [Chunk] -> [Chunk]
hideSource names source = case source of
  [] -> []
  Chunk hidden toks:rest -> Chunk (names ++ hidden) toks : hideSource names rest

data BoundMacroArgs = BoundMacroArgs MacroArgs [MacroArg]

boundArgMap :: BoundMacroArgs -> MacroArgs
boundArgMap bound = case bound of
  BoundMacroArgs argMap _ -> argMap

boundArgList :: BoundMacroArgs -> [MacroArg]
boundArgList bound = case bound of
  BoundMacroArgs _ argList -> argList

bindMacroArgs :: Macros -> Bool -> [String] -> Span -> String -> [String] -> Maybe String -> [[Chunk]] -> Either PreprocessError BoundMacroArgs
bindMacroArgs macros protectDefined disabled sp invokedName params variadic args = do
  let fixedCount = length params
      normalizedArgs = normalizeEmptyMacroArgs fixedCount args
  if length normalizedArgs < fixedCount || (variadic == Nothing && length normalizedArgs /= fixedCount)
    then wrongNumberOfMacroArgs
    else do
      fixed <- bindFixed symbolMapEmpty [] params (take fixedCount normalizedArgs)
      variadicBinding <- case variadic of
        Nothing -> Right fixed
        Just variadicName -> do
          let restArgs = drop fixedCount normalizedArgs
          arg <- makeArg (joinVariadicArgSources sp restArgs)
          Right (insertBoundArg variadicName arg fixed)
      Right variadicBinding
  where
    bindFixed argMap argList ps as = case (ps, as) of
      ([], []) -> Right (BoundMacroArgs argMap (reverse argList))
      (p:ps', a:as') -> do
        arg <- makeArg a
        let bound = insertBoundArg p arg (BoundMacroArgs argMap argList)
        bindFixed (boundArgMap bound) (boundArgList bound) ps' as'
      _ -> wrongNumberOfMacroArgs

    makeArg raw = do
      expanded <- expandSourceChunks macros protectDefined disabled raw
      Right (MacroArg (sourceTokens raw) expanded)

    wrongNumberOfMacroArgs =
      Left (PreprocessError (spanStart sp) ("wrong number of macro arguments for " ++ invokedName))

normalizeEmptyMacroArgs :: Int -> [[Chunk]] -> [[Chunk]]
normalizeEmptyMacroArgs fixedCount args =
  if fixedCount > 0 && null args then [[]] else args

insertBoundArg :: String -> MacroArg -> BoundMacroArgs -> BoundMacroArgs
insertBoundArg name arg bound = case bound of
  BoundMacroArgs argMap argList -> BoundMacroArgs (symbolMapInsert name arg argMap) (arg:argList)

joinVariadicArgSources :: Span -> [[Chunk]] -> [Chunk]
joinVariadicArgSources sp args = case args of
  [] -> []
  first:rest -> first ++ concatMap (chunk [] [commaToken sp]) rest

commaToken :: Span -> Token
commaToken sp = Token sp (TokPunct ",")

substituteMacroBody :: Span -> MacroArgs -> [Token] -> Either PreprocessError [Chunk]
substituteMacroBody sp args body =
  if macroBodyUsesPasteOrStringify body
    then do
      toks <- substituteMacroBodyTokens sp args body
      Right (sourceFromTokens toks)
    else substituteMacroBodyChunks args body

macroBodyUsesPasteOrStringify :: [Token] -> Bool
macroBodyUsesPasteOrStringify body = case body of
  [] -> False
  Token _ (TokPunct "#"):_ -> True
  Token _ (TokPunct "##"):_ -> True
  _:rest -> macroBodyUsesPasteOrStringify rest

substituteMacroBodyChunks :: MacroArgs -> [Token] -> Either PreprocessError [Chunk]
substituteMacroBodyChunks args body = go body id where
  go rest acc = case rest of
    [] -> Right (acc [])
    Token _ (TokIdent name):xs
      | Just arg <- symbolMapLookup name args ->
          go xs (acc . (argExpanded arg ++))
    tok:xs ->
      go xs (acc . chunk [] [tok])

substituteMacroBodyTokens :: Span -> MacroArgs -> [Token] -> Either PreprocessError [Token]
substituteMacroBodyTokens sp args body = go body [] where
  go rest acc = case rest of
    [] -> Right (reverse acc)
    Token _ (TokPunct "#"):Token argSp (TokIdent name):xs
      | Just arg <- symbolMapLookup name args ->
          go xs (Token argSp (TokString (stringifyTokens (argRaw arg))) : acc)
    Token pasteSp (TokPunct "##"):xs ->
      case acc of
        [] -> pasteWithPrevious pasteSp [] xs acc
        previous:before -> pasteWithPrevious pasteSp [previous] xs before
    Token _ (TokIdent name):Token pasteSp (TokPunct "##"):xs
      | Just arg <- symbolMapLookup name args ->
          pasteWithPrevious pasteSp (argRaw arg) xs acc
    Token _ (TokIdent name):xs
      | Just arg <- symbolMapLookup name args ->
          go xs (reverse (sourceTokens (argExpanded arg)) ++ acc)
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
      | Just arg <- symbolMapLookup name args -> Right (coalesceLeadingPpNumber (argRaw arg), rest)
    tok:rest -> Right ([tok], rest)
    [] -> Right ([], [])

-- The C lexer normally sees language tokens, while macro pasting operates on
-- preprocessing tokens.  A preprocessing number may contain identifier
-- characters, so text such as `1_0` arrives here as adjacent `1` and
-- `_0` language tokens.  Rejoin that leading pair while it is a paste operand;
-- the completed paste is then lexed normally by pasteTokens.
coalesceLeadingPpNumber :: [Token] -> [Token]
coalesceLeadingPpNumber toks = case toks of
  Token (Span start middle) kind:Token (Span nextStart end) (TokIdent suffix):rest
    | tokenIsNumber kind && samePosition middle nextStart ->
        let text = tokenText kind ++ suffix
        in Token (Span start end) (TokIdent text) : rest
  _ -> toks

tokenIsNumber :: TokenKind -> Bool
tokenIsNumber kind = case kind of
  TokInt _ -> True
  TokFloat _ -> True
  _ -> False

samePosition :: SrcPos -> SrcPos -> Bool
samePosition left right = case (left, right) of
  (SrcPos leftLine leftColumn, SrcPos rightLine rightColumn) ->
    leftLine == rightLine && leftColumn == rightColumn

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

evalIf :: Macros -> Span -> String -> Either PreprocessError Bool
evalIf macros sp text = do
  toks <- case lexC (stripLineComment text) of
    Left (LexError pos msg) -> Left (PreprocessError pos msg)
    Right result -> Right result
  replaced <- replaceDefinedOperators macros toks
  expanded <- expandTokens macros False [] replaced
  case parseConstExpr [] expanded of
    Right (value, []) -> Right (value /= 0)
    Right (_, tok:_) -> Left (PreprocessError (tokenStart tok) ("trailing tokens in #if expression near " ++ show (tokenText (tokenKind tok))))
    Left msg -> Left (PreprocessError (spanStart sp) ("invalid #if expression: " ++ msg ++ ": " ++ text))

replaceDefinedOperators :: Macros -> [Token] -> Either PreprocessError [Token]
replaceDefinedOperators macros toks = go toks id where
  go rest acc = case rest of
    [] -> Right (acc [])
    Token sp (TokIdent "defined"):Token _ (TokPunct "("):Token _ (TokIdent name):Token _ (TokPunct ")"):xs ->
      go xs (acc . (definedToken sp name :))
    Token sp (TokIdent "defined"):Token _ (TokIdent name):xs ->
      go xs (acc . (definedToken sp name :))
    Token sp (TokIdent "defined"):_ ->
      Left (PreprocessError (spanStart sp) "bad defined operator in #if expression")
    tok:xs ->
      go xs (acc . (tok :))

  definedToken sp name = Token sp (TokInt (if symbolMapMember name macros then "1" else "0"))

chunk :: [String] -> [Token] -> [Chunk] -> [Chunk]
chunk hidden toks rest =
  if null toks then rest else Chunk hidden toks : rest

sourceFromTokens :: [Token] -> [Chunk]
sourceFromTokens toks =
  case toks of
    [] -> []
    _ -> [Chunk [] toks]

sourceTokens :: [Chunk] -> [Token]
sourceTokens source = case source of
  [] -> []
  Chunk _ toks:rest -> toks ++ sourceTokens rest

prependChunk :: [String] -> [Token] -> [Chunk] -> [Chunk]
prependChunk hidden toks source =
  if null toks then source else Chunk hidden toks : source

popSource :: [Chunk] -> Maybe ([String], Token, [Chunk])
popSource source = case source of
  [] -> Nothing
  Chunk _ []:rest -> popSource rest
  Chunk hidden (tok:toks):rest -> Just (hidden, tok, prependChunk hidden toks rest)

stripLineComment :: String -> String
stripLineComment text = case text of
  [] -> []
  '/':'/':_ -> []
  c:rest -> c : stripLineComment rest

macroName :: Macro -> String
macroName macro = case macro of
  ObjectMacro name _ -> name
  FunctionMacro name _ _ _ -> name

relocate :: Span -> [Token] -> [Token]
relocate sp = map replaceSpan where
  replaceSpan (Token _ kind) = Token sp kind

spanStart :: Span -> SrcPos
spanStart (Span start _) = start

tokenStart :: Token -> SrcPos
tokenStart (Token sp _) = spanStart sp

tokenKind :: Token -> TokenKind
tokenKind (Token _ kind) = kind

dropSpaces :: String -> String
dropSpaces = dropWhile isSpaceChar
