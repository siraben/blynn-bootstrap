module Preprocessor
  ( PreprocessError(..)
  , preprocess
  , Macro
  , defineMacro
  , expandTokens
  , expandOperandText
  , evalEligibleIf
  , elifEligible
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
  , argExpanded :: Either PreprocessError Expansion
  }

type Macros = SymbolMap Macro
type MacroArgs = SymbolMap MacroArg

-- Eligibility belongs to individual tokens, including tokens retained from an
-- argument prescan. It must survive substitution and the subsequent rescan.
data PPToken = PPToken [String] Bool Token

-- Separation can outlive the last token (for example the empty x in `a x`).
-- Keep it until a surviving rescan suffix can receive it.
data Expansion = Expansion [PPToken] Bool

-- Empty paste operands remain placemarkers until every ## has been handled.
-- Removing them early can both lose separation and paste an unrelated token.
data MacroPiece = TokenPiece PPToken | EmptyPiece Bool

preprocess :: [Token] -> Either PreprocessError [Token]
preprocess toks = go symbolMapEmpty [] (sourceFromTokens toks) id where
  go macros frames rest acc = case rest of
    [] ->
      if null frames
      then Right (map plainToken (acc []))
      else Left (PreprocessError (SrcPos 1 1) "unterminated conditional directive")
    PPToken _ _ (Token sp (TokDirective text)):xs -> handleDirective macros frames sp text xs acc
    _ ->
      if ifStackActive frames
      then do
        (expanded, rest', _) <- expandNextSource macros rest
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
    Directive "include" _ ->
      if ifStackActive frames
      then Left (PreprocessError (spanStart sp) "unresolved active #include")
      else go macros frames xs acc
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

expandNextSource :: Macros -> [PPToken] -> Either PreprocessError ([PPToken], [PPToken], Bool)
expandNextSource macros toks = case toks of
  [] -> Right ([], [], False)
  original@(PPToken hidden space (Token sp (TokIdent name))):rest
    | not (name `elem` hidden), Just macro <- symbolMapLookup name macros ->
        case macro of
          ObjectMacro _ body ->
            rescanReplacement space (Expansion (map (hideToken (name:hidden)) (leadingSpace space (replacementTokens sp body))) False) rest
          FunctionMacro _ params variadic body -> case rest of
            PPToken _ _ (Token _ (TokPunct "(")):afterOpen -> do
              (args, commas, closeHidden, rest') <- collectInvocationArgs sp afterOpen
              bound <- bindMacroArgs macros sp params variadic args commas
              Expansion replaced trailing <- substituteMacroBody sp bound (leadingSpace space (replacementTokens sp body))
              -- The closing parenthesis may come from a different expansion.
              -- Only names hidden at both ends constrain the replacement.
              let inherited = name : intersect hidden closeHidden
              rescanReplacement space (Expansion (map (hideToken inherited) replaced) trailing) rest'
            _ -> Right ([original], rest, False)
  tok:rest -> Right ([tok], rest, False)

expandSource :: Macros -> [PPToken] -> Either PreprocessError Expansion
expandSource macros toks = go toks False id where
  go rest trailing acc = case rest of
    [] -> Right (Expansion (acc []) trailing)
    _ -> do
      (expanded, rest', trailing') <- expandNextSource macros rest
      go rest' (trailing || trailing') (acc . (expanded ++))

expandTokens :: Macros -> [Token] -> Either PreprocessError [Token]
expandTokens macros toks = do
  Expansion expanded _ <- expandSource macros (sourceFromTokens toks)
  Right (map plainToken expanded)

-- Computed header operands need the same separation/adjacency information as
-- stringification, before the plain-token API discards it.
expandOperandText :: Macros -> [Token] -> Either PreprocessError String
expandOperandText macros toks = do
  Expansion expanded _ <- expandSource macros (sourceFromTokens toks)
  Right (sourceSpelling expanded)

collectInvocationArgs :: Span -> [PPToken] -> Either PreprocessError ([[PPToken]], [PPToken], [String], [PPToken])
collectInvocationArgs sp = go 1 [] [] [] where
  go :: Int -> [PPToken] -> [[PPToken]] -> [PPToken] -> [PPToken] -> Either PreprocessError ([[PPToken]], [PPToken], [String], [PPToken])
  go depth current args commas rest = case rest of
    [] -> Left (PreprocessError (spanStart sp) "unterminated macro invocation")
    PPToken hidden _ (Token _ (TokPunct ")")):xs | depth == 1 ->
      let finalArgs = if null args && null current then [] else reverse (reverse current : args)
      in Right (finalArgs, reverse commas, hidden, xs)
    tok@(PPToken _ _ (Token _ (TokPunct ")"))):xs -> go (depth - 1) (tok:current) args commas xs
    tok@(PPToken _ _ (Token _ (TokPunct "("))):xs -> go (depth + 1) (tok:current) args commas xs
    tok@(PPToken _ _ (Token _ (TokPunct ","))):xs | depth == 1 -> go depth [] (reverse current : args) (tok:commas) xs
    tok:xs -> go depth (tok:current) args commas xs

bindMacroArgs :: Macros -> Span -> [String] -> Maybe String -> [[PPToken]] -> [PPToken] -> Either PreprocessError MacroArgs
bindMacroArgs macros sp params variadic args commas = do
  let fixedCount = length params
  let args' = if fixedCount == 1 && variadic == Nothing && null args then [[]] else args
  if length args' < fixedCount || (variadic == Nothing && length args' /= fixedCount)
    then Left (PreprocessError (spanStart sp) "wrong number of macro arguments")
    else do
      fixed <- bindFixed symbolMapEmpty params (take fixedCount args')
      case variadic of
        Nothing -> Right fixed
        Just name -> do
          arg <- makeArg (joinVariadicArgs (drop fixedCount args') (drop fixedCount commas))
          Right (symbolMapInsert name arg fixed)
  where
    bindFixed argMap ps as = case (ps, as) of
      ([], []) -> Right argMap
      (p:ps', a:as') -> do
        arg <- makeArg a
        bindFixed (symbolMapInsert p arg argMap) ps' as'
      _ -> Left (PreprocessError (spanStart sp) "wrong number of macro arguments")

    -- Keep prescanning lazy: # and ## use only raw tokens.
    makeArg raw = Right (MacroArg raw (expandSource macros (leadingSpace False raw)))

joinVariadicArgs :: [[PPToken]] -> [PPToken] -> [PPToken]
joinVariadicArgs args commas = case args of
  [] -> []
  first:rest -> first ++ case commas of
    comma:more -> comma : joinVariadicArgs rest more
    [] -> []

substituteMacroBody :: Span -> MacroArgs -> [PPToken] -> Either PreprocessError Expansion
substituteMacroBody _ args body = go body [] where
  go rest acc = case rest of
    [] -> Right (removePlacemarkers (reverse acc))
    PPToken _ space (Token _ (TokPunct "#")):PPToken _ _ (Token argSp (TokIdent name)):xs
      | Just arg <- symbolMapLookup name args ->
          go xs (TokenPiece (PPToken [] space (Token argSp (TokString (stringifyTokens (argRaw arg))))) : acc)
    PPToken _ _ (Token pasteSp (TokPunct "##")):xs ->
      case acc of
        [] -> pasteWithPrevious pasteSp [] xs acc
        previous:before -> pasteWithPrevious pasteSp [previous] xs before
    PPToken _ space (Token _ (TokIdent name)):PPToken _ _ (Token pasteSp (TokPunct "##")):xs
      | Just arg <- symbolMapLookup name args -> pasteWithPrevious pasteSp (substitutionPieces space (Expansion (leadingSpace False (argRaw arg)) False)) xs acc
    PPToken _ space (Token _ (TokIdent name)):xs
      | Just arg <- symbolMapLookup name args -> do
          expanded <- argExpanded arg
          go xs (reverse (substitutionPieces space expanded) ++ acc)
    tok:xs -> go xs (TokenPiece tok:acc)

  pasteWithPrevious pasteSp previous xs before = do
    (next, rest') <- nextPasteOperand xs
    case (previous, next) of
      ([TokenPiece (PPToken _ space (Token _ (TokPunct ",")))], [EmptyPiece _]) -> go rest' (EmptyPiece space:before)
      ([comma@(TokenPiece (PPToken _ _ (Token _ (TokPunct ","))))], _) -> go rest' (reverse next ++ comma:before)
      (_, []) -> go rest' (reverse previous ++ before)
      ([], _) -> go rest' (reverse next ++ before)
      (_, n:ns) -> case reverse previous of
        prev:prefix -> do
          pasted <- pastePieces pasteSp prev n
          go rest' (reverse ns ++ pasted:prefix ++ before)
        [] -> go rest' (reverse next ++ before)

  nextPasteOperand xs = case xs of
    PPToken _ space (Token _ (TokIdent name)):rest
      | Just arg <- symbolMapLookup name args -> Right (substitutionPieces space (Expansion (leadingSpace False (argRaw arg)) False), rest)
    tok:rest -> Right ([TokenPiece tok], rest)
    [] -> Right ([], [])

substitutionPieces :: Bool -> Expansion -> [MacroPiece]
substitutionPieces space (Expansion toks trailing) = case toks of
  [] -> [EmptyPiece (space || trailing)]
  -- Prescanning may remove a leading empty macro, exposing real internal
  -- separation on the first surviving token. Merge rather than overwrite it.
  -- Raw paste operands, like prescan inputs, have their outer space trimmed.
  _ -> map TokenPiece (addLeadingSpace space toks) ++ if trailing then [EmptyPiece True] else []

pastePieces :: Span -> MacroPiece -> MacroPiece -> Either PreprocessError MacroPiece
pastePieces sp left right = case (left, right) of
  (EmptyPiece space, EmptyPiece _) -> Right (EmptyPiece space)
  (EmptyPiece space, TokenPiece (PPToken hidden _ tok)) -> Right (TokenPiece (PPToken hidden space tok))
  (TokenPiece _, EmptyPiece _) -> Right left
  (TokenPiece a, TokenPiece b) -> TokenPiece <$> pasteTokens sp a b

removePlacemarkers :: [MacroPiece] -> Expansion
removePlacemarkers pieces = go False pieces id where
  go pending rest acc = case rest of
    [] -> Expansion (acc []) pending
    EmptyPiece space:xs -> go (pending || space) xs acc
    TokenPiece tok:xs -> go False xs (acc . (addLeadingSpace pending [tok] ++))

pasteTokens :: Span -> PPToken -> PPToken -> Either PreprocessError PPToken
pasteTokens sp (PPToken lh space left) (PPToken rh _ right) =
  case lexC (tokenText (tokenKind left) ++ tokenText (tokenKind right)) of
    Right [Token _ kind] -> Right (PPToken (intersect lh rh) space (Token sp kind))
    Right _ -> Left (PreprocessError (spanStart sp) "token paste did not form one token")
    Left (LexError _ msg) -> Left (PreprocessError (spanStart sp) msg)

stringifyTokens :: [PPToken] -> String
stringifyTokens toks = "\"" ++ escapeString (sourceSpelling toks) ++ "\""

sourceSpelling :: [PPToken] -> String
sourceSpelling toks = text (leadingSpace False toks) where
  text rest = case rest of
    [] -> []
    PPToken _ space tok:xs -> (if space then " " else "") ++ tokenText (tokenKind tok) ++ text xs

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
  case parsePPConstExpr expanded of
    Right (value, []) -> Right value
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
sourceFromTokens = go (SrcPos 0 0) where
  go end toks = case toks of
    [] -> []
    tok@(Token (Span start end') _):rest -> PPToken [] (not (samePos end start)) tok : go end' rest
  samePos (SrcPos l c) (SrcPos l' c') = l == l' && c == c'

-- Definition-buffer positions encode adjacency, but are not source locations
-- for diagnostics. Derive separation first, then relocate only body tokens;
-- substituted argument tokens keep their own invocation/argument locations.
replacementTokens :: Span -> [Token] -> [PPToken]
replacementTokens sp body = map relocate (sourceFromTokens body) where
  relocate (PPToken hidden space (Token _ kind)) = PPToken hidden space (Token sp kind)

plainToken :: PPToken -> Token
plainToken (PPToken _ _ tok) = tok

hideToken :: [String] -> PPToken -> PPToken
hideToken names (PPToken hidden space tok) = PPToken (union names hidden) space tok

leadingSpace :: Bool -> [PPToken] -> [PPToken]
leadingSpace space toks = case toks of
  [] -> []
  PPToken hidden _ tok:rest -> PPToken hidden space tok : rest

-- Transfer separation after the replacement to its suffix, or retain it if
-- this is the end of an argument prescan. An empty invocation's own leading
-- space also survives, without inserting space around nonempty replacements.
rescanReplacement :: Bool -> Expansion -> [PPToken] -> Either PreprocessError ([PPToken], [PPToken], Bool)
rescanReplacement space (Expansion replacement trailing) rest =
  let pending = trailing || (null replacement && space)
      -- The body's original leading space was set before substitution. The
      -- first survivor can now carry additional separation from empty pieces.
      source = addLeadingSpace space replacement ++ addLeadingSpace pending rest
  in Right ([], source, pending && null rest)

addLeadingSpace :: Bool -> [PPToken] -> [PPToken]
addLeadingSpace space toks = case toks of
  [] -> []
  PPToken hidden old tok:rest -> PPToken hidden (space || old) tok : rest

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
