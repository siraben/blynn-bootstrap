module Operators
  ( Assoc(..)
  , binopArith
  ) where

import Base

data Assoc = LeftAssoc | RightAssoc

binopArith :: String -> Maybe (Int, Assoc)
binopArith op = case op of
  [c] -> case c of
    '|' -> left 5
    '^' -> left 6
    '&' -> left 7
    '<' -> left 9
    '>' -> left 9
    '+' -> left 11
    '-' -> left 11
    '*' -> left 12
    '/' -> left 12
    '%' -> left 12
    _ -> Nothing
  [_, _] -> case op of
    "||" -> left 3
    "&&" -> left 4
    "==" -> left 8
    "!=" -> left 8
    "<=" -> left 9
    ">=" -> left 9
    "<<" -> left 10
    ">>" -> left 10
    _ -> Nothing
  _ -> Nothing
  where
    left prec = Just (prec, LeftAssoc)
