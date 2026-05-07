module HccSystem where

import Base
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import System.Directory (canonicalizePath, doesFileExist, findExecutable)
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath ((</>), takeDirectory, takeFileName)
import System.IO (hPutStrLn, stderr)
import System.Process (callProcess)

hccInit :: IO ()
hccInit = setLocaleEncoding utf8

hccArgs :: IO [String]
hccArgs = getArgs

hccExitSuccess :: IO ()
hccExitSuccess = exitSuccess

hccExitFailure :: IO a
hccExitFailure = exitFailure

hccPutStr :: String -> IO ()
hccPutStr = putStr

hccPutStrLn :: String -> IO ()
hccPutStrLn = putStrLn

hccPutErrLine :: String -> IO ()
hccPutErrLine = hPutStrLn stderr

hccReadFileOrStdin :: String -> IO String
hccReadFileOrStdin path =
  if path == "-"
  then getContents
  else readFile path

hccReadFile :: String -> IO String
hccReadFile = readFile

hccWriteFile :: String -> String -> IO ()
hccWriteFile = writeFile

hccLookupEnv :: String -> IO (Maybe String)
hccLookupEnv = lookupEnv

hccFindExecutable :: String -> IO (Maybe String)
hccFindExecutable = findExecutable

hccCallProcess :: String -> [String] -> IO ()
hccCallProcess = callProcess

hccCanonicalizePath :: String -> IO String
hccCanonicalizePath = canonicalizePath

hccDoesFileExist :: String -> IO Bool
hccDoesFileExist = doesFileExist

hccFilterExisting :: [String] -> IO [String]
hccFilterExisting paths = case paths of
  [] -> pure []
  path:rest -> do
    exists <- hccDoesFileExist path
    kept <- hccFilterExisting rest
    pure (if exists then path:kept else kept)

hccPathJoin :: String -> String -> String
hccPathJoin = (</>)

hccTakeDirectory :: String -> String
hccTakeDirectory = takeDirectory

hccTakeFileName :: String -> String
hccTakeFileName = takeFileName
