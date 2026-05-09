module HccSystem where

import Base
import System

foreign import ccall "hcc_buffer_clear" hccBufferClear :: IO ()
foreign import ccall "hcc_buffer_put" hccBufferPut :: Char -> IO ()
foreign import ccall "hcc_stdout_buffer" hccStdoutBuffer :: IO ()
foreign import ccall "hcc_stderr_char" hccStderrChar :: Char -> IO ()
foreign import ccall "hcc_exit_success" hccExitSuccessRaw :: IO ()
foreign import ccall "hcc_exit_failure" hccExitFailureRaw :: IO ()
foreign import ccall "hcc_read_file" hccReadFileRaw :: IO Int
foreign import ccall "hcc_canonicalize" hccCanonicalizeRaw :: IO ()
foreign import ccall "hcc_does_file_exist" hccDoesFileExistRaw :: IO Int
foreign import ccall "hcc_result_len" hccResultLen :: IO Int
foreign import ccall "hcc_result_char" hccResultChar :: IO Char

hccInit :: IO ()
hccInit = pure ()

hccArgs :: IO [String]
hccArgs = getArgs

hccExitSuccess :: IO ()
hccExitSuccess = hccExitSuccessRaw

hccExitFailure :: IO a
hccExitFailure = hccExitFailureRaw >> hccExitFailure

hccPutStr :: String -> IO ()
hccPutStr text = withBuffer text hccStdoutBuffer

hccPutStrLn :: String -> IO ()
hccPutStrLn text = hccPutStr text >> hccPutStr "\n"

hccPutErrLine :: String -> IO ()
hccPutErrLine msg = mapM_ hccStderrChar msg >> hccStderrChar '\n'

hccReadFile :: String -> IO String
hccReadFile path = withBuffer path $ do
  ok <- hccReadFileRaw
  case ok == 0 of
    True -> hccPutErrLine ("hcc: cannot read " ++ path) >> hccExitFailure
    False -> readResult

hccCanonicalizePath :: String -> IO String
hccCanonicalizePath path = withBuffer path $ hccCanonicalizeRaw >> readResult

hccDoesFileExist :: String -> IO Bool
hccDoesFileExist path = withBuffer path hccDoesFileExistBuffered

hccDoesFileExistBuffered :: IO Bool
hccDoesFileExistBuffered = do
  exists <- hccDoesFileExistRaw
  pure (exists /= 0)

hccFilterExisting :: [String] -> IO [String]
hccFilterExisting paths = case paths of
  [] -> pure []
  path:rest -> do
    exists <- hccDoesFileExist path
    kept <- hccFilterExisting rest
    pure (if exists then path:kept else kept)

hccPathJoin :: String -> String -> String
hccPathJoin left right = case null left of
  True -> right
  False -> case null right of
    True -> left
    False -> case last left == '/' of
      True -> left ++ right
      False -> left ++ "/" ++ right

hccTakeDirectory :: String -> String
hccTakeDirectory path = case dropWhile (/= '/') (reverse path) of
  [] -> "."
  '/':rest -> case reverse rest of
    [] -> "/"
    dir -> dir
  _ -> "."

hccTakeFileName :: String -> String
hccTakeFileName path = reverse (takeWhile (/= '/') (reverse path))

withBuffer :: String -> IO a -> IO a
withBuffer text action = hccBufferClear >> mapM_ hccBufferPut text >> action

readResult :: IO String
readResult = do
  len <- hccResultLen
  go len []
  where
    go remaining acc =
      if remaining <= 0
      then pure (reverse acc)
      else do
        c <- hccResultChar
        go (remaining - 1) (c:acc)
