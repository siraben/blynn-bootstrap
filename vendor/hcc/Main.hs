module Main where

import Base
import Ast (renderProgram)
import CompileM
import CodegenM1 hiding (line, mapCompileError)
import HccSystem
import Ir (renderModuleIr)
import Lexer hiding (charCode, isAsciiAlpha, isAsciiAlphaNum, isDigit, isHexDigit, isIdentChar, isIdentStart, lexerIsSpace, prefixOf)
import Lower
import Parser hiding (stringLiteral)
import Preprocessor hiding (charCode, directiveName, dropSpaces, isAsciiAlpha, isAsciiAlphaNum, isDigitChar, isIdentChar, isIdentStart, ppIsSpace, prefixOf, spanStart, suffixOf, token, tokenKind, tokenStart, tokens, trim)
import SymbolTable
import Token

main :: IO ()
main = do
  hccInit
  args <- hccArgs
  case args of
    [] -> die "hcc: no input files"
    ["--help"] -> usage >> hccExitSuccess
    "--lex-dump":files -> lexDump files
    "--pp-dump":files -> ppDump files
    "--expand-dump":dumpArgs -> expandDump dumpArgs
    "--parse-dump":files -> parseDump files
    "--ir-dump":files -> irDump files
    "--lower-check":files -> lowerCheck files
    "--codegen-check":files -> codegenCheck files
    "--check":files -> checkFiles files
    _ | "-S" `elem` args -> compileAssembly args
    _ -> compileWithCc args

usage :: IO ()
usage = hccPutStrLn "usage: hcc [CC-ARGS...]\n       hcc -S [-o FILE] INPUT.c\n       hcc --check FILE...\n       hcc --lex-dump FILE...\n       hcc --pp-dump FILE...\n       hcc --expand-dump FILE...\n       hcc --parse-dump FILE...\n       hcc --ir-dump FILE..."

die :: String -> IO ()
die msg = hccPutErrLine msg >> hccExitFailure

lexDump :: [String] -> IO ()
lexDump files = case files of
  [] -> die "hcc: no input files"
  _ -> mapM_ lexDumpFile files

lexDumpFile :: String -> IO ()
lexDumpFile path = do
  source <- hccReadFileOrStdin path
  case lexC source of
    Left (LexError pos msg) -> die (path ++ ":" ++ showPos pos ++ ": " ++ msg)
    Right toks -> mapM_ (hccPutStrLn . renderToken) toks

ppDump :: [String] -> IO ()
ppDump files = case files of
  [] -> die "hcc: no input files"
  _ -> mapM_ ppDumpFile files

ppDumpFile :: String -> IO ()
ppDumpFile path = do
  source <- hccReadFileOrStdin path
  case preprocessSource source of
    Left msg -> die (path ++ ":" ++ msg)
    Right toks -> mapM_ (hccPutStrLn . renderToken) toks

expandDump :: [String] -> IO ()
expandDump args = case assemblyArgs ("-S":args) of
  Left msg -> die msg
  Right opts -> do
    source <- readSourceWithIncludes (asmIncludeDirs opts) (asmDefines opts) (asmInput opts)
    hccPutStr (renderDefines (asmDefines opts) ++ source)

preprocessSource :: String -> Either String [Token]
preprocessSource source = case lexC (stripComments (spliceContinuations source)) of
  Left (LexError pos msg) -> Left (showPos pos ++ ": " ++ msg)
  Right toks -> mapPreprocessError (preprocess toks)

spliceContinuations :: String -> String
spliceContinuations source = case source of
  [] -> []
  '\\':c:'\n':rest ->
    if charCode c == 13
      then spliceContinuations rest
      else '\\' : c : '\n' : spliceContinuations rest
  '\\':'\n':rest -> spliceContinuations rest
  c:rest -> c : spliceContinuations rest

stripComments :: String -> String
stripComments source = normal source where
  normal text = case text of
    [] -> []
    '/':'/':rest -> lineComment rest
    '/':'*':rest -> blockComment 1 rest
    '"':rest -> '"' : stringLiteral rest
    '\'':rest -> '\'' : charLiteral rest
    c:rest -> c : normal rest

  lineComment text = case text of
    [] -> []
    '\n':rest -> '\n' : normal rest
    _:rest -> lineComment rest

  blockComment :: Int -> String -> String
  blockComment depth text = case text of
    [] -> []
    '/':'*':rest -> blockComment (depth + 1) rest
    '*':'/':rest ->
      if depth == 1
        then ' ' : normal rest
        else blockComment (depth - 1) rest
    '\n':rest -> '\n' : blockComment depth rest
    _:rest -> blockComment depth rest

  stringLiteral text = case text of
    [] -> []
    '\\':c:rest -> '\\' : c : stringLiteral rest
    '"':rest -> '"' : normal rest
    c:rest -> c : stringLiteral rest

  charLiteral text = case text of
    [] -> []
    '\\':c:rest -> '\\' : c : charLiteral rest
    '\'':rest -> '\'' : normal rest
    c:rest -> c : charLiteral rest

mapPreprocessError :: Either PreprocessError a -> Either String a
mapPreprocessError result = case result of
  Left (PreprocessError pos msg) -> Left (showPos pos ++ ": " ++ msg)
  Right toks -> Right toks

parseDump :: [String] -> IO ()
parseDump files = case files of
  [] -> die "hcc: no input files"
  _ -> mapM_ parseDumpFile files

parseDumpFile :: String -> IO ()
parseDumpFile path = do
  source <- hccReadFileOrStdin path
  case preprocessSource source >>= mapParseError . parseProgram of
    Left msg -> die (path ++ ":" ++ msg)
    Right ast -> hccPutStrLn (renderProgram ast)

irDump :: [String] -> IO ()
irDump files = case files of
  [] -> die "hcc: no input files"
  _ -> mapM_ irDumpFile files

irDumpFile :: String -> IO ()
irDumpFile path = do
  source <- hccReadFileOrStdin path
  case preprocessSource source >>= mapParseError . parseProgram >>= mapCompileError . lowerProgram of
    Left msg -> die (path ++ ":" ++ msg)
    Right ir -> hccPutStrLn (renderModuleIr ir)

lowerCheck :: [String] -> IO ()
lowerCheck files = case files of
  [] -> die "hcc: no input files"
  _ -> mapM_ lowerCheckFile files

lowerCheckFile :: String -> IO ()
lowerCheckFile path = do
  source <- hccReadFileOrStdin path
  case preprocessSource source >>= mapParseError . parseProgram >>= mapCompileError . lowerProgram of
    Left msg -> die (path ++ ":" ++ msg)
    Right _ -> pure ()

codegenCheck :: [String] -> IO ()
codegenCheck files = case files of
  [] -> die "hcc: no input files"
  _ -> mapM_ codegenCheckFile files

codegenCheckFile :: String -> IO ()
codegenCheckFile path = do
  source <- hccReadFileOrStdin path
  case preprocessSource source >>= mapParseError . parseProgram >>= mapCodegenError . codegenM1WithDataPrefix (dataLabelPrefix path) of
    Left msg -> die (path ++ ":" ++ msg)
    Right _ -> pure ()

mapParseError :: Either ParseError a -> Either String a
mapParseError result = case result of
  Left (ParseError pos msg) -> Left (showPos pos ++ ": " ++ msg)
  Right ast -> Right ast

checkFiles :: [String] -> IO ()
checkFiles files = case files of
  [] -> die "hcc: no input files"
  _ -> mapM_ checkFile files

checkFile :: String -> IO ()
checkFile path = do
  source <- hccReadFileOrStdin path
  case preprocessSource source >>= mapParseError . parseProgram of
    Left msg -> die (path ++ ":" ++ msg)
    Right _ -> pure ()

compileWithCc :: [String] -> IO ()
compileWithCc args = do
  cc <- resolveCc
  hccCallProcess cc args

compileAssembly :: [String] -> IO ()
compileAssembly args = do
  case assemblyArgs args of
    Left msg -> die msg
    Right opts -> do
      trace <- hccTraceAsm
      hccTrace trace "reading source"
      source <- readSourceWithIncludes (asmIncludeDirs opts) (asmDefines opts) (asmInput opts)
      let sourceWithDefines = renderDefines (asmDefines opts) ++ source
      hccTrace trace "preprocessing"
      case preprocessSource sourceWithDefines of
        Left msg -> die (asmInput opts ++ ":" ++ msg)
        Right toks -> do
          hccTrace trace "parsing"
          case mapParseError (parseProgram toks) of
            Left msg -> die (asmInput opts ++ ":" ++ msg)
            Right ast -> do
              hccTrace trace "opening assembly"
              handle <- hccOpenWriteFile (asmOutput opts)
              case handle == 0 of
                True -> die ("hcc: cannot write " ++ asmOutput opts)
                False -> do
                  hccTrace trace "writing assembly"
                  result <- codegenM1WriteTraceWithDataPrefix (hccWriteAndFlushLines handle) (hccTrace trace) (dataLabelPrefix (asmInput opts)) ast
                  hccClose handle
                  case result of
                    Left (CodegenError msg) -> die (asmInput opts ++ ":" ++ msg)
                    Right _ -> hccTrace trace "done"

hccWriteAndFlushLines :: Int -> [String] -> IO ()
hccWriteAndFlushLines handle lines' = do
  hccWriteHandleLines handle lines'
  hccHandleFlush handle

hccTraceAsm :: IO Bool
hccTraceAsm = do
  value <- hccLookupEnv "HCC_TRACE_ASM"
  case value of
    Nothing -> pure False
    Just _ -> pure True

hccTrace :: Bool -> String -> IO ()
hccTrace enabled msg =
  if enabled
    then hccPutErrLine ("hcc: " ++ msg)
    else pure ()

dataLabelPrefix :: String -> String
dataLabelPrefix path =
  "HCC_DATA_" ++ sanitized
  where
    sanitized = case sanitizeLabel (hccTakeFileName path) of
      [] -> "unit"
      text -> text

sanitizeLabel :: String -> String
sanitizeLabel text = case text of
  [] -> []
  c:rest -> sanitizeChar c ++ sanitizeLabel rest
  where
    sanitizeChar c =
      if isAsciiAlphaNum c then [c] else "_"

isAsciiAlphaNum :: Char -> Bool
isAsciiAlphaNum c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

data AsmOptions = AsmOptions
  { asmInput :: String
  , asmOutput :: String
  , asmIncludeDirs :: [String]
  , asmDefines :: [(String, String)]
  } deriving (Eq, Show)

assemblyArgs :: [String] -> Either String AsmOptions
assemblyArgs args = finish (go args Nothing Nothing [] []) where
  finish parsed = case parsed of
    Left msg -> Left msg
    Right (out, input, includes, defines) -> case input of
      Nothing -> Left "hcc: no input files"
      Just path -> Right (AsmOptions path (maybe (replaceExt path ".M1") id out) (reverse includes) (reverse defines))

  go rest out input includes defines = case rest of
    [] -> Right (out, input, includes, defines)
    "-S":xs -> go xs out input includes defines
    "-o":path:xs -> go xs (Just path) input includes defines
    "-I":path:xs -> go xs out input (path:includes) defines
    "-D":def:xs -> go xs out input includes (parseDefine def:defines)
    flag:xs | "-I" `prefixOf` flag && length flag > 2 ->
      go xs out input (drop 2 flag:includes) defines
    flag:xs | "-D" `prefixOf` flag && length flag > 2 ->
      go xs out input includes (parseDefine (drop 2 flag):defines)
    flag:xs | ignoredAssemblyFlag flag ->
      go xs out input includes defines
    flag:_ | take 1 flag == "-" -> Left ("hcc: unsupported -S option: " ++ flag)
    path:xs -> go xs out (Just path) includes defines

ignoredAssemblyFlag :: String -> Bool
ignoredAssemblyFlag flag =
  flag `elem` ["-c", "-pipe", "-nostdinc", "-nostdlib", "-static"]

parseDefine :: String -> (String, String)
parseDefine def = case break (== '=') def of
  (name, "") -> (name, "1")
  (name, _:value) -> (name, unescapeDefineValue value)

unescapeDefineValue :: String -> String
unescapeDefineValue value = case value of
  [] -> []
  '\\':'"':rest -> '"' : unescapeDefineValue rest
  c:rest -> c : unescapeDefineValue rest

renderDefines :: [(String, String)] -> String
renderDefines defs = renderDefinesBuilder defs ""

renderDefinesBuilder :: [(String, String)] -> String -> String
renderDefinesBuilder defs = case defs of
  [] -> id
  (name, value):rest ->
    ("#define "++)
    . (name++)
    . (' ':)
    . (value++)
    . ('\n':)
    . renderDefinesBuilder rest

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
  } deriving (Eq, Show)

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

trim :: String -> String
trim = reverse . dropWhile isSpaceChar . reverse . dropWhile isSpaceChar

lastMaybe :: [a] -> Maybe a
lastMaybe xs = case xs of
  [] -> Nothing
  [x] -> Just x
  _:rest -> lastMaybe rest

isDigitChar :: Char -> Bool
isDigitChar c = c >= '0' && c <= '9'

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
  deriving (Eq, Show)

includeGuard :: String -> String -> Maybe IncludeGuard
includeGuard path source =
  let cleanedLines = lines (stripCommentsForDirectives source)
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

stripCommentsForDirectives :: String -> String
stripCommentsForDirectives source = normal source where
  normal :: String -> String
  normal text = case text of
    [] -> []
    '/':'/':rest -> lineComment rest
    '/':'*':rest -> blockComment 1 rest
    '"':rest -> '"' : stringLiteral rest
    '\'':rest -> '\'' : charLiteral rest
    c:rest -> c : normal rest

  lineComment :: String -> String
  lineComment text = case text of
    [] -> []
    '\n':rest -> '\n' : normal rest
    _:rest -> lineComment rest

  blockComment :: Int -> String -> String
  blockComment depth text
    | depth <= 0 = normal text
    | otherwise = case text of
        [] -> []
        '/':'*':rest -> blockComment (depth + 1) rest
        '*':'/':rest -> blockComment (depth - 1) rest
        '\n':rest -> '\n' : blockComment depth rest
        _:rest -> blockComment depth rest

  stringLiteral :: String -> String
  stringLiteral text = case text of
    [] -> []
    '\\':c:rest -> '\\' : c : stringLiteral rest
    '"':rest -> '"' : normal rest
    c:rest -> c : stringLiteral rest

  charLiteral :: String -> String
  charLiteral text = case text of
    [] -> []
    '\\':c:rest -> '\\' : c : charLiteral rest
    '\'':rest -> '\'' : normal rest
    c:rest -> c : charLiteral rest

isSpaceChar :: Char -> Bool
isSpaceChar c =
  c == ' ' || c == '\n' || charCode c == 9 || charCode c == 13

charCode :: Char -> Int
charCode = fromEnum

replaceExt :: String -> String -> String
replaceExt path ext = reverse (dropExt (reverse path)) ++ ext where
  dropExt xs = case xs of
    [] -> []
    '.':_ -> []
    c:rest -> c : dropExt rest

prefixOf :: String -> String -> Bool
prefixOf prefix text = take (length prefix) text == prefix

mapCodegenError :: Either CodegenError a -> Either String a
mapCodegenError result = case result of
  Left (CodegenError msg) -> Left msg
  Right x -> Right x

mapCompileError :: Either CompileError a -> Either String a
mapCompileError result = case result of
  Left (CompileError msg) -> Left msg
  Right x -> Right x

resolveCc :: IO String
resolveCc = do
  override <- hccLookupEnv "HCC_BACKEND_CC"
  case override of
    Just cc -> pure cc
    Nothing -> do
      found <- hccFindExecutable "cc"
      case found of
        Just cc -> pure cc
        Nothing -> die "hcc: temporary cc backend needs `cc` on PATH or HCC_BACKEND_CC" >> pure "cc"

showPos :: SrcPos -> String
showPos (SrcPos line col) = show line ++ ":" ++ show col
