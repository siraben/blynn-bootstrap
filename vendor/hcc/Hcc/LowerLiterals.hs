module LowerLiterals where

import Base
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
bitAnd a b = bitFoldInt bitAndBool a b 1 0

bitOr :: Int -> Int -> Int
bitOr a b = bitFoldInt bitOrBool a b 1 0

bitXor :: Int -> Int -> Int
bitXor a b = bitFoldInt bitXorBool a b 1 0

bitFoldInt :: (Bool -> Bool -> Bool) -> Int -> Int -> Int -> Int -> Int
bitFoldInt op a b bit out =
  if bit > 1073741824
    then out
    else
      let out' = if op (bitSet a bit) (bitSet b bit) then out + bit else out
      in if bit == 1073741824 then out' else bitFoldInt op a b (bit * 2) out'

bitSet :: Int -> Int -> Bool
bitSet value bit =
  if value >= 0
    then ((value `div` bit) `mod` 2) == 1
    else not (bitSet (0 - value - 1) bit)

bitAndBool :: Bool -> Bool -> Bool
bitAndBool x y = x && y

bitOrBool :: Bool -> Bool -> Bool
bitOrBool x y = x || y

bitXorBool :: Bool -> Bool -> Bool
bitXorBool x y = x /= y

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

intConstInstr :: Temp -> String -> Instr
intConstInstr temp text = case parseIntBytes text of
  Just bytes -> IConstBytes temp bytes
  Nothing -> IConst temp (parseInt text)

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
digitValue c =
  if c >= '0' && c <= '9'
    then fromEnum c - fromEnum '0'
    else if c >= 'a' && c <= 'f'
      then 10 + fromEnum c - fromEnum 'a'
      else if c >= 'A' && c <= 'F'
        then 10 + fromEnum c - fromEnum 'A'
        else 99

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
