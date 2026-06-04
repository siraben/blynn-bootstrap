module LowerDataValues
  ( zeroData
  ) where

import Base
import TypesIr

zeroData :: Int -> [DataValue]
zeroData n = if n <= 0 then [] else DByte 0 : zeroData (n - 1)
