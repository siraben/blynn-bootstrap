module IncludeExpand
  ( readSourceWithIncludes
  ) where

import Base
import DriverCommon
import HccSystem
import SymbolTable
import TextUtil

readSourceWithIncludes :: [String] -> [(String, String)] -> String -> IO String
readSourceWithIncludes includeDirs defines path = do
  (builder, _, _) <- expandFile [] symbolSetEmpty initialMacros path
  pure (builder "")
  where
  initialMacros = symbolSetFromList (map fst defines)

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
    let active = includeActive frames
        keep = (line++) . ('\n':)
    in case directiveNameFromLine line of
      Just "ifdef" ->
        pure (keep, guards, macros, pushIncludeFrame frames (maybe False (`symbolSetMember` macros) (directiveArgument "ifdef" line)))
      Just "ifndef" ->
        pure (keep, guards, macros, pushIncludeFrame frames (maybe False (not . (`symbolSetMember` macros)) (directiveArgument "ifndef" line)))
      Just "if" ->
        pure (keep, guards, macros, pushIncludeFrame frames (evalIncludeIf macros (directiveRest "if" line)))
      Just "elif" ->
        pure (keep, guards, macros, replaceIncludeElif frames (evalIncludeIf macros (directiveRest "elif" line)))
      Just "else" ->
        pure (keep, guards, macros, replaceIncludeElse frames)
      Just "endif" ->
        pure (keep, guards, macros, case frames of { [] -> []; _:xs -> xs })
      Just "define" | active ->
        pure (keep, guards, maybe macros (`symbolSetInsert` macros) (directiveArgument "define" line), frames)
      Just "undef" | active ->
        pure (keep, guards, maybe macros (`symbolSetDelete` macros) (directiveArgument "undef" line), frames)
      _ -> case includeName line of
        Just name | active -> do
          found <- findInclude currentDir name
          case found of
            Nothing -> pure (keep, guards, macros, frames)
            Just file ->
              if file `elem` stack
              then pure (id, guards, macros, frames)
              else do
                (expanded, guards', macros') <- expandFile stack guards macros file
                pure (expanded, guards', macros', frames)
        _ -> pure (keep, guards, macros, frames)

  findInclude currentDir name = do
    let candidates = hccPathJoin currentDir name : map (`hccPathJoin` name) includeDirs
    existing <- hccFilterExisting candidates
    pure (case existing of
      [] -> Nothing
      file:_ -> Just file)

includeName :: String -> Maybe String
includeName line = case words line of
  "#include":raw:_ -> stripIncludeDelims raw
  "#":"include":raw:_ -> stripIncludeDelims raw
  _ -> Nothing

stripIncludeDelims :: String -> Maybe String
stripIncludeDelims raw = case raw of
  '"':rest -> Just (takeWhile (/= '"') rest)
  '<':rest -> Just (takeWhile (/= '>') rest)
  _ -> Nothing

data IncludeFrame = IncludeFrame
  { includeParentActive :: Bool
  , includeBranchTaken :: Bool
  , includeFrameActive :: Bool
  }

includeActive :: [IncludeFrame] -> Bool
includeActive frames = case frames of
  [] -> True
  frame:_ -> includeFrameActive frame

pushIncludeFrame :: [IncludeFrame] -> Bool -> [IncludeFrame]
pushIncludeFrame frames cond =
  let parent = includeActive frames
      active = parent && cond
  in IncludeFrame parent active active : frames

replaceIncludeElif :: [IncludeFrame] -> Bool -> [IncludeFrame]
replaceIncludeElif frames cond = case frames of
  [] -> []
  frame:rest ->
    let active = includeParentActive frame && not (includeBranchTaken frame) && cond
        taken = includeBranchTaken frame || active
    in frame { includeBranchTaken = taken, includeFrameActive = active } : rest

replaceIncludeElse :: [IncludeFrame] -> [IncludeFrame]
replaceIncludeElse frames = case frames of
  [] -> []
  frame:rest ->
    let active = includeParentActive frame && not (includeBranchTaken frame)
    in frame { includeBranchTaken = True, includeFrameActive = active } : rest

directiveRest :: String -> String -> String
directiveRest directive line = case dropWhile isSpaceChar line of
  '#':rest -> afterDirective directive rest
  _ -> ""

afterDirective :: String -> String -> String
afterDirective directive text =
  let trimmed = dropWhile isSpaceChar text
  in if directive `prefixOf` trimmed
     then dropWhile isSpaceChar (drop (length directive) trimmed)
     else ""

evalIncludeIf :: SymbolSet -> String -> Bool
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
          | all isMacroNameChar atom -> symbolSetMember atom macros
          | otherwise -> False

    evalDefined raw =
      let rest = trim raw
      in case rest of
        '(' : xs -> symbolSetMember (takeWhile isMacroNameChar xs) macros
        _ -> symbolSetMember (takeWhile isMacroNameChar rest) macros

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

isMacroNameChar :: Char -> Bool
isMacroNameChar c =
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'

readDecimal :: String -> Int
readDecimal text = go 0 text where
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
skipLineRange start end sourceLines =
  kept 0 sourceLines
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

directiveArgument :: String -> String -> Maybe String
directiveArgument directive line = case words line of
  word:name:_ | word == "#" ++ directive -> Just name
  "#":word:name:_ | word == directive -> Just name
  _ -> Nothing

directiveNameFromLine :: String -> Maybe String
directiveNameFromLine line = case words line of
  "#":word:_ -> Just word
  word:_ | "#" `prefixOf` word -> Just (drop 1 word)
  _ -> Nothing

canonicalGuardName :: String -> String -> Bool
canonicalGuardName path guard =
  filenameTokens (hccTakeFileName path) == guardTokens guard

filenameTokens :: String -> [String]
filenameTokens name = splitNameTokens (map toUpperAscii name)

guardTokens :: String -> [String]
guardTokens name = splitNameTokens (map toUpperAscii name)

splitNameTokens :: String -> [String]
splitNameTokens text = filter (not . null) (go text "") where
  go rest current = case rest of
    [] -> [reverse current]
    c:cs ->
      if isNameChar c
      then go cs (c:current)
      else reverse current : go cs ""

isNameChar :: Char -> Bool
isNameChar c =
  (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

toUpperAscii :: Char -> Char
toUpperAscii c =
  if c >= 'a' && c <= 'z'
  then toEnum (fromEnum c - 32)
  else c
