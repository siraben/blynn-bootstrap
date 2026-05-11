module LowerDataValues
  ( zeroData
  , bytesData
  ) where

import Base
import TypesIr

zeroData :: Int -> [DataValue]
zeroData n = if n <= 0 then [] else DByte 0 : zeroData (n - 1)

bytesData :: [Int] -> [DataValue]
bytesData [] = []
bytesData (byte:rest) = DByte byte : bytesData rest
