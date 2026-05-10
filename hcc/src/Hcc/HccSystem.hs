module HccSystem where

import Base
import System

foreign import ccall "hcc_buffer_clear" hccBufferClear :: IO ()
foreign import ccall "hcc_buffer_put" hccBufferPut :: Char -> IO ()
foreign import ccall "hcc_buffer_put4" hccBufferPut4 :: Char -> Char -> Char -> Char -> IO ()
foreign import ccall "hcc_buffer_put8" hccBufferPut8 :: Char -> Char -> Char -> Char -> Char -> Char -> Char -> Char -> IO ()
foreign import ccall "hcc_stdout_buffer" hccStdoutBuffer :: IO ()
foreign import ccall "hcc_stderr_char" hccStderrChar :: Char -> IO ()
foreign import ccall "hcc_exit_success" hccExitSuccessRaw :: IO ()
foreign import ccall "hcc_exit_failure" hccExitFailureRaw :: IO ()
foreign import ccall "hcc_open_write" hccOpenWrite :: IO Int
foreign import ccall "hcc_read_file" hccReadFileRaw :: IO Int
foreign import ccall "hcc_handle_flush" hccHandleFlush :: Int -> IO ()
foreign import ccall "hcc_obuf_new" hccObufNew :: Int -> IO Word
foreign import ccall "hcc_obuf_free" hccObufFree :: Word -> IO ()
foreign import ccall "hcc_obuf_clear" hccObufClear :: Word -> IO ()
foreign import ccall "hcc_obuf_len" hccObufLen :: Word -> IO Int
foreign import ccall "hcc_obuf_put" hccObufPut :: Word -> Char -> IO ()
foreign import ccall "hcc_obuf_put4" hccObufPut4 :: Word -> Char -> Char -> Char -> Char -> IO ()
foreign import ccall "hcc_obuf_put8" hccObufPut8 :: Word -> Char -> Char -> Char -> Char -> Char -> Char -> Char -> Char -> IO ()
foreign import ccall "hcc_obuf_write" hccObufWrite :: Int -> Word -> IO ()
foreign import ccall "hcc_close" hccClose :: Int -> IO ()
foreign import ccall "hcc_canonicalize" hccCanonicalizeRaw :: IO ()
foreign import ccall "hcc_does_file_exist" hccDoesFileExistRaw :: IO Int
foreign import ccall "hcc_result_len" hccResultLen :: IO Int
foreign import ccall "hcc_result_at" hccResultAt :: Int -> IO Char

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
    False -> readRuntimeResult

hccOpenWriteFile :: String -> IO Int
hccOpenWriteFile path = withBuffer path hccOpenWrite

hccWithOpenWriteFile :: String -> (Int -> IO a) -> IO (Maybe a)
hccWithOpenWriteFile path action = do
  handle <- hccOpenWriteFile path
  case handle == 0 of
    True -> pure Nothing
    False -> do
      result <- action handle
      hccClose handle
      pure (Just result)

hccCanonicalizePath :: String -> IO String
hccCanonicalizePath path = withBuffer path $ hccCanonicalizeRaw >> readRuntimeResult

hccDoesFileExist :: String -> IO Bool
hccDoesFileExist path = withBuffer path hccDoesFileExistBuffered

hccDoesFileExistBuffered :: IO Bool
hccDoesFileExistBuffered = do
  exists <- hccDoesFileExistRaw
  pure (exists /= 0)

hccFilterExisting :: [String] -> IO [String]
hccFilterExisting [] = pure []
hccFilterExisting (path:rest) = do
  exists <- hccDoesFileExist path
  kept <- hccFilterExisting rest
  pure (if exists then path:kept else kept)

hccPathJoin :: String -> String -> String
hccPathJoin [] right = right
hccPathJoin left [] = left
hccPathJoin left right
  | last left == '/' = left ++ right
  | otherwise = left ++ "/" ++ right

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
withBuffer text action = do
  hccBufferClear
  hccBufferText text
  result <- action
  hccBufferClear
  pure result

hccBufferText :: String -> IO ()
hccBufferText text = case text of
  [] -> pure ()
  c1:c2:c3:c4:c5:c6:c7:c8:rest -> hccBufferPut8 c1 c2 c3 c4 c5 c6 c7 c8 >> hccBufferText rest
  c1:c2:c3:c4:rest -> hccBufferPut4 c1 c2 c3 c4 >> hccBufferText rest
  c:rest -> hccBufferPut c >> hccBufferText rest

readRuntimeResult :: IO String
readRuntimeResult = do
  len <- hccResultLen
  go (len - 1) []
  where
    go index acc =
      if index < 0
      then pure acc
      else do
        c <- hccResultAt index
        go (index - 1) (c:acc)

hccWriteHandleLines :: Int -> [String] -> IO ()
hccWriteHandleLines handle lines' = hccWithObuf outputChunkSize $ \out -> do
  hccWriteBufferedLines handle out lines'
  hccObufWrite handle out

hccWithObuf :: Int -> (Word -> IO a) -> IO a
hccWithObuf initialCap action = do
  out <- hccObufNew initialCap
  case out == 0 of
    True -> hccPutErrLine "hcc: cannot allocate output buffer" >> hccExitFailure
    False -> do
      result <- action out
      hccObufFree out
      pure result

hccWithHandleLineWriter :: Int -> (([String] -> IO ()) -> IO a) -> IO a
hccWithHandleLineWriter handle action = hccWithObuf outputChunkSize $ \out -> do
  result <- action (hccWriteBufferedLines handle out)
  hccObufWrite handle out
  hccHandleFlush handle
  pure result

hccWriteBufferedLines :: Int -> Word -> [String] -> IO ()
hccWriteBufferedLines handle out rest = case rest of
  [] -> pure ()
  line:linesRest -> do
    hccWriteBufferedText out line
    hccObufPut out '\n'
    len <- hccObufLen out
    case len >= outputChunkSize of
      True -> hccObufWrite handle out >> hccObufClear out
      False -> pure ()
    hccWriteBufferedLines handle out linesRest

hccWriteBufferedText :: Word -> String -> IO ()
hccWriteBufferedText out text = case text of
  [] -> pure ()
  c1:c2:c3:c4:c5:c6:c7:c8:rest -> hccObufPut8 out c1 c2 c3 c4 c5 c6 c7 c8 >> hccWriteBufferedText out rest
  c1:c2:c3:c4:rest -> hccObufPut4 out c1 c2 c3 c4 >> hccWriteBufferedText out rest
  c:rest -> hccObufPut out c >> hccWriteBufferedText out rest

outputChunkSize :: Int
outputChunkSize = 65536
