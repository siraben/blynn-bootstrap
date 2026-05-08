module Main where

import Base
import MutableIO
import System

main :: IO ()
main = do
  counter <- newMutVar 10
  n <- modifyMutVar counter (+ 5)
  pairRef <- newMutVar (3, 4)
  writeMutVar pairRef (n, 7)
  pair <- readMutVar pairRef
  array <- newIntArray 4 1
  writeIntArray array 2 n
  modified <- modifyIntArray array 2 (* 2)
  total <- sumIntArray array 4
  let pairTotal = case pair of
        (x, y) -> x + y
  if n == 15 && modified == 30 && total == 33 && pairTotal == 22
    then putStrLn "mutable-io: ok"
    else putStrLn "mutable-io: fail"
