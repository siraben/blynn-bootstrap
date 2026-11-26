module IncludeExpand
  ( preprocessFileTokens
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

-- Logical lines are visited once. Buffer ordinary lines until a directive so
-- a macro invocation can span lines; a header without directives contributes
-- to the same buffer. Offsets still count lines in the include-expanded text.
data Output = Output Int [String] ([Token] -> [Token])

preprocessFileTokens :: [String] -> [(String, String)] -> String -> IO [Token]
preprocessFileTokens includeDirs defines path = do
  initial <- requirePP (foldM addDefine symbolMapEmpty defines)
  (out, _, macros) <- expandFile (0 :: Int) symbolSetEmpty initial (Output (1 + length defines) [] id) path
  flushed <- flush macros out
  case flushed of
    Output _ _ build -> pure (build [])
  where
    sp = Span (SrcPos 1 1) (SrcPos 1 1)
    addDefine macros (name, value) = defineMacro macros sp (name ++ " " ++ value)

    flush macros out@(Output next pending build) = case pending of
      [] -> pure out
      _ -> do
        let text = foldl (\rest line -> line ++ '\n':rest) "" pending
        toks <- case lexCAt (next - length pending) text of
          Left (LexError pos msg) -> requirePP (Left (PreprocessError pos msg))
          Right result -> pure result
        expanded <- requirePP (expandTokens macros toks)
        pure (Output next [] (build . (expanded ++)))

    expandFile depth once macros out file = do
      key <- hccCanonicalizePath file
      if symbolSetMember key once
        then pure (out, once, macros)
        else if depth >= 200
          then die "hcpp: include nesting exceeds 200" >> pure (out, once, macros)
          else do
            source <- hccReadFile key
            normalized <- case normalizeSource source of
              Left msg -> die (key ++ ":" ++ msg) >> pure ""
              Right text -> pure text
            expandLines key depth once macros [] out (lines normalized)

    expandLines key depth once macros frames out ls = case ls of
      [] ->
        if null frames then pure (out, once, macros)
        else die ("hcpp: unterminated conditional in " ++ key) >> pure (out, once, macros)
      line:rest -> do
        (next, once', macros', frames') <- expandLine key depth once macros frames out line
        expandLines key depth once' macros' frames' next rest

    expandLine key depth once macros frames out@(Output next pending build) line =
      case dropWhile isSpaceChar line of
        '#':_ -> handleDirective key depth once macros frames out (parseDirective line)
        _ -> do
          let kept = if ifStackActive frames then line else ""
          pure (Output (next + 1) (kept:pending) build, once, macros, frames)

    handleDirective key depth once macros frames out directive = case directive of
      Directive "include" rest | ifStackActive frames -> do
        request <- requirePP (includeRequest macros rest)
        case request of
          Nothing -> die "hcpp: invalid active #include operand" >> pure (out, once, macros, frames)
          Just name -> do
            found <- findInclude (hccTakeDirectory key) name
            case found of
              Nothing -> die ("hcpp: cannot find include file " ++ show name) >> pure (out, once, macros, frames)
              Just file -> do
                (expanded, once', macros') <- expandFile (depth + 1) once macros out file
                pure (expanded, once', macros', frames)
      _ -> do
        flushed <- flush macros out
        case flushed of
          Output next _ build -> do
            let after = Output (next + 1) [] build
            let linePos = SrcPos next 1
            let lineSpan = Span linePos linePos
            transition <- requirePP (transitionDirective macros frames lineSpan directive)
            case transition of
              Just (macros', frames') -> pure (after, once, macros', frames')
              Nothing -> case directive of
                Directive "pragma" rest | ifStackActive frames && trim rest == "once" ->
                  pure (after, symbolSetInsert key once, macros, frames)
                Directive name _ ->
                  if not (ifStackActive frames) || name `elem` ["", "line", "pragma"] || all isDigitChar name
                    then pure (after, once, macros, frames)
                    else requirePP (Left (PreprocessError linePos ("unsupported directive: #" ++ name)))

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
