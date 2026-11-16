module Literal
  ( pow2
  , bitAndInt
  , bitOrInt
  , bitXorInt
  , intLiteralIsUnsigned
  , stripIntSuffix
  , floatLiteralBytes
  , floatLiteralSize
  , stripFloatSuffix
  , integerLiteralBytes
  , intBytes
  , charValue
  , stringBytes
  , isDecimalDigit
  , isOctalDigit
  , isHexDigit
  , decimalDigit
  , hexDigit
  , boolToInt
  , Constant(..)
  , constantLiteralChecked
  , constantLiteralRankedChecked
  , constantConvert
  , constantPromote
  , constantToIntChecked
  , constantInt
  , constantToInt
  , constantTrue
  , constantUnary
  , constantBinary
  , constantCommon
  ) where

import Base

boolToInt :: Bool -> Int
boolToInt = bool 0 1

pow2 :: Int -> Int
pow2 n = if n <= 0 then 1 else 2 * pow2 (n - 1)

bitAndInt :: Int -> Int -> Int
bitAndInt lhs rhs = bitFoldInt (&&) lhs rhs

bitOrInt :: Int -> Int -> Int
bitOrInt lhs rhs = bitFoldInt (||) lhs rhs

bitXorInt :: Int -> Int -> Int
bitXorInt lhs rhs = bitFoldInt (/=) lhs rhs

-- Terminate at the sign extension rather than at an arbitrary bit number.
-- This preserves every bit representable by the legacy Int API.
bitFoldInt :: (Bool -> Bool -> Bool) -> Int -> Int -> Int
bitFoldInt op lhs rhs =
  if (lhs == 0 || lhs == -1) && (rhs == 0 || rhs == -1)
  then if op (lhs == -1) (rhs == -1) then -1 else 0
  else 2 * bitFoldInt op (lhs `div` 2) (rhs `div` 2) + boolToInt (op (lhs `mod` 2 /= 0) (rhs `mod` 2 /= 0))

intLiteralIsUnsigned :: String -> Bool
intLiteralIsUnsigned text = case text of
  [] -> False
  c:rest -> c `elem` "uU" || intLiteralIsUnsigned rest

stripIntSuffix :: String -> String
stripIntSuffix text = reverse (dropWhile isIntSuffix (reverse text))

isIntSuffix :: Char -> Bool
isIntSuffix c = c `elem` "uUlL"

floatLiteralSize :: String -> Int
floatLiteralSize text
  | endsWithFloatSuffix "fF" text = 4
  | endsWithFloatSuffix "lL" text = 16
  | otherwise = 8

-- HCC holds a floating value as a signed integer. A literal with a nonzero
-- fraction, an exponent, or a hexadecimal form has no such value.
floatLiteralBytes :: Int -> String -> Either String [Int]
floatLiteralBytes size text =
  let clean = stripFloatSuffix text
      width = if size < 8 then size else 8
      range = if size < 8 then "32-bit" else "64-bit"
      outside = Left ("floating literal exceeds supported " ++ range ++ " range: " ++ text)
  in if not (integerFraction (dropWhile isDecimalDigit clean))
       then Left ("unsupported non-integer floating literal: " ++ text)
       else case readBaseBytesChecked 10 clean of
         Just bytes -> if fitsWidth width False bytes then Right (take size bytes) else outside
         Nothing -> outside

integerFraction :: String -> Bool
integerFraction fraction = case fraction of
  [] -> True
  '.':rest -> all (== '0') rest
  _ -> False

stripFloatSuffix :: String -> String
stripFloatSuffix text = reverse (dropWhile isFloatLiteralSuffix (reverse text))

isFloatLiteralSuffix :: Char -> Bool
isFloatLiteralSuffix c = c `elem` "fFlL"

endsWithFloatSuffix :: String -> String -> Bool
endsWithFloatSuffix suffixes text = case reverse text of
  c:_ -> c `elem` suffixes
  [] -> False

integerLiteralBytes :: String -> Either String [Int]
integerLiteralBytes text =
  let word = case stripIntSuffix text of
        '0':'x':xs -> readBaseBytesChecked 16 xs
        '0':'X':xs -> readBaseBytesChecked 16 xs
        '0':xs -> readBaseBytesChecked 8 xs
        clean -> readBaseBytesChecked 10 clean
  in case word of
    Just bytes -> Right bytes
    Nothing -> Left "integer literal exceeds supported 64-bit range"

-- Check in nine bytes before reading the eight-byte value, so overflow
-- cannot turn an invalid literal into a valid truncated value.
readBaseBytesChecked :: Int -> String -> Maybe [Int]
readBaseBytesChecked base text =
  if fits (replicate 9 0) text then Just (value (replicate 8 0) text) else Nothing
  where
  step bytes c = byteWordAddSmallCarry (digitValue c) (byteWordMulSmall base bytes)
  fits bytes remaining = case remaining of
    [] -> True
    c:rest -> if digitValue c >= base then True else
      let next = step bytes c
      in last next == 0 && fits next rest
  value bytes remaining = case remaining of
    [] -> bytes
    c:rest -> if digitValue c >= base then bytes else value (step bytes c) rest

digitValue :: Char -> Int
digitValue c
  | isDecimalDigit c = decimalDigit c
  | c >= 'a' && c <= 'f' = 10 + fromEnum c - fromEnum 'a'
  | c >= 'A' && c <= 'F' = 10 + fromEnum c - fromEnum 'A'
  | otherwise = 99

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
    signedByte (fst (decodeEscape (dropClosingQuote rest)))
  ['\'', c, '\''] -> signedByte (fromEnum c)
  _ -> 0

signedByte :: Int -> Int
signedByte value =
  let byte = value `mod` 256
  in if byte >= 128 then byte - 256 else byte

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

-- Byte-backed target integers. Neither the native host's Int width nor the
-- seed compiler's Int width is the target arithmetic contract. Width is in
-- bytes; ordinary integers use the selected ILP32/LP64 model, while
-- preprocessing treats all integer types as intmax_t/uintmax_t (64).
data Constant = Constant Int Bool [Int]

-- Rank (int=1, long=2, long long=3) matters even when two types have the
-- same width. Share candidate selection between byte folding and runtime
-- type inference rather than recovering a type from width or suffix alone.
constantLiteralRanked :: Int -> Bool -> String -> [Int] -> (Int, Constant)
constantLiteralRanked longSize preprocessing text bytes =
  let unsigned = intLiteralIsUnsigned text
      longs = length (filter (`elem` "lL") text)
      nonDecimal = case text of { '0':_:_ -> True; _ -> False }
      sizes = if preprocessing then [(3, 8)] else if longs >= 2 then [(3, 8)]
              else if longs == 1 then [(2, longSize), (3, 8)] else [(1, 4), (2, longSize), (3, 8)]
      candidates = concatMap (\(rank, size) -> if unsigned then [(rank, size, True)]
                               else if nonDecimal then [(rank, size, False), (rank, size, True)]
                               else [(rank, size, False)]) sizes
      choose remaining = case remaining of
        [] -> (3, Constant 8 True bytes)
        (rank, size, u):rest ->
          if fitsWidth size u bytes then (rank, Constant size u (take size bytes)) else choose rest
  in choose candidates

fitsWidth :: Int -> Bool -> [Int] -> Bool
fitsWidth size unsigned bytes =
  let limit = replicate (size - 1) 255 ++ [if unsigned then 255 else 127] ++ replicate (8 - size) 0
  in constWordCompare bytes limit <= 0

-- An invalid literal must not turn into a small (apparently valid) array
-- extent.
constantLiteralChecked :: Int -> Bool -> String -> Either String Constant
constantLiteralChecked longSize preprocessing text =
  fmap snd (constantLiteralRankedChecked longSize preprocessing text)

constantLiteralRankedChecked :: Int -> Bool -> String -> Either String (Int, Constant)
constantLiteralRankedChecked longSize preprocessing text =
  fmap (constantLiteralRanked longSize preprocessing text) (integerLiteralBytes text)

constantConvert :: Int -> Bool -> Constant -> Constant
constantConvert = constConvert

constantPromote :: Constant -> Constant
constantPromote value@(Constant size _ _) =
  if size < 4 then constConvert 4 False value else value

-- Enum values and layout counts have an Int-facing representation. Keep this
-- boundary portable to the seed route; never silently truncate a wide value.
constantToIntChecked :: Constant -> Maybe Int
constantToIntChecked value =
  let Constant _ _ bytes = constConvert 8 False value
      narrowed = constConvert 4 False value
      Constant _ _ restored = constConvert 8 False narrowed
  in if bytes == restored && constNegative value == constNegative narrowed
     then Just (constantToInt narrowed) else Nothing

constantInt :: Int -> Int -> Constant
constantInt size value = Constant size False (intBytes size value)

constantToInt :: Constant -> Int
constantToInt (Constant _ unsigned bytes) =
  let negative = not unsigned && constWordNegative bytes
      magnitude = if negative then constWordNegate bytes else bytes
      value = foldr (\byte acc -> byte + 256 * acc) 0 magnitude
  in if negative then negate value else value

constantTrue :: Constant -> Bool
constantTrue (Constant _ _ bytes) = any (/= 0) bytes

constWordNegative :: [Int] -> Bool
constWordNegative bytes = case reverse bytes of
  byte:_ -> byte >= 128
  [] -> False

constNegative :: Constant -> Bool
constNegative (Constant _ unsigned bytes) = not unsigned && constWordNegative bytes

constantCommon :: Constant -> Constant -> (Constant, Constant)
constantCommon a@(Constant sa ua _) b@(Constant sb ub _) =
  let size = max sa sb
      unsigned = if sa == sb then ua || ub else if sa > sb then ua else ub
  in (constConvert size unsigned a, constConvert size unsigned b)

constConvert :: Int -> Bool -> Constant -> Constant
constConvert size unsigned value@(Constant _ _ bytes) =
  Constant size unsigned (take size (bytes ++ repeat (if constNegative value then 255 else 0)))

constantUnary :: String -> Constant -> Constant
constantUnary op value@(Constant size unsigned bytes) = case op of
  "-" -> Constant size unsigned (constWordNegate bytes)
  "~" -> Constant size unsigned (map (255 -) bytes)
  "!" -> constantInt size (boolToInt (not (constantTrue value)))
  _ -> value

constantBinary :: String -> Constant -> Constant -> Either String Constant
constantBinary op left right =
  let (a@(Constant size unsigned ab), b@(Constant _ _ bb)) = constantCommon left right
      result bytes = Right (Constant size unsigned bytes)
      boolean truth = Right (constantInt (min 4 size) (boolToInt truth))
      cmp = if constNegative a /= constNegative b
            then if constNegative a then -1 else 1
            else constWordCompare ab bb
      divide remainder =
        if not (constantTrue b) then Left "division by zero in constant expression"
        else let am = if constNegative a then constWordNegate ab else ab
                 bm = if constNegative b then constWordNegate bb else bb
                 (q, r) = constWordDivide am bm
                 negative = if remainder then constNegative a else constNegative a /= constNegative b
                 bytes = if remainder then r else q
             in result (if negative then constWordNegate bytes else bytes)
  in case op of
    "+" -> result (constWordAdd ab bb)
    "-" -> result (constWordAdd ab (constWordNegate bb))
    "*" -> result (constWordMultiply ab bb)
    "/" -> divide False
    "%" -> divide True
    "&" -> result (zipWith bitAndInt ab bb)
    "|" -> result (zipWith bitOrInt ab bb)
    "^" -> result (zipWith bitXorInt ab bb)
    "<<" -> constShift False left right
    ">>" -> constShift True left right
    "==" -> boolean (cmp == 0)
    "!=" -> boolean (cmp /= 0)
    "<" -> boolean (cmp < 0)
    "<=" -> boolean (cmp <= 0)
    ">" -> boolean (cmp > 0)
    ">=" -> boolean (cmp >= 0)
    "&&" -> boolean (constantTrue a && constantTrue b)
    "||" -> boolean (constantTrue a || constantTrue b)
    _ -> Left ("unhandled operator in constant expression: " ++ op)

constShift :: Bool -> Constant -> Constant -> Either String Constant
constShift right value@(Constant size unsigned bytes) count@(Constant _ _ cb) =
  if constNegative count || constWordCompare cb (intBytes (length cb) (size * 8)) >= 0
  then Left "invalid shift count in constant expression"
  else Right (Constant size unsigned (shift (constantToInt count) bytes))
  where
    shift n word =
      if n == 0 then word
      else shift (n - 1) (if right then constWordRight (if constNegative value then 128 else 0) word else byteWordMulSmall 2 word)

constWordCompare :: [Int] -> [Int] -> Int
constWordCompare a b =
  if reverse a < reverse b then -1 else if a == b then 0 else 1

constWordAdd :: [Int] -> [Int] -> [Int]
constWordAdd = add 0 where
  add carry as bs = case (as, bs) of
    (a:ar, b:br) -> let n = a + b + carry in n `mod` 256 : add (n `div` 256) ar br
    _ -> []

constWordNegate :: [Int] -> [Int]
constWordNegate bytes = byteWordAddSmallCarry 1 (map (255 -) bytes)

constWordMultiply :: [Int] -> [Int] -> [Int]
constWordMultiply a b = go a b (map (const 0) a) where
  go shifted rest acc = case rest of
    [] -> acc
    byte:more -> go (take (length a) (0:shifted)) more (constWordAdd acc (byteWordMulSmall byte shifted))

constWordRight :: Int -> [Int] -> [Int]
constWordRight fill bytes = reverse (go fill (reverse bytes)) where
  go carry rest = case rest of
    [] -> []
    byte:more -> (byte `div` 2 + carry) : go ((byte `mod` 2) * 128) more

constWordDivide :: [Int] -> [Int] -> ([Int], [Int])
constWordDivide a b = go (reverse (concatMap bits a)) zero (zero ++ [0]) where
  zero = map (const 0) a
  divisor = b ++ [0]
  bits byte = take 8 (byteBits byte)
  byteBits n = n `mod` 2 : byteBits (n `div` 2)
  go rest quotient remainder = case rest of
    [] -> (quotient, take (length a) remainder)
    bit:more ->
      let trial = byteWordAddSmallCarry bit (byteWordMulSmall 2 remainder)
          fits = constWordCompare trial divisor >= 0
          remainder' = if fits then constWordAdd trial (constWordNegate divisor) else trial
          quotient' = byteWordAddSmallCarry (boolToInt fits) (byteWordMulSmall 2 quotient)
      in go more quotient' remainder'
