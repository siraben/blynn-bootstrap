module IncludeExpand
  ( readSourceWithIncludes
  ) where

import Base
import Directive
import DriverCommon
import HccSystem
import IfFrame
import SymbolTable
import TextUtil

type IncludeMacros = SymbolMap String

readSourceWithIncludes :: [String] -> [(String, String)] -> String -> IO String
readSourceWithIncludes includeDirs defines path = do
  (builder, _, _) <- expandFile [] symbolSetEmpty initialMacros path
  pure (builder "")
  where
  initialMacros = macrosFromDefines defines

  expandFile stack guards macros file = do
    key <- hccCanonicalizePath file
    if key `elem` stack
      then pure (id, guards, macros)
      else do
        source <- hccReadFile key
        case includeGuard key source of
          Just (PragmaOnce guard) | symbolSetMember guard guards ->
            pure (id, guards, macros)
          Just (IfndefGuard guard start end) | symbolSetMember guard guards ->
            expandLines (hccTakeDirectory key) (key:stack) guards macros [] (skipLineRange start end (lines source))
          guardInfo -> do
            let guards' = case guardInfo of
                  Nothing -> guards
                  Just (PragmaOnce guard) -> symbolSetInsert guard guards
                  Just (IfndefGuard guard _ _) -> symbolSetInsert guard guards
            expandLines (hccTakeDirectory key) (key:stack) guards' macros [] (lines source)

  expandLines currentDir stack guards macros frames ls = case ls of
    [] -> pure (id, guards, macros)
    line:rest -> do
      (expanded, guards', macros', frames') <- expandLine currentDir stack guards macros frames line
      (tailText, guards'', macros'') <- expandLines currentDir stack guards' macros' frames' rest
      pure (expanded . tailText, guards'', macros'')

  expandLine currentDir stack guards macros frames line =
    let active = ifStackActive frames
        keep = (line++) . ('\n':)
    in case directiveNameFromLine line of
      Just "ifdef" ->
        pure (keep, guards, macros, applyIncludeIf frames (IfCondition (maybe False (`symbolMapMember` macros) (directiveArgument "ifdef" line))))
      Just "ifndef" ->
        pure (keep, guards, macros, applyIncludeIf frames (IfCondition (maybe False (not . (`symbolMapMember` macros)) (directiveArgument "ifndef" line))))
      Just "if" ->
        pure (keep, guards, macros, applyIncludeIf frames (IfCondition (evalIncludeIf macros (directiveRest "if" line))))
      Just "elif" ->
        pure (keep, guards, macros, applyIncludeIf frames (ElifCondition (evalIncludeIf macros (directiveRest "elif" line))))
      Just "else" ->
        pure (keep, guards, macros, applyIncludeIf frames ElseCondition)
      Just "endif" ->
        pure (keep, guards, macros, applyIncludeIf frames EndifCondition)
      Just "define" | active ->
        case directiveDefine line of
          Just (name, value) -> pure (keep, guards, symbolMapInsert name value macros, frames)
          Nothing -> pure (keep, guards, macros, frames)
      Just "undef" | active ->
        case directiveArgument "undef" line of
          Just name -> pure (keep, symbolSetDelete name guards, symbolMapDelete name macros, frames)
          Nothing -> pure (keep, guards, macros, frames)
      _ -> case includeRequest macros line of
        Just (form, name) | active -> do
          found <- findInclude currentDir name
          case found of
            Nothing -> case form of
              QuoteInclude -> die ("hcpp: cannot find include file " ++ show name)
                              >> pure (keep, guards, macros, frames)
              SystemInclude -> die ("hcpp: cannot find include file <" ++ name ++ ">")
                               >> pure (keep, guards, macros, frames)
            Just file ->
              if file `elem` stack
              then pure (id, guards, macros, frames)
              else do
                (expanded, guards', macros') <- expandFile stack guards macros file
                pure (expanded, guards', macros', frames)
        _ -> pure (keep, guards, macros, frames)

  applyIncludeIf frames directive = case applyIfDirective frames directive of
    Nothing -> frames
    Just frames' -> frames'

  findInclude currentDir name = do
    let candidates = hccPathJoin currentDir name : map (`hccPathJoin` name) includeDirs
    existing <- hccFilterExisting candidates
    pure (case existing of
      [] -> Nothing
      file:_ -> Just file)

data IncludeForm = QuoteInclude | SystemInclude

includeRequest :: IncludeMacros -> String -> Maybe (IncludeForm, String)
includeRequest macros line = case parseDirective line of
  Directive "include" rest -> case words rest of
    raw:_ -> includeRequestRaw macros raw
    _ -> Nothing
  _ -> Nothing

includeRequestRaw :: IncludeMacros -> String -> Maybe (IncludeForm, String)
includeRequestRaw macros raw = case stripIncludeDelims raw of
  Just request -> Just request
  Nothing -> case symbolMapLookup raw macros of
    Just replacement -> stripIncludeDelims (trim replacement)
    Nothing -> Nothing

stripIncludeDelims :: String -> Maybe (IncludeForm, String)
stripIncludeDelims raw = case raw of
  '"':rest -> Just (QuoteInclude, takeWhile (/= '"') rest)
  '<':rest -> Just (SystemInclude, takeWhile (/= '>') rest)
  _ -> Nothing

evalIncludeIf :: IncludeMacros -> String -> Bool
evalIncludeIf macros text =
  evalOr (filter (not . null) (splitTopLevel "||" text))
  where
    evalOr parts = case parts of
      [] -> evalAnd (filter (not . null) (splitTopLevel "&&" text))
      [part] -> evalAnd (filter (not . null) (splitTopLevel "&&" part))
      part:rest -> evalIncludeIf macros part || evalOr rest

    evalAnd parts = case parts of
      [] -> evalAtom text
      [part] -> evalAtom part
      part:rest -> evalAtom part && evalAnd rest

    evalAtom raw =
      let atom = trim raw
      in case atom of
        '!':rest -> not (evalAtom rest)
        'd':'e':'f':'i':'n':'e':'d':rest -> evalDefined rest
        '(' : rest | lastMaybe rest == Just ')' -> evalIncludeIf macros (init rest)
        _ | all isDigitChar atom -> readDecimal atom /= 0
          | all isIdentChar atom -> case symbolMapLookup atom macros of
              Just value -> evalIncludeIf macros value
              Nothing -> False
          | otherwise -> False

    evalDefined raw =
      let rest = trim raw
      in case rest of
        '(' : xs -> symbolMapMember (takeWhile isIdentChar xs) macros
        _ -> symbolMapMember (takeWhile isIdentChar rest) macros

macrosFromDefines :: [(String, String)] -> IncludeMacros
macrosFromDefines defines = case defines of
  [] -> symbolMapEmpty
  (name, value):rest -> symbolMapInsert name value (macrosFromDefines rest)

splitTopLevel :: String -> String -> [String]
splitTopLevel sep text = go 0 text "" where
  go :: Int -> String -> String -> [String]
  go depth rest current = case rest of
    [] -> [reverse current]
    c:cs
      | c == '(' -> go (depth + 1) cs (c:current)
      | c == ')' -> go (depth - 1) cs (c:current)
      | depth == 0 && sep `prefixOf` rest -> reverse current : go depth (drop (length sep) rest) ""
      | otherwise -> go depth cs (c:current)

lastMaybe :: [a] -> Maybe a
lastMaybe xs = case xs of
  [] -> Nothing
  [x] -> Just x
  _:rest -> lastMaybe rest

readDecimal :: String -> Int
readDecimal = go 0 where
  go acc rest = case rest of
    [] -> acc
    c:cs -> go (acc * 10 + fromEnum c - fromEnum '0') cs

data IncludeGuard
  = PragmaOnce String
  | IfndefGuard String Int Int

includeGuard :: String -> String -> Maybe IncludeGuard
includeGuard path source =
  let cleanedLines = lines (stripComments source)
      indexedLines = zip [0..] cleanedLines
  in case dropBlankLines indexedLines of
    (start, line):rest
      | pragmaOnceLine line -> Just (PragmaOnce ("__HCC_PRAGMA_ONCE_" ++ path))
      | Just name <- directiveArgument "ifndef" line
      , canonicalGuardName path name ->
          case ifndefGuardEnd name rest of
            Just end -> Just (IfndefGuard name start end)
            Nothing -> Nothing
    _ -> Nothing

ifndefGuardEnd :: String -> [(Int, String)] -> Maybe Int
ifndefGuardEnd guard linesAfterIfndef =
  case dropBlankLines linesAfterIfndef of
    (_, line):rest
      | directiveArgument "define" line == Just guard ->
          matchingEndif 1 rest
    _ -> Nothing

matchingEndif :: Int -> [(Int, String)] -> Maybe Int
matchingEndif depth sourceLines = case sourceLines of
  [] -> Nothing
  (lineNo, line):rest -> case directiveNameFromLine line of
    Just name | name `elem` ["if", "ifdef", "ifndef"] ->
      matchingEndif (depth + 1) rest
    Just "endif" ->
      if depth == 1
      then Just lineNo
      else matchingEndif (depth - 1) rest
    _ -> matchingEndif depth rest

dropBlankLines :: [(Int, String)] -> [(Int, String)]
dropBlankLines sourceLines = case sourceLines of
  [] -> []
  (_, line):rest ->
    if null (dropWhile isSpaceChar line)
    then dropBlankLines rest
    else sourceLines

skipLineRange :: Int -> Int -> [String] -> [String]
skipLineRange start end =
  kept 0
  where
    kept index lines' = case lines' of
      [] -> []
      line:rest ->
        if index >= start && index <= end
        then kept (index + 1) rest
        else line : kept (index + 1) rest

pragmaOnceLine :: String -> Bool
pragmaOnceLine line = case words line of
  ["#pragma", "once"] -> True
  ["#", "pragma", "once"] -> True
  _ -> False

directiveDefine :: String -> Maybe (String, String)
directiveDefine line = case dropWhile isSpaceChar line of
  '#':rest -> defineAfterHash rest
  _ -> Nothing

defineAfterHash :: String -> Maybe (String, String)
defineAfterHash text =
  let trimmed = dropWhile isSpaceChar text
  in if "define" `prefixOf` trimmed
     then defineNameValue (drop (length "define") trimmed)
     else Nothing

defineNameValue :: String -> Maybe (String, String)
defineNameValue text = case dropWhile isSpaceChar text of
  c:rest | isIdentStart c ->
    let (tailName, afterName) = span isIdentChar rest
        name = c:tailName
    in Just (name, defineReplacement afterName)
  _ -> Nothing

defineReplacement :: String -> String
defineReplacement text = case text of
  '(':_ -> "1"
  _ -> case trim text of
    "" -> "1"
    value -> value

canonicalGuardName :: String -> String -> Bool
canonicalGuardName path guard =
  splitNameTokens (map toUpperAscii (hccTakeFileName path)) == splitNameTokens (map toUpperAscii guard)

splitNameTokens :: String -> [String]
splitNameTokens text = filter (not . null) (go text "") where
  go rest current = case rest of
    [] -> [reverse current]
    c:cs ->
      if isNameChar c
      then go cs (c:current)
      else reverse current : go cs ""

isNameChar :: Char -> Bool
isNameChar c = isAsciiUpper c || isDigitChar c

toUpperAscii :: Char -> Char
toUpperAscii c =
  if isAsciiLower c
  then toEnum (fromEnum c - 32)
  else c

isAsciiLower :: Char -> Bool
isAsciiLower c = c >= 'a' && c <= 'z'

isAsciiUpper :: Char -> Bool
isAsciiUpper c = c >= 'A' && c <= 'Z'
