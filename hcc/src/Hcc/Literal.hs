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
  , floatLiteralBytes
  , floatLiteralSize
  , stripFloatSuffix
  , naturalLiteralBytes
  , intBytes
  , charValue
  , stringBytes
  , isDecimalDigit
  , isOctalDigit
  , isHexDigit
  , decimalDigit
  , hexDigit
  , boolToInt
  , evalConstBinOp
  ) where

import Base

boolToInt :: Bool -> Int
boolToInt = bool 0 1

evalConstBinOp :: String -> Int -> Int -> Maybe Int
evalConstBinOp op a b = case op of
  "+" -> Just (a + b)
  "-" -> Just (a - b)
  "*" -> Just (a * b)
  "/" -> if b == 0 then Nothing else Just (a `div` b)
  "%" -> if b == 0 then Nothing else Just (a `mod` b)
  "<<" -> Just (shiftLeftInt a (max 0 b))
  ">>" -> Just (shiftRightInt a (max 0 b))
  "&" -> Just (bitAndInt a b)
  "^" -> Just (bitXorInt a b)
  "|" -> Just (bitOrInt a b)
  "==" -> Just (boolToInt (a == b))
  "!=" -> Just (boolToInt (a /= b))
  "<" -> Just (boolToInt (a < b))
  "<=" -> Just (boolToInt (a <= b))
  ">" -> Just (boolToInt (a > b))
  ">=" -> Just (boolToInt (a >= b))
  "&&" -> Just (boolToInt (a /= 0 && b /= 0))
  "||" -> Just (boolToInt (a /= 0 || b /= 0))
  _ -> Nothing

pow2 :: Int -> Int
pow2 n = if n <= 0 then 1 else 2 * pow2 (n - 1)

bitNotInt :: Int -> Int
bitNotInt value = negate value - 1

bitAndInt :: Int -> Int -> Int
bitAndInt lhs rhs = bitFoldInt (&&) lhs rhs 1 0

bitOrInt :: Int -> Int -> Int
bitOrInt lhs rhs = bitFoldInt (||) lhs rhs 1 0

bitXorInt :: Int -> Int -> Int
bitXorInt lhs rhs = bitFoldInt (/=) lhs rhs 1 0

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
  c:rest -> c `elem` "uU" || intLiteralIsUnsigned rest

parseInt :: String -> Int
parseInt text =
  let clean = stripIntSuffix text
  in case clean of
    '0':'x':xs -> readHexFrom 0 xs
    '0':'X':xs -> readHexFrom 0 xs
    '0':xs -> readOctalFrom 0 xs
    _ -> readDecimalPrefixFrom 0 clean

stripIntSuffix :: String -> String
stripIntSuffix text = reverse (dropWhile isIntSuffix (reverse text))

isIntSuffix :: Char -> Bool
isIntSuffix c = c `elem` "uUlL"

floatLiteralSize :: String -> Int
floatLiteralSize text
  | endsWithFloatSuffix "fF" text = 4
  | endsWithFloatSuffix "lL" text = 16
  | otherwise = 8

floatLiteralBytes :: Int -> String -> [Int]
floatLiteralBytes size text =
  take size (floatLiteralByteWord text)

floatLiteralByteWord :: String -> [Int]
floatLiteralByteWord text = case stripFloatSuffix text of
  '0':'x':rest -> readBaseBytes 16 rest
  '0':'X':rest -> readBaseBytes 16 rest
  rest -> readBaseBytes 10 rest

stripFloatSuffix :: String -> String
stripFloatSuffix text = reverse (dropWhile isFloatLiteralSuffix (reverse text))

isFloatLiteralSuffix :: Char -> Bool
isFloatLiteralSuffix c = c `elem` "fFlL"

endsWithFloatSuffix :: String -> String -> Bool
endsWithFloatSuffix suffixes text = case reverse text of
  c:_ -> c `elem` suffixes
  [] -> False

readDecimalPrefixFrom :: Int -> String -> Int
readDecimalPrefixFrom acc xs = case xs of
  c:rest ->
    if isDecimalDigit c
      then readDecimalPrefixFrom (acc * 10 + decimalDigit c) rest
      else acc
  [] -> acc

readOctalFrom :: Int -> String -> Int
readOctalFrom n xs = case xs of
  [] -> n
  c:rest ->
    if isOctalDigit c
      then readOctalFrom (n * 8 + decimalDigit c) rest
      else n

readHexFrom :: Int -> String -> Int
readHexFrom n xs = case xs of
  [] -> n
  c:rest -> readHexFrom (n * 16 + hexDigit c) rest

naturalLiteralBytes :: String -> [Int]
naturalLiteralBytes text = case text of
  '0':'x':xs -> readBaseBytes 16 xs
  '0':'X':xs -> readBaseBytes 16 xs
  '0':xs -> readBaseBytes 8 xs
  _ -> readBaseBytes 10 text

readBaseBytes :: Int -> String -> [Int]
readBaseBytes base = readBaseBytesFrom base zeroByteWord

readBaseBytesFrom :: Int -> [Int] -> String -> [Int]
readBaseBytesFrom base bytes text = case text of
  [] -> bytes
  c:rest ->
    if digitValue c < base
      then readBaseBytesFrom base (byteWordMulAdd base (digitValue c) bytes) rest
      else bytes

digitValue :: Char -> Int
digitValue c
  | isDecimalDigit c = decimalDigit c
  | c >= 'a' && c <= 'f' = 10 + fromEnum c - fromEnum 'a'
  | c >= 'A' && c <= 'F' = 10 + fromEnum c - fromEnum 'A'
  | otherwise = 99

zeroByteWord :: [Int]
zeroByteWord = [0,0,0,0,0,0,0,0]

byteWordMulAdd :: Int -> Int -> [Int] -> [Int]
byteWordMulAdd base digit bytes = take 8 (byteWordAddSmallCarry digit (byteWordMulSmall base bytes))

byteWordMulSmall :: Int -> [Int] -> [Int]
byteWordMulSmall factor = byteWordMulSmallCarry factor 0

byteWordMulSmallCarry :: Int -> Int -> [Int] -> [Int]
byteWordMulSmallCarry factor carry bytes = case bytes of
  [] -> []
  byte:rest ->
    let total = byte * factor + carry
    in (total `mod` 256) : byteWordMulSmallCarry factor (total `div` 256) rest

byteWordAddSmallCarry :: Int -> [Int] -> [Int]
byteWordAddSmallCarry carry bytes = case bytes of
  [] -> []
  byte:rest ->
    let total = byte + carry
    in (total `mod` 256) : byteWordAddSmallCarry (total `div` 256) rest

intBytes :: Int -> Int -> [Int]
intBytes size value = take size (intBytesFrom value)

intBytesFrom :: Int -> [Int]
intBytesFrom n = (n `mod` 256) : intBytesFrom (n `div` 256)

charValue :: String -> Int
charValue text = case text of
  '\'':'\\':rest ->
    fst (decodeEscape (dropClosingQuote rest))
  ['\'', c, '\''] -> fromEnum c
  _ -> 0

stringBytes :: String -> [Int]
stringBytes text = stringBytesFrom (stripTrailingQuote (stripLeadingQuote text))

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
isDecimalDigit c = fromEnum c >= fromEnum '0' && fromEnum c <= fromEnum '9'

isOctalDigit :: Char -> Bool
isOctalDigit c = fromEnum c >= fromEnum '0' && fromEnum c <= fromEnum '7'

isHexDigit :: Char -> Bool
isHexDigit c = isDecimalDigit c || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')

decimalDigit :: Char -> Int
decimalDigit c = fromEnum c - fromEnum '0'

hexDigit :: Char -> Int
hexDigit c
  | isDecimalDigit c = decimalDigit c
  | c >= 'a' && c <= 'f' = 10 + fromEnum c - fromEnum 'a'
  | c >= 'A' && c <= 'F' = 10 + fromEnum c - fromEnum 'A'
  | otherwise = 0

stripLeadingQuote :: String -> String
stripLeadingQuote text = case text of
  c:rest -> if fromEnum c == 34 then rest else text
  [] -> []

stripTrailingQuote :: String -> String
stripTrailingQuote text = reverse (stripLeadingQuote (reverse text))
