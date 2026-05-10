module Literal
  ( pow2
  , bitNotInt
  , bitAndInt
  , bitOrInt
  , bitXorInt
  , shiftLeftInt
  , shiftRightInt
  , intLiteralIsUnsigned
  , parseInt
  , stripIntSuffix
  , intBytes
  , takeInts
  , charValue
  , stringBytes
  , isDecimalDigit
  , isOctalDigit
  , isHexDigit
  , decimalDigit
  , hexDigit
  ) where

import Base

pow2 :: Int -> Int
pow2 n = if n <= 0 then 1 else 2 * pow2 (n - 1)

bitNotInt :: Int -> Int
bitNotInt value = 0 - value - 1

bitAndInt :: Int -> Int -> Int
bitAndInt lhs rhs = bitFoldInt bitAndBool lhs rhs 1 0

bitOrInt :: Int -> Int -> Int
bitOrInt lhs rhs = bitFoldInt bitOrBool lhs rhs 1 0

bitXorInt :: Int -> Int -> Int
bitXorInt lhs rhs = bitFoldInt bitXorBool lhs rhs 1 0

bitAndBool :: Bool -> Bool -> Bool
bitAndBool lhs rhs = lhs && rhs

bitOrBool :: Bool -> Bool -> Bool
bitOrBool lhs rhs = lhs || rhs

bitXorBool :: Bool -> Bool -> Bool
bitXorBool lhs rhs = lhs /= rhs

bitFoldInt :: (Bool -> Bool -> Bool) -> Int -> Int -> Int -> Int -> Int
bitFoldInt op lhs rhs bit acc =
  if bit > 1073741824
  then acc
  else
    let acc' = if op (bitSet lhs bit) (bitSet rhs bit) then acc + bit else acc
    in if bit == 1073741824 then acc' else bitFoldInt op lhs rhs (bit * 2) acc'

bitSet :: Int -> Int -> Bool
bitSet value bit =
  if value >= 0
  then ((value `div` bit) `mod` 2) == 1
  else not (bitSet (bitNotInt value) bit)

shiftLeftInt :: Int -> Int -> Int
shiftLeftInt value amount = value * pow2 amount

shiftRightInt :: Int -> Int -> Int
shiftRightInt value amount = value `div` pow2 amount

intLiteralIsUnsigned :: String -> Bool
intLiteralIsUnsigned text = case text of
  [] -> False
  c:rest -> c == 'u' || c == 'U' || intLiteralIsUnsigned rest

parseInt :: String -> Int
parseInt text =
  let clean = stripIntSuffix text
  in case clean of
    '0':'x':xs -> readHex xs
    '0':'X':xs -> readHex xs
    '0':xs -> readOctal xs
    _ -> readDecimalPrefix clean

stripIntSuffix :: String -> String
stripIntSuffix text = reverse (dropWhile isIntSuffix (reverse text))

isIntSuffix :: Char -> Bool
isIntSuffix c =
  c == 'u' || c == 'U' || c == 'l' || c == 'L'

readDecimalPrefix :: String -> Int
readDecimalPrefix text = readDecimalPrefixFrom 0 text

readDecimalPrefixFrom :: Int -> String -> Int
readDecimalPrefixFrom acc xs = case xs of
  c:rest ->
    if isDecimalDigit c
      then readDecimalPrefixFrom (acc * 10 + decimalDigit c) rest
      else acc
  [] -> acc

readOctal :: String -> Int
readOctal text = readOctalFrom 0 text

readOctalFrom :: Int -> String -> Int
readOctalFrom n xs = case xs of
  [] -> n
  c:rest ->
    if isOctalDigit c
      then readOctalFrom (n * 8 + decimalDigit c) rest
      else n

readHex :: String -> Int
readHex text = readHexFrom 0 text

readHexFrom :: Int -> String -> Int
readHexFrom n xs = case xs of
  [] -> n
  c:rest -> readHexFrom (n * 16 + hexDigit c) rest

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

charValue :: String -> Int
charValue text = case text of
  '\'':'\\':rest ->
    fst (decodeEscape (dropClosingQuote rest))
  ['\'', c, '\''] -> fromEnum c
  _ -> 0

stringBytes :: String -> [Int]
stringBytes text = stringBytesFrom (stripQuotes text)

stringBytesFrom :: String -> [Int]
stringBytesFrom chars = case chars of
  [] -> [0]
  '\\':rest ->
    let decoded = decodeEscape rest
        value = fst decoded
        tailChars = snd decoded
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
          then readOctalEscape (count + 1) (value * 8 + decimalDigit c) rest
          else (value, text)
      [] -> (value, text)

readHexEscape :: String -> (Int, String)
readHexEscape text =
  case readHexEscapeFrom 0 text of
    (value, rest, consumed) ->
      if consumed then (value, rest) else (fromEnum 'x', text)

readHexEscapeFrom :: Int -> String -> (Int, String, Bool)
readHexEscapeFrom value chars = case chars of
  c:rest ->
    if isHexDigit c
      then
        case readHexEscapeFrom (value * 16 + hexDigit c) rest of
          (v, r, _) -> (v, r, True)
      else (value, chars, False)
  [] -> (value, chars, False)

isDecimalDigit :: Char -> Bool
isDecimalDigit c = c >= '0' && c <= '9'

isOctalDigit :: Char -> Bool
isOctalDigit c = c >= '0' && c <= '7'

isHexDigit :: Char -> Bool
isHexDigit c =
  isDecimalDigit c || isLowerHexDigit c || isUpperHexDigit c

isLowerHexDigit :: Char -> Bool
isLowerHexDigit c = c >= 'a' && c <= 'f'

isUpperHexDigit :: Char -> Bool
isUpperHexDigit c = c >= 'A' && c <= 'F'

decimalDigit :: Char -> Int
decimalDigit c = fromEnum c - fromEnum '0'

hexDigit :: Char -> Int
hexDigit c
  | c >= '0' && c <= '9' = decimalDigit c
  | c >= 'a' && c <= 'f' = 10 + fromEnum c - fromEnum 'a'
  | c >= 'A' && c <= 'F' = 10 + fromEnum c - fromEnum 'A'
  | otherwise = 0

stripQuotes :: String -> String
stripQuotes text = stripTrailingQuote (stripLeadingQuote text)

stripLeadingQuote :: String -> String
stripLeadingQuote text = case text of
  c:rest -> if fromEnum c == 34 then rest else text
  [] -> []

stripTrailingQuote :: String -> String
stripTrailingQuote text = reverse (stripLeadingQuote (reverse text))
