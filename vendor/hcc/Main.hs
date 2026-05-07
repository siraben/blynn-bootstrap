module Main where

import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Control.Monad (filterM)
import System.Directory (findExecutable)
import System.Directory (doesFileExist)
import System.Environment (getArgs)
import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath ((</>), takeDirectory)
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
    "--parse-dump":files -> parseDump files
    "--ir-dump":files -> irDump files
    "--check":files -> checkFiles files
    _ | "-S" `elem` args -> compileAssembly args
    _ -> compileWithCc args

usage :: IO ()
usage = putStrLn "usage: hcc [CC-ARGS...]\n       hcc -S [-o FILE] INPUT.c\n       hcc --check FILE...\n       hcc --lex-dump FILE...\n       hcc --pp-dump FILE...\n       hcc --parse-dump FILE...\n       hcc --ir-dump FILE..."

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

preprocessSource :: String -> Either String [Token]
preprocessSource source = case lexC source of
  Left (LexError pos msg) -> Left (showPos pos ++ ": " ++ msg)
  Right toks -> mapPreprocessError (preprocess toks)

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
      case preprocessSource sourceWithDefines >>= mapParseError . parseProgram >>= mapCodegenError . codegenM1 of
        Left msg -> die (asmInput opts ++ ":" ++ msg)
        Right asm -> writeFile (asmOutput opts) asm

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
  (name, _:value) -> (name, value)

renderDefines :: [(String, String)] -> String
renderDefines defs = concatMap render defs where
  render (name, value) = "#define " ++ name ++ " " ++ value ++ "\n"

readSourceWithIncludes :: [FilePath] -> FilePath -> IO String
readSourceWithIncludes includeDirs path = expandFile [] path where
  expandFile stack file = do
    source <- readFile file
    expandLines (takeDirectory file) (file:stack) (lines source)

  expandLines currentDir stack ls = case ls of
    [] -> pure ""
    line:rest -> do
      expanded <- expandIncludeLine currentDir stack line
      tailText <- expandLines currentDir stack rest
      pure (expanded ++ tailText)

  expandIncludeLine currentDir stack line = case includeName line of
    Nothing -> pure (line ++ "\n")
    Just name -> do
      found <- findInclude currentDir name
      case found of
        Nothing -> pure (line ++ "\n")
        Just file ->
          if file `elem` stack
          then pure ""
          else expandFile stack file

  findInclude currentDir name = do
    let candidates = (currentDir </> name) : map (</> name) includeDirs
    existing <- filterM doesFileExist candidates
    pure (case existing of
      [] -> Nothing
      file:_ -> Just file)

includeName :: String -> Maybe String
includeName line = case words line of
  "#include":raw:_ -> stripIncludeDelims raw
  _ -> Nothing

stripIncludeDelims :: String -> Maybe String
stripIncludeDelims raw = case raw of
  '"':rest -> Just (takeWhile (/= '"') rest)
  '<':rest -> Just (takeWhile (/= '>') rest)
  _ -> Nothing

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
