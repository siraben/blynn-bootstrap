module Lower.Common where

pairFirst :: (a, b) -> a
pairFirst pair = case pair of
  (a, _) -> a

pairSecond :: (a, b) -> b
pairSecond pair = case pair of
  (_, b) -> b

tripleFirst :: (a, b, c) -> a
tripleFirst triple = case triple of
  (a, _, _) -> a

tripleSecond :: (a, b, c) -> b
tripleSecond triple = case triple of
  (_, b, _) -> b

tripleThird :: (a, b, c) -> c
tripleThird triple = case triple of
  (_, _, c) -> c

listIsEmpty :: [a] -> Bool
listIsEmpty values = case values of
  [] -> True
  _ -> False

stringMember :: String -> [String] -> Bool
stringMember value values = case values of
  [] -> False
  item:rest -> if value == item then True else stringMember value rest
