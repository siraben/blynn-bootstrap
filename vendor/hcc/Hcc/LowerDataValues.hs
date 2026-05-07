module LowerDataValues where

import Base
import Ir

padData :: Int -> [DataValue] -> [DataValue]
padData size values =
  let used = dataSize values
  in if used >= size then takeData size values else values ++ zeroData (size - used)

takeData :: Int -> [DataValue] -> [DataValue]
takeData size values =
  if size <= 0 then [] else case values of
    [] -> []
    DByte byte:rest -> DByte byte : takeData (size - 1) rest
    DAddress label:rest ->
      if size >= 8 then DAddress label : takeData (size - 8) rest else zeroData size

dataSize :: [DataValue] -> Int
dataSize values = case values of
  [] -> 0
  DByte _:rest -> 1 + dataSize rest
  DAddress _:rest -> 8 + dataSize rest

zeroData :: Int -> [DataValue]
zeroData n = if n <= 0 then [] else DByte 0 : zeroData (n - 1)

bytesData :: [Int] -> [DataValue]
bytesData bytes = case bytes of
  [] -> []
  byte:rest -> DByte byte : bytesData rest
