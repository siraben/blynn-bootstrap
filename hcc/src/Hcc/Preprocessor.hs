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
  { argRaw :: [PPToken]
  , argExpanded :: Either PreprocessError [PPToken]
  }

type Macros = SymbolMap Macro
type MacroArgs = SymbolMap MacroArg

-- Eligibility belongs to individual tokens, including tokens retained from an
-- argument prescan. It must survive substitution and the subsequent rescan.
data PPToken = PPToken [String] Token

preprocess :: [Token] -> Either PreprocessError [Token]
preprocess toks = go symbolMapEmpty [] (sourceFromTokens toks) id where
  go macros frames rest acc = case rest of
    [] ->
      if null frames
      then Right (map plainToken (acc []))
      else Left (PreprocessError (SrcPos 1 1) "unterminated conditional directive")
    PPToken _ (Token sp (TokDirective text)):xs -> handleDirective macros frames sp text xs acc
    _ ->
      if ifStackActive frames
      then do
        (expanded, rest') <- expandNextSource macros rest
        go macros frames rest' (acc . (expanded ++))
      else go macros frames (drop 1 rest) acc

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
    Directive "include" _ -> go macros frames xs acc
    Directive "ifdef" rest ->
      case directiveName rest of
        Just name -> go macros (startIf frames (symbolMapMember name macros)) xs acc
        Nothing -> Left (PreprocessError (spanStart sp) "#ifdef without macro name")
    Directive "ifndef" rest ->
      case directiveName rest of
        Just name -> go macros (startIf frames (not (symbolMapMember name macros))) xs acc
        Nothing -> Left (PreprocessError (spanStart sp) "#ifndef without macro name")
    Directive "if" rest ->
      evalEligibleIf (ifStackActive frames) macros rest >>= \cond -> go macros (startIf frames cond) xs acc
    Directive "elif" rest ->
      evalEligibleIf (elifEligible frames) macros rest >>= \cond -> replaceElif sp frames cond >>= \frames' -> go macros frames' xs acc
    Directive "else" _ -> replaceElse sp frames >>= \frames' -> go macros frames' xs acc
    Directive "endif" _ -> popIf sp frames >>= \frames' -> go macros frames' xs acc
    Directive "" _ -> go macros frames xs acc
    Directive name _ | ("#" ++ name) `elem` ignoredDirectives -> go macros frames xs acc
    Directive name _ | all isDigitChar name -> go macros frames xs acc
    Directive name _ ->
      if ifStackActive frames
      then Left (PreprocessError (spanStart sp) ("unsupported directive: #" ++ name))
      else go macros frames xs acc

-- Ineligible groups still affect nesting, but their expressions are not parsed
-- or macro-expanded (and may contain otherwise invalid expressions).
elifEligible :: [IfFrame] -> Bool
elifEligible frames = case frames of
  [] -> False
  frame:_ -> ifParent frame && not (ifTaken frame)

evalEligibleIf :: Bool -> Macros -> String -> Either PreprocessError Bool
evalEligibleIf eligible macros text =
  if eligible then evalIf macros text else Right False

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
parseMacroParams sp text = parsePieces [] Nothing (filter (not . null) (map trim (splitCommas text))) where
  parsePieces params variadic pieces = case pieces of
    [] -> Right (reverse params, variadic)
    piece:rest
      | piece == "..." -> parsePieces params (Just "__VA_ARGS__") rest
      | "..." `suffixOf` piece ->
          let name = trim (take (length piece - 3) piece)
          in if all isIdentChar name && not (null name)
             then parsePieces params (Just name) rest
             else Left (PreprocessError (spanStart sp) ("bad variadic macro parameter: " ++ piece))
      | all isIdentChar piece && not (null piece) -> parsePieces (piece:params) variadic rest
      | otherwise -> Left (PreprocessError (spanStart sp) ("bad macro parameter: " ++ piece))

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

expandNextSource :: Macros -> [PPToken] -> Either PreprocessError ([PPToken], [PPToken])
expandNextSource macros toks = case toks of
  [] -> Right ([], [])
  original@(PPToken hidden (Token sp (TokIdent name))):rest
    | not (name `elem` hidden), Just macro <- symbolMapLookup name macros ->
        case macro of
          ObjectMacro _ body ->
            Right ([], map (hideToken (name:hidden)) (sourceFromTokens body) ++ rest)
          FunctionMacro _ params variadic body -> case rest of
            PPToken _ (Token _ (TokPunct "(")):afterOpen -> do
              (args, closeHidden, rest') <- collectInvocationArgs sp afterOpen
              bound <- bindMacroArgs macros sp params variadic args
              replaced <- substituteMacroBody sp bound (sourceFromTokens body)
              -- The closing parenthesis may come from a different expansion.
              -- Only names hidden at both ends constrain the replacement.
              let inherited = name : intersect hidden closeHidden
              Right ([], map (hideToken inherited) replaced ++ rest')
            _ -> Right ([original], rest)
  tok:rest -> Right ([tok], rest)

expandSource :: Macros -> [PPToken] -> Either PreprocessError [PPToken]
expandSource macros toks = go toks id where
  go rest acc = case rest of
    [] -> Right (acc [])
    _ -> do
      (expanded, rest') <- expandNextSource macros rest
      go rest' (acc . (expanded ++))

expandTokens :: Macros -> [Token] -> Either PreprocessError [Token]
expandTokens macros toks = map plainToken <$> expandSource macros (sourceFromTokens toks)

collectInvocationArgs :: Span -> [PPToken] -> Either PreprocessError ([[PPToken]], [String], [PPToken])
collectInvocationArgs sp = go 1 [] [] where
  go :: Int -> [PPToken] -> [[PPToken]] -> [PPToken] -> Either PreprocessError ([[PPToken]], [String], [PPToken])
  go depth current args rest = case rest of
    [] -> Left (PreprocessError (spanStart sp) "unterminated macro invocation")
    PPToken hidden (Token _ (TokPunct ")")):xs | depth == 1 ->
      let finalArgs = if null args && null current then [] else reverse (reverse current : args)
      in Right (finalArgs, hidden, xs)
    tok@(PPToken _ (Token _ (TokPunct ")"))):xs -> go (depth - 1) (tok:current) args xs
    tok@(PPToken _ (Token _ (TokPunct "("))):xs -> go (depth + 1) (tok:current) args xs
    PPToken _ (Token _ (TokPunct ",")):xs | depth == 1 -> go depth [] (reverse current : args) xs
    tok:xs -> go depth (tok:current) args xs

bindMacroArgs :: Macros -> Span -> [String] -> Maybe String -> [[PPToken]] -> Either PreprocessError MacroArgs
bindMacroArgs macros sp params variadic args = do
  let fixedCount = length params
  let args' = if fixedCount == 1 && variadic == Nothing && null args then [[]] else args
  if length args' < fixedCount || (variadic == Nothing && length args' /= fixedCount)
    then Left (PreprocessError (spanStart sp) "wrong number of macro arguments")
    else do
      fixed <- bindFixed symbolMapEmpty params (take fixedCount args')
      case variadic of
        Nothing -> Right fixed
        Just name -> do
          arg <- makeArg (joinVariadicArgs sp (drop fixedCount args'))
          Right (symbolMapInsert name arg fixed)
  where
    bindFixed argMap ps as = case (ps, as) of
      ([], []) -> Right argMap
      (p:ps', a:as') -> do
        arg <- makeArg a
        bindFixed (symbolMapInsert p arg argMap) ps' as'
      _ -> Left (PreprocessError (spanStart sp) "wrong number of macro arguments")

    -- Keep prescanning lazy: # and ## use only raw tokens.
    makeArg raw = Right (MacroArg raw (expandSource macros raw))

joinVariadicArgs :: Span -> [[PPToken]] -> [PPToken]
joinVariadicArgs sp args = case args of
  [] -> []
  first:rest -> first ++ concatMap (PPToken [] (Token sp (TokPunct ",")) :) rest

substituteMacroBody :: Span -> MacroArgs -> [PPToken] -> Either PreprocessError [PPToken]
substituteMacroBody _ args body = go body [] where
  go rest acc = case rest of
    [] -> Right (reverse acc)
    PPToken _ (Token _ (TokPunct "#")):PPToken _ (Token argSp (TokIdent name)):xs
      | Just arg <- symbolMapLookup name args ->
          go xs (PPToken [] (Token argSp (TokString (stringifyTokens (map plainToken (argRaw arg))))) : acc)
    PPToken _ (Token pasteSp (TokPunct "##")):xs ->
      case acc of
        [] -> pasteWithPrevious pasteSp [] xs acc
        previous:before -> pasteWithPrevious pasteSp [previous] xs before
    PPToken _ (Token _ (TokIdent name)):PPToken _ (Token pasteSp (TokPunct "##")):xs
      | Just arg <- symbolMapLookup name args -> pasteWithPrevious pasteSp (argRaw arg) xs acc
    PPToken _ (Token _ (TokIdent name)):xs
      | Just arg <- symbolMapLookup name args -> do
          expanded <- argExpanded arg
          go xs (reverse expanded ++ acc)
    tok:xs -> go xs (tok:acc)

  pasteWithPrevious pasteSp previous xs before = do
    (next, rest') <- nextPasteOperand xs
    case (previous, next) of
      ([PPToken _ (Token _ (TokPunct ","))], []) -> go rest' before
      ([comma@(PPToken _ (Token _ (TokPunct ",")))], _) -> go rest' (reverse next ++ comma:before)
      (_, []) -> go rest' (reverse previous ++ before)
      ([], _) -> go rest' (reverse next ++ before)
      (_, n:ns) -> case reverse previous of
        prev:prefix -> do
          pasted <- pasteTokens pasteSp prev n
          go rest' (reverse ns ++ pasted:prefix ++ before)
        [] -> go rest' (reverse next ++ before)

  nextPasteOperand xs = case xs of
    PPToken _ (Token _ (TokIdent name)):rest
      | Just arg <- symbolMapLookup name args -> Right (argRaw arg, rest)
    tok:rest -> Right ([tok], rest)
    [] -> Right ([], [])

pasteTokens :: Span -> PPToken -> PPToken -> Either PreprocessError PPToken
pasteTokens sp (PPToken lh left) (PPToken rh right) =
  case lexC (tokenText (tokenKind left) ++ tokenText (tokenKind right)) of
    Right [Token _ kind] -> Right (PPToken (intersect lh rh) (Token sp kind))
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
  toks <- case lexC text of
    Left (LexError pos msg) -> Left (PreprocessError pos msg)
    Right result -> Right result
  replaced <- replaceDefinedOperators macros toks
  expanded <- expandTokens macros replaced
  case parseConstExpr [] expanded of
    Right (value, []) -> Right (value /= 0)
    Right (_, tok:_) -> Left (PreprocessError (tokenStart tok) ("trailing tokens in #if expression near " ++ show (tokenText (tokenKind tok))))
    Left msg -> Left (PreprocessError (SrcPos 1 1) msg)

replaceDefinedOperators :: Macros -> [Token] -> Either PreprocessError [Token]
replaceDefinedOperators macros toks = go toks id where
  go rest acc = case rest of
    [] -> Right (acc [])
    Token sp (TokIdent "defined"):Token _ (TokPunct "("):Token _ (TokIdent name):Token _ (TokPunct ")"):xs ->
      go xs (acc . (definedToken sp name :))
    Token sp (TokIdent "defined"):Token _ (TokIdent name):xs -> go xs (acc . (definedToken sp name :))
    Token sp (TokIdent "defined"):_ -> Left (PreprocessError (spanStart sp) "bad defined operator in #if expression")
    tok:xs -> go xs (acc . (tok :))
  definedToken sp name = Token sp (TokInt (if symbolMapMember name macros then "1" else "0"))

sourceFromTokens :: [Token] -> [PPToken]
sourceFromTokens = map (PPToken [])

plainToken :: PPToken -> Token
plainToken (PPToken _ tok) = tok

hideToken :: [String] -> PPToken -> PPToken
hideToken names (PPToken hidden tok) = PPToken (union names hidden) tok

macroName :: Macro -> String
macroName macro = case macro of
  ObjectMacro name _ -> name
  FunctionMacro name _ _ _ -> name

spanStart :: Span -> SrcPos
spanStart (Span start _) = start

tokenStart :: Token -> SrcPos
tokenStart (Token sp _) = spanStart sp

tokenKind :: Token -> TokenKind
tokenKind (Token _ kind) = kind

dropSpaces :: String -> String
dropSpaces = dropWhile isSpaceChar
