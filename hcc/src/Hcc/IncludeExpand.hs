module IncludeExpand
  ( readSourceWithIncludes
  ) where

import Base
import Directive
import DriverCommon
import HccSystem
import IfFrame
import Lexer
import Preprocessor
import SymbolTable
import TextUtil
import TypesToken

-- The include walk replays the shared macro/conditional transitions, retaining
-- directives for the token pass. Header definitions flow back to the includer.
readSourceWithIncludes :: [String] -> [(String, String)] -> String -> IO String
readSourceWithIncludes includeDirs defines path = do
  initial <- requirePP (foldM addDefine symbolMapEmpty defines)
  (builder, _, _) <- expandFile (0 :: Int) symbolSetEmpty initial path
  pure (builder "")
  where
  sp = Span (SrcPos 1 1) (SrcPos 1 1)
  addDefine macros (name, value) = defineMacro macros sp (name ++ " " ++ value)

  expandFile depth once macros file = do
    key <- hccCanonicalizePath file
    if symbolSetMember key once
      then pure (id, once, macros)
      else if depth >= 200
        then die "hcpp: include nesting exceeds 200" >> pure (id, once, macros)
        else do
          source <- hccReadFile key
          -- Translation phases 2 and 3 precede directive recognition, including
          -- continued macro definitions and comments containing apparent #ifs.
          normalized <- case normalizeSource source of
            Left msg -> die (key ++ ":" ++ msg) >> pure ""
            Right text -> pure text
          expandLines key depth once macros [] 1 (lines normalized)

  expandLines key depth once macros frames lineNumber ls = case ls of
    [] ->
      if null frames then pure (id, once, macros)
      else die ("hcpp: unterminated conditional in " ++ key) >> pure (id, once, macros)
    line:rest -> do
      (expanded, once', macros', frames') <- expandLine key depth once macros frames lineNumber line
      (tailText, once'', macros'') <- expandLines key depth once' macros' frames' (lineNumber + 1) rest
      pure (expanded . tailText, once'', macros'')

  expandLine key depth once macros frames lineNumber line = do
    let active = ifStackActive frames
        keep = (line++) . ('\n':)
        directive = parseDirective line
        lineSpan = Span (SrcPos lineNumber 1) (SrcPos lineNumber 1)
    transition <- requirePP (transitionDirective macros frames lineSpan directive)
    case transition of
      Just (macros', frames') -> pure (keep, once, macros', frames')
      Nothing -> case directive of
        Directive "pragma" rest | active && trim rest == "once" ->
          pure (keep, symbolSetInsert key once, macros, frames)
        Directive "include" rest | active -> do
          request <- requirePP (includeRequest macros rest)
          case request of
            Nothing -> die "hcpp: invalid active #include operand" >> pure (keep, once, macros, frames)
            Just name -> do
              found <- findInclude (hccTakeDirectory key) name
              case found of
                Nothing -> die ("hcpp: cannot find include file " ++ show name) >> pure (keep, once, macros, frames)
                Just file -> do
                  (expanded, once', macros') <- expandFile (depth + 1) once macros file
                  pure (expanded, once', macros', frames)
        _ -> pure (keep, once, macros, frames)

  findInclude currentDir name = do
    let candidates = hccPathJoin currentDir name : map (`hccPathJoin` name) includeDirs
    existing <- hccFilterExisting candidates
    pure (case existing of
      [] -> Nothing
      file:_ -> Just file)

requirePP :: Either PreprocessError a -> IO a
requirePP result = case result of
  Right value -> pure value
  Left (PreprocessError pos msg) -> do
    die ("hcpp:" ++ showPos pos ++ ": " ++ msg)
    requirePP result

includeRequest :: SymbolMap Macro -> String -> Either PreprocessError (Maybe String)
includeRequest macros text =
  -- Literal header names are not macro-expanded internally.
  case stripIncludeDelims (trim text) of
    Just name -> Right (Just name)
    Nothing -> do
      toks <- case lexC text of
        Left (LexError pos msg) -> Left (PreprocessError pos msg)
        Right result -> Right result
      expanded <- expandOperandText macros toks
      Right (stripIncludeDelims expanded)

stripIncludeDelims :: String -> Maybe String
stripIncludeDelims raw = case raw of
  '"':rest -> finish '"' rest
  '<':rest -> finish '>' rest
  _ -> Nothing
  where
  finish delim rest = case span (/= delim) rest of
    (name, _:tailText) | not (null name) && null (trim tailText) -> Just name
    _ -> Nothing
