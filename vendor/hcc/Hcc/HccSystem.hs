module HccSystem where

import Base
import System

foreign import ccall "hcc_buffer_clear" hccBufferClear :: IO ()
foreign import ccall "hcc_buffer_put" hccBufferPut :: Char -> IO ()
foreign import ccall "hcc_stderr_char" hccStderrChar :: Char -> IO ()
foreign import ccall "hcc_exit_success" hccExitSuccessRaw :: IO ()
foreign import ccall "hcc_exit_failure" hccExitFailureRaw :: IO ()
foreign import ccall "hcc_open_read" hccOpenRead :: IO Int
foreign import ccall "hcc_open_write" hccOpenWrite :: IO Int
foreign import ccall "hcc_handle_eof" hccHandleEof :: Int -> IO Int
foreign import ccall "hcc_handle_read_char" hccHandleReadChar :: Int -> IO Char
foreign import ccall "hcc_handle_write_char" hccHandleWriteChar :: Int -> Char -> IO ()
foreign import ccall "hcc_handle_write_buffer" hccHandleWriteBuffer :: Int -> IO ()
foreign import ccall "hcc_handle_flush" hccHandleFlush :: Int -> IO ()
foreign import ccall "hcc_close" hccClose :: Int -> IO ()
foreign import ccall "hcc_canonicalize" hccCanonicalizeRaw :: IO ()
foreign import ccall "hcc_does_file_exist" hccDoesFileExistRaw :: IO Int
foreign import ccall "hcc_result_eof" hccResultEof :: IO Int
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
hccPutStr = putStr

hccPutStrLn :: String -> IO ()
hccPutStrLn = putStrLn

hccPutErrLine :: String -> IO ()
hccPutErrLine msg = mapM_ hccStderrChar msg >> hccStderrChar '\n'

hccReadFile :: String -> IO String
hccReadFile path = withBuffer path (hccReadFileBuffered path)

hccReadFileBuffered :: String -> IO String
hccReadFileBuffered path = do
  handle <- hccOpenRead
  case handle == 0 of
    True -> hccPutErrLine ("hcc: cannot read " ++ path) >> hccExitFailure
    False -> do
      text <- readHandle handle
      hccClose handle
      pure text

hccOpenWriteFile :: String -> IO Int
hccOpenWriteFile path = withBuffer path hccOpenWrite

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

readHandle :: Int -> IO String
readHandle handle = do
  done <- hccHandleEof handle
  case done /= 0 of
    True -> pure []
    False -> do
      c <- hccHandleReadChar handle
      rest <- readHandle handle
      pure (c:rest)

readResult :: IO String
readResult = do
  done <- hccResultEof
  case done /= 0 of
    True -> pure []
    False -> do
      c <- hccResultChar
      rest <- readResult
      pure (c:rest)

hccWriteHandleText :: Int -> String -> IO ()
hccWriteHandleText handle text = withBuffer text (hccHandleWriteBuffer handle)

hccWriteHandleLines :: Int -> [String] -> IO ()
hccWriteHandleLines handle lines' = case lines' of
  [] -> pure ()
  line:rest -> do
    hccWriteHandleText handle line
    hccHandleWriteChar handle '\n'
    hccWriteHandleLines handle rest
