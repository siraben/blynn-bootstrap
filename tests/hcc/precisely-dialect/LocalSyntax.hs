module Main where

import Base
import System

data Box a = Box a

main :: IO ()
main =
  putStrLn (case transform (Box 7) of
    Box n -> if n == 21 then "local-syntax: ok" else "local-syntax: bad")

transform :: Box Int -> Box Int
transform box =
  let scale = \n -> n * 3
  in case box of
    Box value -> Box (scale value)
