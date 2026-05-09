module LowerCommon where

import Base

pairFirst :: (a, b) -> a
pairFirst (a, _) = a

pairSecond :: (a, b) -> b
pairSecond (_, b) = b

tripleFirst :: (a, b, c) -> a
tripleFirst (a, _, _) = a

tripleSecond :: (a, b, c) -> b
tripleSecond (_, b, _) = b

tripleThird :: (a, b, c) -> c
tripleThird (_, _, c) = c

listIsEmpty :: [a] -> Bool
listIsEmpty [] = True
listIsEmpty _ = False

stringMember :: String -> [String] -> Bool
stringMember _ [] = False
stringMember value (item:rest) =
  if value == item then True else stringMember value rest
