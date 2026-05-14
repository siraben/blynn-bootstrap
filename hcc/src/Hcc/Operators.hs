module Operators
  ( Assoc(..)
  , rightAssoc
  , binopArith
  ) where

import Base

data Assoc = LeftAssoc | RightAssoc

rightAssoc :: Assoc -> Bool
rightAssoc assoc = case assoc of
  RightAssoc -> True
  LeftAssoc -> False

binopArith :: String -> Maybe (Int, Assoc)
binopArith op = case op of
  "||" -> Just (3, LeftAssoc)
  "&&" -> Just (4, LeftAssoc)
  "|"  -> Just (5, LeftAssoc)
  "^"  -> Just (6, LeftAssoc)
  "&"  -> Just (7, LeftAssoc)
  "==" -> Just (8, LeftAssoc)
  "!=" -> Just (8, LeftAssoc)
  "<"  -> Just (9, LeftAssoc)
  "<=" -> Just (9, LeftAssoc)
  ">"  -> Just (9, LeftAssoc)
  ">=" -> Just (9, LeftAssoc)
  "<<" -> Just (10, LeftAssoc)
  ">>" -> Just (10, LeftAssoc)
  "+"  -> Just (11, LeftAssoc)
  "-"  -> Just (11, LeftAssoc)
  "*"  -> Just (12, LeftAssoc)
  "/"  -> Just (12, LeftAssoc)
  "%"  -> Just (12, LeftAssoc)
  _    -> Nothing
