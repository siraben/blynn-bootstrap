module Main where

import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Control.Monad (filterM)
import Data.Char (isAlphaNum)
import qualified Data.Set as Set
import System.Directory (findExecutable)
import System.Directory (canonicalizePath)
import System.Directory (doesFileExist)
import System.Environment (getArgs)
import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath ((</>), takeDirectory, takeFileName)
import System.IO (hPutStrLn, stderr)
import System.Process (callProcess)

import qualified Hcc.CompileM as CompileM
import Hcc.CodegenM1
import Hcc.Lexer
import Hcc.Lower
import Hcc.Parser
import Hcc.Preprocessor
import Hcc.Token

main :: IO ()
main = do
  setLocaleEncoding utf8
  args <- getArgs
  case args of
    [] -> die "hcc: no input files"
    ["--help"] -> usage >> exitSuccess
    "--lex-dump":files -> lexDump files
    "--pp-dump":files -> ppDump files
    "--expand-dump":dumpArgs -> expandDump dumpArgs
    "--parse-dump":files -> parseDump files
    "--ir-dump":files -> irDump files
    "--check":files -> checkFiles files
    _ | "-S" `elem` args -> compileAssembly args
    _ -> compileWithCc args

usage :: IO ()
usage = putStrLn "usage: hcc [CC-ARGS...]\n       hcc -S [-o FILE] INPUT.c\n       hcc --check FILE...\n       hcc --lex-dump FILE...\n       hcc --pp-dump FILE...\n       hcc --expand-dump FILE...\n       hcc --parse-dump FILE...\n       hcc --ir-dump FILE..."

die :: String -> IO ()
die msg = hPutStrLn stderr msg >> exitFailure

lexDump :: [String] -> IO ()
lexDump files = case files of
  [] -> die "hcc: no input files"
  _ -> mapM_ lexDumpFile files

lexDumpFile :: String -> IO ()
lexDumpFile path = do
  source <- if path == "-" then getContents else readFile path
  case lexC source of
    Left (LexError pos msg) -> die (path ++ ":" ++ showPos pos ++ ": " ++ msg)
    Right toks -> mapM_ (putStrLn . renderToken) toks

ppDump :: [String] -> IO ()
ppDump files = case files of
  [] -> die "hcc: no input files"
  _ -> mapM_ ppDumpFile files

ppDumpFile :: String -> IO ()
ppDumpFile path = do
  source <- if path == "-" then getContents else readFile path
  case preprocessSource source of
    Left msg -> die (path ++ ":" ++ msg)
    Right toks -> mapM_ (putStrLn . renderToken) toks

expandDump :: [String] -> IO ()
expandDump args = case assemblyArgs ("-S":args) of
  Left msg -> die msg
  Right opts -> do
    source <- readSourceWithIncludes (asmIncludeDirs opts) (asmInput opts)
    putStr (renderDefines (asmDefines opts) ++ source)

preprocessSource :: String -> Either String [Token]
preprocessSource source = case lexC (stripComments (spliceContinuations source)) of
  Left (LexError pos msg) -> Left (showPos pos ++ ": " ++ msg)
  Right toks -> mapPreprocessError (preprocess toks)

spliceContinuations :: String -> String
spliceContinuations source = case source of
  [] -> []
  '\\':'\r':'\n':rest -> spliceContinuations rest
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
  source <- if path == "-" then getContents else readFile path
  case preprocessSource source >>= mapParseError . parseProgram of
    Left msg -> die (path ++ ":" ++ msg)
    Right ast -> print ast

irDump :: [String] -> IO ()
irDump files = case files of
  [] -> die "hcc: no input files"
  _ -> mapM_ irDumpFile files

irDumpFile :: String -> IO ()
irDumpFile path = do
  source <- if path == "-" then getContents else readFile path
  case preprocessSource source >>= mapParseError . parseProgram >>= mapCompileError . lowerProgram of
    Left msg -> die (path ++ ":" ++ msg)
    Right ir -> print ir

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
  source <- if path == "-" then getContents else readFile path
  case preprocessSource source >>= mapParseError . parseProgram of
    Left msg -> die (path ++ ":" ++ msg)
    Right _ -> pure ()

compileWithCc :: [String] -> IO ()
compileWithCc args = do
  cc <- resolveCc
  callProcess cc args

compileAssembly :: [String] -> IO ()
compileAssembly args = do
  case assemblyArgs args of
    Left msg -> die msg
    Right opts -> do
      source <- readSourceWithIncludes (asmIncludeDirs opts) (asmInput opts)
      let sourceWithDefines = renderDefines (asmDefines opts) ++ source
      case preprocessSource sourceWithDefines >>= mapParseError . parseProgram >>= mapCodegenError . codegenM1WithDataPrefix (dataLabelPrefix (asmInput opts)) of
        Left msg -> die (asmInput opts ++ ":" ++ msg)
        Right asm -> writeFile (asmOutput opts) asm

dataLabelPrefix :: FilePath -> String
dataLabelPrefix path =
  "HCC_DATA_" ++ sanitized
  where
    sanitized = case sanitizeLabel (takeFileName path) of
      [] -> "unit"
      text -> text

sanitizeLabel :: String -> String
sanitizeLabel text = case text of
  [] -> []
  c:rest -> sanitizeChar c ++ sanitizeLabel rest
  where
    sanitizeChar c =
      if isAlphaNum c then [c] else "_"

data AsmOptions = AsmOptions
  { asmInput :: FilePath
  , asmOutput :: FilePath
  , asmIncludeDirs :: [FilePath]
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

renderDefinesBuilder :: [(String, String)] -> ShowS
renderDefinesBuilder defs = case defs of
  [] -> id
  (name, value):rest ->
    showString "#define "
    . showString name
    . showChar ' '
    . showString value
    . showChar '\n'
    . renderDefinesBuilder rest

readSourceWithIncludes :: [FilePath] -> FilePath -> IO String
readSourceWithIncludes includeDirs path = do
  (builder, _) <- expandFile [] Set.empty path
  pure (builder "")
  where

  expandFile stack guards file = do
    key <- canonicalizePath file
    if key `elem` stack
      then pure (id, guards)
      else do
        source <- readFile key
        case includeGuard key source of
          Just (PragmaOnce guard) | guard `Set.member` guards ->
            pure (id, guards)
          Just (IfndefGuard guard start end) | guard `Set.member` guards ->
            expandLines (takeDirectory key) (key:stack) guards (skipLineRange start end (lines source))
          guardInfo -> do
            let guards' = case guardInfo of
                  Nothing -> guards
                  Just (PragmaOnce guard) -> Set.insert guard guards
                  Just (IfndefGuard guard _ _) -> Set.insert guard guards
            expandLines (takeDirectory key) (key:stack) guards' (lines source)

  expandLines currentDir stack guards ls = case ls of
    [] -> pure (id, guards)
    line:rest -> do
      (expanded, guards') <- expandIncludeLine currentDir stack guards line
      (tailText, guards'') <- expandLines currentDir stack guards' rest
      pure (expanded . tailText, guards'')

  expandIncludeLine currentDir stack guards line = case includeName line of
    Nothing -> pure (showString line . showChar '\n', guards)
    Just name -> do
      found <- findInclude currentDir name
      case found of
        Nothing -> pure (showString line . showChar '\n', guards)
        Just file ->
          if file `elem` stack
          then pure (id, guards)
          else expandFile stack guards file

  findInclude currentDir name = do
    let candidates = (currentDir </> name) : map (</> name) includeDirs
    existing <- filterM doesFileExist candidates
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

data IncludeGuard
  = PragmaOnce String
  | IfndefGuard String Int Int
  deriving (Eq, Show)

includeGuard :: FilePath -> String -> Maybe IncludeGuard
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

canonicalGuardName :: FilePath -> String -> Bool
canonicalGuardName path guard =
  filenameTokens (takeFileName path) == guardTokens guard

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
isSpaceChar c = c == ' ' || c == '\t' || c == '\r' || c == '\n'

replaceExt :: FilePath -> String -> FilePath
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

mapCompileError :: Either CompileM.CompileError a -> Either String a
mapCompileError result = case result of
  Left (CompileM.CompileError msg) -> Left msg
  Right x -> Right x

resolveCc :: IO FilePath
resolveCc = do
  override <- lookupEnv "HCC_BACKEND_CC"
  case override of
    Just cc -> pure cc
    Nothing -> do
      found <- findExecutable "cc"
      case found of
        Just cc -> pure cc
        Nothing -> die "hcc: temporary cc backend needs `cc` on PATH or HCC_BACKEND_CC" >> pure "cc"

showPos :: SrcPos -> String
showPos (SrcPos line col) = show line ++ ":" ++ show col
