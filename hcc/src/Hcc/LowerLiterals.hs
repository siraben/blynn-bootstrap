module LowerLiterals
  ( intConstOperand
  , lowerBinOp
  ) where

import Base
import Literal
import TypesIr

intConstOperand :: String -> Either String Operand
intConstOperand text = fmap operand (integerLiteralBytes text) where
  operand bytes =
    if exceedsSignedInt bytes then OImmBytes bytes
    else OImm (foldr (\byte acc -> byte + 256 * acc) 0 bytes)

exceedsSignedInt :: [Int] -> Bool
exceedsSignedInt bytes = case bytes of
  _:_:_:b3:b4:b5:b6:b7:_ ->
    b4 /= 0 || b5 /= 0 || b6 /= 0 || b7 /= 0 || b3 >= 128
  _ -> False

lowerBinOp :: String -> Maybe BinOp
lowerBinOp op = case op of
  "+" -> Just IAdd
  "-" -> Just ISub
  "*" -> Just IMul
  "/" -> Just IDiv
  "%" -> Just IMod
  "<<" -> Just IShl
  ">>" -> Just IShr
  "==" -> Just IEq
  "!=" -> Just INe
  "&" -> Just IAnd
  "|" -> Just IOr
  "^" -> Just IXor
  _ -> Nothing
