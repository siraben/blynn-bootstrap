module LowerLiterals where

import Ir
import LowerCommon

constBinOp :: String -> Int -> Int -> Int
constBinOp op a b = case op of
  "+" -> a + b
  "-" -> a - b
  "*" -> a * b
  "/" -> if b == 0 then 0 else a `div` b
  "%" -> if b == 0 then 0 else a `mod` b
  "<<" -> a * pow2 b
  ">>" -> a `div` pow2 b
  "|" -> bitOr a b
  "&" -> bitAnd a b
  "^" -> bitXor a b
  "==" -> truthInt (a == b)
  "!=" -> truthInt (a /= b)
  "<" -> truthInt (a < b)
  "<=" -> truthInt (a <= b)
  ">" -> truthInt (a > b)
  ">=" -> truthInt (a >= b)
  "&&" -> truthInt (a /= 0 && b /= 0)
  "||" -> truthInt (a /= 0 || b /= 0)
  _ -> 0

truthInt :: Bool -> Int
truthInt value = if value then 1 else 0

pow2 :: Int -> Int
pow2 n = if n <= 0 then 1 else 2 * pow2 (n - 1)

bitAnd :: Int -> Int -> Int
bitAnd a b = bitFoldAnd 1 a b 0

bitOr :: Int -> Int -> Int
bitOr a b = bitFoldOr 1 a b 0

bitXor :: Int -> Int -> Int
bitXor a b = bitFoldXor 1 a b 0

bitFoldAnd :: Int -> Int -> Int -> Int -> Int
bitFoldAnd bit a b out =
  if bit > 1073741824
    then out
    else
      let abit = a `mod` (bit * 2) `div` bit
          bbit = b `mod` (bit * 2) `div` bit
          out' = if bitAndBits abit bbit then out + bit else out
      in bitFoldAnd (bit * 2) a b out'

bitFoldOr :: Int -> Int -> Int -> Int -> Int
bitFoldOr bit a b out =
  if bit > 1073741824
    then out
    else
      let abit = a `mod` (bit * 2) `div` bit
          bbit = b `mod` (bit * 2) `div` bit
          out' = if bitOrBits abit bbit then out + bit else out
      in bitFoldOr (bit * 2) a b out'

bitFoldXor :: Int -> Int -> Int -> Int -> Int
bitFoldXor bit a b out =
  if bit > 1073741824
    then out
    else
      let abit = a `mod` (bit * 2) `div` bit
          bbit = b `mod` (bit * 2) `div` bit
          out' = if bitXorBits abit bbit then out + bit else out
      in bitFoldXor (bit * 2) a b out'

bitAndBits :: Int -> Int -> Bool
bitAndBits x y = x /= 0 && y /= 0

bitOrBits :: Int -> Int -> Bool
bitOrBits x y = x /= 0 || y /= 0

bitXorBits :: Int -> Int -> Bool
bitXorBits x y = (x /= 0) /= (y /= 0)

intBytes :: Int -> Int -> [Int]
intBytes size value = takeInts size (intBytesFrom value)

intBytesFrom :: Int -> [Int]
intBytesFrom n = (n `mod` 256) : intBytesFrom (n `div` 256)

takeInts :: Int -> [Int] -> [Int]
takeInts count values =
  if count <= 0
    then []
    else case values of
      [] -> []
      value:rest -> value : takeInts (count - 1) rest

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

intLiteralIsUnsigned :: String -> Bool
intLiteralIsUnsigned text = case text of
  [] -> False
  c:rest -> if c == 'u' || c == 'U' then True else intLiteralIsUnsigned rest

parseInt :: String -> Int
parseInt text =
  let clean = stripIntSuffix text
  in case clean of
    '0':'x':xs -> readHex xs
    '0':'X':xs -> readHex xs
    '0':xs -> readOctal xs
    _ -> readDecimalPrefix clean

readDecimalPrefix :: String -> Int
readDecimalPrefix text = readDecimalPrefixFrom 0 text

readDecimalPrefixFrom :: Int -> String -> Int
readDecimalPrefixFrom acc xs = case xs of
  c:rest ->
    if isDecimalDigit c
      then readDecimalPrefixFrom (acc * 10 + decimalDigit c) rest
      else acc
  [] -> acc

isDecimalDigit :: Char -> Bool
isDecimalDigit c = c >= '0' && c <= '9'

decimalDigit :: Char -> Int
decimalDigit c = fromEnum c - fromEnum '0'

readOctal :: String -> Int
readOctal text = readOctalFrom 0 text

readOctalFrom :: Int -> String -> Int
readOctalFrom n xs = case xs of
  [] -> n
  c:rest ->
    if isOctalDigit c
      then readOctalFrom (n * 8 + fromEnum c - fromEnum '0') rest
      else n

stripIntSuffix :: String -> String
stripIntSuffix text = reverse (dropIntSuffix (reverse text))

dropIntSuffix :: String -> String
dropIntSuffix text = case text of
  [] -> []
  c:rest -> if isIntSuffix c then dropIntSuffix rest else text

isIntSuffix :: Char -> Bool
isIntSuffix c =
  c == 'u' || c == 'U' || c == 'l' || c == 'L'

readHex :: String -> Int
readHex text = readHexFrom 0 text

readHexFrom :: Int -> String -> Int
readHexFrom n xs = case xs of
  [] -> n
  c:rest -> readHexFrom (n * 16 + hexDigit c) rest

hexDigit :: Char -> Int
hexDigit c =
  if c >= '0' && c <= '9'
    then fromEnum c - fromEnum '0'
    else if c >= 'a' && c <= 'f'
      then 10 + fromEnum c - fromEnum 'a'
      else if c >= 'A' && c <= 'F'
        then 10 + fromEnum c - fromEnum 'A'
        else 0

charValue :: String -> Int
charValue text = case text of
  '\'':'\\':rest ->
    pairFirst (decodeEscape (dropClosingQuote rest))
  '\'':c:'\'':[] -> fromEnum c
  _ -> 0

stringBytes :: String -> [Int]
stringBytes text = stringBytesFrom (stripQuotes text)

stringBytesFrom :: String -> [Int]
stringBytesFrom chars = case chars of
  [] -> [0]
  '\\':rest ->
    let decoded = decodeEscape rest
        value = pairFirst decoded
        tailChars = pairSecond decoded
    in value : stringBytesFrom tailChars
  c:rest -> fromEnum c : stringBytesFrom rest

dropClosingQuote :: String -> String
dropClosingQuote text = case reverse text of
  '\'':rest -> reverse rest
  _ -> text

decodeEscape :: String -> (Int, String)
decodeEscape text = case text of
  'n':rest -> (10, rest)
  't':rest -> (9, rest)
  'r':rest -> (13, rest)
  'f':rest -> (12, rest)
  'v':rest -> (11, rest)
  'a':rest -> (7, rest)
  'b':rest -> (8, rest)
  '\\':rest -> (92, rest)
  '\'':rest -> (39, rest)
  '"':rest -> (34, rest)
  'x':rest -> readHexEscape rest
  c:rest ->
    if isOctalDigit c
      then readOctalEscape 0 0 (c:rest)
      else (fromEnum c, rest)
  [] -> (0, [])

readOctalEscape :: Int -> Int -> String -> (Int, String)
readOctalEscape count value text =
  if count >= 3
    then (value, text)
    else case text of
      c:rest ->
        if isOctalDigit c
          then readOctalEscape (count + 1) (value * 8 + fromEnum c - fromEnum '0') rest
          else (value, text)
      [] -> (value, text)

readHexEscape :: String -> (Int, String)
readHexEscape text =
  let result = readHexEscapeFrom 0 text
      value = tripleFirst result
      rest = tripleSecond result
      consumed = tripleThird result
  in if consumed then (value, rest) else (fromEnum 'x', text)

readHexEscapeFrom :: Int -> String -> (Int, String, Bool)
readHexEscapeFrom value chars = case chars of
  c:rest ->
    if isHexDigit c
      then
        let result = readHexEscapeFrom (value * 16 + hexDigit c) rest
            v = tripleFirst result
            r = tripleSecond result
        in (v, r, True)
      else (value, chars, False)
  [] -> (value, chars, False)

isOctalDigit :: Char -> Bool
isOctalDigit c = c >= '0' && c <= '7'

isHexDigit :: Char -> Bool
isHexDigit c =
  isDecimalDigit c || isLowerHexDigit c || isUpperHexDigit c

isLowerHexDigit :: Char -> Bool
isLowerHexDigit c = c >= 'a' && c <= 'f'

isUpperHexDigit :: Char -> Bool
isUpperHexDigit c = c >= 'A' && c <= 'F'

stripQuotes :: String -> String
stripQuotes text = stripTrailingQuote (stripLeadingQuote text)

stripLeadingQuote :: String -> String
stripLeadingQuote text = case text of
  c:rest -> if fromEnum c == 34 then rest else text
  [] -> []

stripTrailingQuote :: String -> String
stripTrailingQuote text = reverse (stripLeadingQuote (reverse text))
