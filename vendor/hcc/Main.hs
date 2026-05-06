module Main where

import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)

import Hcc.Lexer
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
    _ -> die "hcc: only --lex-dump is implemented"

usage :: IO ()
usage = putStrLn "usage: hcc --lex-dump FILE...\n       hcc --pp-dump FILE..."

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

showPos :: SrcPos -> String
showPos (SrcPos line col) = show line ++ ":" ++ show col
