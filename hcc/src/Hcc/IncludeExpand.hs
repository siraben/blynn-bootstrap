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

-- The include walk and the final token pass share macro parsing, expansion,
-- conditional arithmetic and eligibility. Header definitions flow back to the
-- includer; inactive definitions never enter the environment.
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
          expandLines key depth once macros [] (lines (stripComments (spliceContinuations source)))

  expandLines key depth once macros frames ls = case ls of
    [] ->
      if null frames then pure (id, once, macros)
      else die ("hcpp: unterminated conditional in " ++ key) >> pure (id, once, macros)
    line:rest -> do
      (expanded, once', macros', frames') <- expandLine key depth once macros frames line
      (tailText, once'', macros'') <- expandLines key depth once' macros' frames' rest
      pure (expanded . tailText, once'', macros'')

  expandLine key depth once macros frames line =
    let active = ifStackActive frames
        keep = (line++) . ('\n':)
        condition directive = do
          frames' <- case applyIfDirective frames directive of
            Just result -> pure result
            Nothing -> die ("hcpp: unmatched conditional in " ++ key) >> pure frames
          pure (keep, once, macros, frames')
    in case parseDirective line of
      Directive "ifdef" rest -> condition (IfCondition (maybe False (`symbolMapMember` macros) (directiveName rest)))
      Directive "ifndef" rest -> condition (IfCondition (maybe False (not . (`symbolMapMember` macros)) (directiveName rest)))
      Directive "if" rest -> do
        value <- requirePP (evalEligibleIf active macros rest)
        condition (IfCondition value)
      Directive "elif" rest -> do
        value <- requirePP (evalEligibleIf (elifEligible frames) macros rest)
        condition (ElifCondition value)
      Directive "else" _ -> condition ElseCondition
      Directive "endif" _ -> condition EndifCondition
      Directive "define" rest | active -> do
        macros' <- requirePP (defineMacro macros sp rest)
        pure (keep, once, macros', frames)
      Directive "undef" rest | active ->
        case directiveName rest of
          Just name -> pure (keep, once, symbolMapDelete name macros, frames)
          Nothing -> die "hcpp: #undef without macro name" >> pure (keep, once, macros, frames)
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
