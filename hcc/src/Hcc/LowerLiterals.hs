module LowerLiterals
  ( constBinOp
  , intConstOperand
  , lowerBinOp
  ) where

import Base
import Literal
import TypesIr

constBinOp :: String -> Int -> Int -> Int
constBinOp op a b = maybe 0 id (evalConstBinOp op a b)

intConstOperand :: String -> Operand
intConstOperand text = case parseIntBytes text of
  Just bytes -> OImmBytes bytes
  Nothing -> OImm (parseInt text)

parseIntBytes :: String -> Maybe [Int]
parseIntBytes text =
  let bytes = naturalLiteralBytes (stripIntSuffix text)
  in if exceedsSignedInt bytes then Just bytes else Nothing

naturalLiteralBytes :: String -> [Int]
naturalLiteralBytes text = case text of
  '0':'x':xs -> readBaseBytes 16 xs
  '0':'X':xs -> readBaseBytes 16 xs
  '0':xs -> readBaseBytes 8 xs
  _ -> readBaseBytes 10 text

readBaseBytes :: Int -> String -> [Int]
readBaseBytes base text = readBaseBytesFrom base zeroByteWord text

readBaseBytesFrom :: Int -> [Int] -> String -> [Int]
readBaseBytesFrom base bytes text = case text of
  [] -> bytes
  c:rest ->
    if digitValidForBase base c
    then readBaseBytesFrom base (byteWordMulAdd base (digitValue c) bytes) rest
    else bytes

digitValidForBase :: Int -> Char -> Bool
digitValidForBase base c = digitValue c < base

digitValue :: Char -> Int
digitValue c
  | c >= '0' && c <= '9' = fromEnum c - fromEnum '0'
  | c >= 'a' && c <= 'f' = 10 + fromEnum c - fromEnum 'a'
  | c >= 'A' && c <= 'F' = fromEnum c - fromEnum 'A' + 10
  | otherwise = 99

zeroByteWord :: [Int]
zeroByteWord = [0,0,0,0,0,0,0,0]

byteWordMulAdd :: Int -> Int -> [Int] -> [Int]
byteWordMulAdd base digit bytes = takeInts 8 (byteWordAddSmall digit (byteWordMulSmall base bytes))

byteWordMulSmall :: Int -> [Int] -> [Int]
byteWordMulSmall factor bytes = byteWordMulSmallCarry factor 0 bytes

byteWordMulSmallCarry :: Int -> Int -> [Int] -> [Int]
byteWordMulSmallCarry factor carry bytes = case bytes of
  [] -> []
  byte:rest ->
    let total = byte * factor + carry
    in (total `mod` 256) : byteWordMulSmallCarry factor (total `div` 256) rest

byteWordAddSmall :: Int -> [Int] -> [Int]
byteWordAddSmall addend bytes = byteWordAddSmallCarry addend bytes

byteWordAddSmallCarry :: Int -> [Int] -> [Int]
byteWordAddSmallCarry carry bytes = case bytes of
  [] -> []
  byte:rest ->
    let total = byte + carry
    in (total `mod` 256) : byteWordAddSmallCarry (total `div` 256) rest

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
  "&&" -> Just IAnd
  "||" -> Just IOr
  _ -> Nothing
