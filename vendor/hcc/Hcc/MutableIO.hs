module MutableIO where

import Base

data MutVar a = MutVar (IORef a)

newMutVar :: a -> IO (MutVar a)
newMutVar value = do
  ref <- newIORef value
  pure (MutVar ref)

readMutVar :: MutVar a -> IO a
readMutVar var = case var of
  MutVar ref -> readIORef ref

writeMutVar :: MutVar a -> a -> IO ()
writeMutVar var value = case var of
  MutVar ref -> writeIORef ref value

modifyMutVar :: MutVar a -> (a -> a) -> IO a
modifyMutVar var f = do
  old <- readMutVar var
  let new = f old
  writeMutVar var new
  pure new

data IntArray = IntArray Int

foreign import ccall "hcc_iarray_new" hccIArrayNew :: Int -> Int -> IO Int
foreign import ccall "hcc_iarray_read" hccIArrayRead :: Int -> Int -> IO Int
foreign import ccall "hcc_iarray_write" hccIArrayWrite :: Int -> Int -> Int -> IO ()

newIntArray :: Int -> Int -> IO IntArray
newIntArray size initial = do
  ident <- hccIArrayNew size initial
  pure (IntArray ident)

readIntArray :: IntArray -> Int -> IO Int
readIntArray array index = case array of
  IntArray ident -> hccIArrayRead ident index

writeIntArray :: IntArray -> Int -> Int -> IO ()
writeIntArray array index value = case array of
  IntArray ident -> hccIArrayWrite ident index value

modifyIntArray :: IntArray -> Int -> (Int -> Int) -> IO Int
modifyIntArray array index f = do
  old <- readIntArray array index
  let new = f old
  writeIntArray array index new
  pure new

foldIntArray :: (a -> Int -> a) -> a -> IntArray -> Int -> IO a
foldIntArray f initial array size = go 0 initial where
  go index acc =
    if index >= size
      then pure acc
      else do
        value <- readIntArray array index
        go (index + 1) (f acc value)

sumIntArray :: IntArray -> Int -> IO Int
sumIntArray = foldIntArray (+) 0
