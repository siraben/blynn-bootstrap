module Main where

import System.Directory (findExecutable)
import System.Environment (getArgs)
import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)
import System.Process (callProcess)

import Hcc.CodegenM1
import Hcc.Lexer
import Hcc.Parser
import Hcc.Preprocessor
import Hcc.Token

main :: IO ()
main = do
  args <- getArgs
  case args of
    [] -> die "hcc: no input files"
    ["--help"] -> usage >> exitSuccess
    "--lex-dump":files -> lexDump files
    "--pp-dump":files -> ppDump files
    "--parse-dump":files -> parseDump files
    "--check":files -> checkFiles files
    _ | "-S" `elem` args -> compileAssembly args
    _ -> compileWithCc args

usage :: IO ()
usage = putStrLn "usage: hcc [CC-ARGS...]\n       hcc -S [-o FILE] INPUT.c\n       hcc --check FILE...\n       hcc --lex-dump FILE...\n       hcc --pp-dump FILE...\n       hcc --parse-dump FILE..."

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
    Right (input, output) -> do
      source <- readFile input
      case preprocessSource source >>= mapParseError . parseProgram >>= mapCodegenError . codegenM1 of
        Left msg -> die (input ++ ":" ++ msg)
        Right asm -> writeFile output asm

assemblyArgs :: [String] -> Either String (FilePath, FilePath)
assemblyArgs args = go args Nothing Nothing where
  go rest out input = case rest of
    [] -> case input of
      Nothing -> Left "hcc: no input files"
      Just path -> Right (path, maybe (replaceExt path ".M1") id out)
    "-S":xs -> go xs out input
    "-o":path:xs -> go xs (Just path) input
    flag:_ | take 1 flag == "-" -> Left ("hcc: unsupported -S option: " ++ flag)
    path:xs -> go xs out (Just path)

replaceExt :: FilePath -> String -> FilePath
replaceExt path ext = reverse (dropExt (reverse path)) ++ ext where
  dropExt xs = case xs of
    [] -> []
    '.':_ -> []
    c:rest -> c : dropExt rest

mapCodegenError :: Either CodegenError a -> Either String a
mapCodegenError result = case result of
  Left (CodegenError msg) -> Left msg
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
