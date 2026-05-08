module ConstExpr where

import Base
import ParseLite
import Token

type ConstParser a = P [(String, Integer)] Token String a

parseConstExpr :: [(String, Integer)] -> [Token] -> Either String (Integer, [Token])
parseConstExpr env toks = parseRest parseCond env toks

parseCond :: ConstParser Integer
parseCond = do
  cond <- parseOr
  question <- constEatPunct "?"
  if question
    then do
      yes <- parseCond
      constNeedPunct ":" "expected ':' in constant expression"
      no <- parseCond
      pure (if cond /= 0 then yes else no)
    else pure cond

parseOr :: ConstParser Integer
parseOr = do
  lhs <- parseLogicalAnd
  parseOrTail lhs

parseOrTail :: Integer -> ConstParser Integer
parseOrTail lhs = do
  found <- constEatPunct "||"
  if found
    then do
      rhs <- parseLogicalAnd
      parseOrTail (truth (lhs /= 0 || rhs /= 0))
    else pure lhs

parseLogicalAnd :: ConstParser Integer
parseLogicalAnd = do
  lhs <- parseBitOr
  parseLogicalAndTail lhs

parseLogicalAndTail :: Integer -> ConstParser Integer
parseLogicalAndTail lhs = do
  found <- constEatPunct "&&"
  if found
    then do
      rhs <- parseBitOr
      parseLogicalAndTail (truth (lhs /= 0 && rhs /= 0))
    else pure lhs

parseBitOr :: ConstParser Integer
parseBitOr = do
  lhs <- parseBitXor
  parseBitOrTail lhs

parseBitOrTail :: Integer -> ConstParser Integer
parseBitOrTail lhs = do
  found <- constEatPunct "|"
  if found
    then do
      rhs <- parseBitXor
      parseBitOrTail (bitOrInteger lhs rhs)
    else pure lhs

parseBitXor :: ConstParser Integer
parseBitXor = do
  lhs <- parseBitAnd
  parseBitXorTail lhs

parseBitXorTail :: Integer -> ConstParser Integer
parseBitXorTail lhs = do
  found <- constEatPunct "^"
  if found
    then do
      rhs <- parseBitAnd
      parseBitXorTail (bitXorInteger lhs rhs)
    else pure lhs

parseBitAnd :: ConstParser Integer
parseBitAnd = do
  lhs <- parseEq
  parseBitAndTail lhs

parseBitAndTail :: Integer -> ConstParser Integer
parseBitAndTail lhs = do
  found <- constEatPunct "&"
  if found
    then do
      rhs <- parseEq
      parseBitAndTail (bitAndInteger lhs rhs)
    else pure lhs

parseEq :: ConstParser Integer
parseEq = do
  lhs <- parseRel
  eq <- constEatPunct "=="
  if eq
    then compareTail (==) lhs
    else do
      ne <- constEatPunct "!="
      if ne then compareTail (/=) lhs else pure lhs

parseRel :: ConstParser Integer
parseRel = do
  lhs <- parseShift
  lt <- constEatPunct "<"
  if lt
    then compareTail (<) lhs
    else do
      le <- constEatPunct "<="
      if le
        then compareTail (<=) lhs
        else do
          gt <- constEatPunct ">"
          if gt
            then compareTail (>) lhs
            else do
              ge <- constEatPunct ">="
              if ge then compareTail (>=) lhs else pure lhs

compareTail :: (Integer -> Integer -> Bool) -> Integer -> ConstParser Integer
compareTail op lhs = do
  rhs <- parseShift
  pure (truth (lhs `op` rhs))

parseShift :: ConstParser Integer
parseShift = do
  lhs <- parseAdd
  parseShiftTail lhs

parseShiftTail :: Integer -> ConstParser Integer
parseShiftTail lhs = do
  left <- constEatPunct "<<"
  if left
    then do
      rhs <- parseAdd
      parseShiftTail (shiftLeftInteger lhs (max 0 rhs))
    else do
      right <- constEatPunct ">>"
      if right
        then do
          rhs <- parseAdd
          parseShiftTail (shiftRightInteger lhs (max 0 rhs))
        else pure lhs

parseAdd :: ConstParser Integer
parseAdd = do
  lhs <- parseMul
  parseAddTail lhs

parseAddTail :: Integer -> ConstParser Integer
parseAddTail lhs = do
  plus <- constEatPunct "+"
  if plus
    then do
      rhs <- parseMul
      parseAddTail (lhs + rhs)
    else do
      minus <- constEatPunct "-"
      if minus
        then do
          rhs <- parseMul
          parseAddTail (lhs - rhs)
        else pure lhs

parseMul :: ConstParser Integer
parseMul = do
  lhs <- parseUnary
  parseMulTail lhs

parseMulTail :: Integer -> ConstParser Integer
parseMulTail lhs = do
  star <- constEatPunct "*"
  if star
    then do
      rhs <- parseUnary
      parseMulTail (lhs * rhs)
    else do
      slash <- constEatPunct "/"
      if slash
        then do
          rhs <- parseUnary
          if rhs == 0
            then pFail "division by zero in constant expression"
            else parseMulTail (lhs `div` rhs)
        else do
          percent <- constEatPunct "%"
          if percent
            then do
              rhs <- parseUnary
              if rhs == 0
                then pFail "modulo by zero in constant expression"
                else parseMulTail (lhs `mod` rhs)
            else pure lhs

parseUnary :: ConstParser Integer
parseUnary = do
  bang <- constEatPunct "!"
  if bang
    then do
      value <- parseUnary
      pure (truth (value == 0))
    else do
      plus <- constEatPunct "+"
      if plus
        then parseUnary
        else do
          minus <- constEatPunct "-"
          if minus
            then do
              value <- parseUnary
              pure (-value)
            else do
              tilde <- constEatPunct "~"
              if tilde
                then do
                  value <- parseUnary
                  pure (bitNotInteger value)
                else parsePrimary

parsePrimary :: ConstParser Integer
parsePrimary = do
  paren <- constEatPunct "("
  if paren
    then do
      value <- parseCond
      constNeedPunct ")" "expected ')' in constant expression"
      pure value
    else do
      tok <- pTake "empty constant expression"
      case constTokenKind tok of
        TokIdent "defined" -> parseDefinedOperator
        TokIdent name -> do
          env <- pEnv
          pure (maybe 0 id (lookup name env))
        TokInt value -> pure (parseIntLiteral value)
        TokChar value -> pure (charInt value)
        _ -> pFail "unsupported token in constant expression"

parseDefinedOperator :: ConstParser Integer
parseDefinedOperator = do
  paren <- constEatPunct "("
  if paren
    then do
      name <- constNeedIdent "bad defined operator in #if expression"
      constNeedPunct ")" "bad defined operator in #if expression"
      pure (truth (name /= ""))
    else do
      name <- constNeedIdent "bad defined operator in #if expression"
      pure (truth (name /= ""))

constEatPunct :: String -> ConstParser Bool
constEatPunct expected = pRaw $ \_env toks -> case toks of
  Token _ (TokPunct punct):rest | punct == expected -> Consumed (Ok True rest)
  _ -> Unconsumed (Ok False toks)

constNeedPunct :: String -> String -> ConstParser ()
constNeedPunct expected err = do
  found <- constEatPunct expected
  if found then pure () else pFail err

constNeedIdent :: String -> ConstParser String
constNeedIdent err = do
  tok <- pTake err
  case constTokenKind tok of
    TokIdent name -> pure name
    _ -> pFail err

truth :: Bool -> Integer
truth value = if value then 1 else 0

constTokenKind :: Token -> TokenKind
constTokenKind (Token _ kind) = kind

parseIntLiteral :: String -> Integer
parseIntLiteral value = case readNumber (map toLowerAscii (stripIntSuffix value)) of
  Just n -> n
  Nothing -> 0

stripIntSuffix :: String -> String
stripIntSuffix text = reverse (dropWhile (`elem` "uUlL") (reverse text))

readNumber :: String -> Maybe Integer
readNumber text = case text of
  '0':'x':digits -> readRadix 16 hexDigitValue digits
  '0':digits | any isOctDigit digits -> readRadix 8 octDigitValue digits
  _ -> readRadix 10 decDigitValue text

readRadix :: Integer -> (Char -> Maybe Integer) -> String -> Maybe Integer
readRadix radix valueOf text = go 0 text where
  go acc rest = case rest of
    [] -> Just acc
    c:cs -> case valueOf c of
      Just value -> go (acc * radix + value) cs
      Nothing -> Nothing

charInt :: String -> Integer
charInt text = case text of
  '\'':'\\':c:_ -> escapeChar c
  '\'':c:_ -> fromIntegral (charCode c)
  _ -> 0

escapeChar :: Char -> Integer
escapeChar c = case c of
  'n' -> 10
  'r' -> 13
  't' -> 9
  '0' -> 0
  '\\' -> 92
  '\'' -> 39
  '"' -> 34
  _ -> fromIntegral (charCode c)

toLowerAscii :: Char -> Char
toLowerAscii c =
  if c >= 'A' && c <= 'Z'
  then toEnum (fromEnum c + 32)
  else c

isOctDigit :: Char -> Bool
isOctDigit c = c >= '0' && c <= '7'

decDigitValue :: Char -> Maybe Integer
decDigitValue c =
  if c >= '0' && c <= '9'
  then Just (fromIntegral (charCode c - charCode '0'))
  else Nothing

octDigitValue :: Char -> Maybe Integer
octDigitValue c =
  if c >= '0' && c <= '7'
  then Just (fromIntegral (charCode c - charCode '0'))
  else Nothing

hexDigitValue :: Char -> Maybe Integer
hexDigitValue c
  | c >= '0' && c <= '9' = Just (fromIntegral (charCode c - charCode '0'))
  | c >= 'a' && c <= 'f' = Just (fromIntegral (10 + charCode c - charCode 'a'))
  | otherwise = Nothing

charCode :: Char -> Int
charCode = fromEnum

bitNotInteger :: Integer -> Integer
bitNotInteger value = 0 - value - 1

bitAndInteger :: Integer -> Integer -> Integer
bitAndInteger lhs rhs
  | lhs < 0 && rhs < 0 = bitNotInteger (bitOrInteger (bitNotInteger lhs) (bitNotInteger rhs))
  | lhs < 0 = bitAndNegative lhs rhs
  | rhs < 0 = bitAndNegative rhs lhs
  | otherwise = bitAndNonNegative lhs rhs

bitAndNegative :: Integer -> Integer -> Integer
bitAndNegative negative nonnegative =
  nonnegative - bitAndNonNegative nonnegative (bitNotInteger negative)

bitAndNonNegative :: Integer -> Integer -> Integer
bitAndNonNegative lhs rhs = go lhs rhs 1 0 where
  go x y bit acc =
    if x == 0 || y == 0
    then acc
    else
      let acc' = if x `mod` 2 == 1 && y `mod` 2 == 1 then acc + bit else acc
      in go (x `div` 2) (y `div` 2) (bit * 2) acc'

bitOrInteger :: Integer -> Integer -> Integer
bitOrInteger lhs rhs =
  bitNotInteger (bitAndInteger (bitNotInteger lhs) (bitNotInteger rhs))

bitXorInteger :: Integer -> Integer -> Integer
bitXorInteger lhs rhs =
  bitOrInteger (bitAndInteger lhs (bitNotInteger rhs)) (bitAndInteger (bitNotInteger lhs) rhs)

shiftLeftInteger :: Integer -> Integer -> Integer
shiftLeftInteger value amount = value * powerOfTwo amount

shiftRightInteger :: Integer -> Integer -> Integer
shiftRightInteger value amount = value `div` powerOfTwo amount

powerOfTwo :: Integer -> Integer
powerOfTwo amount =
  if amount <= 0
  then 1
  else 2 * powerOfTwo (amount - 1)
