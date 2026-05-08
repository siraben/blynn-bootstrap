module Main where

import Base
import System

main :: IO ()
main =
  putStrLn (status 5)

status :: Int -> String
status n
  | folded == 15 = "where: ok"
  | otherwise = "where: bad"
  where
    folded = sumTo n

sumTo :: Int -> Int
sumTo n = go n 0 where
  go current acc = case current of
    0 -> acc
    _ -> go (current - 1) (acc + current)
