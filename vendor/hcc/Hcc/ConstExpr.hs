module ConstExpr where

import Base
import ParseLite
import Token

type ConstParser a = P [(String, Int)] Token String a

parseConstExpr :: [(String, Int)] -> [Token] -> Either String (Int, [Token])
parseConstExpr env toks = parseRest parseCond env toks

parseCond :: ConstParser Int
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

parseOr :: ConstParser Int
parseOr = do
  lhs <- parseLogicalAnd
  parseOrTail lhs

parseOrTail :: Int -> ConstParser Int
parseOrTail lhs = do
  found <- constEatPunct "||"
  if found
    then do
      rhs <- parseLogicalAnd
      parseOrTail (truth (lhs /= 0 || rhs /= 0))
    else pure lhs

parseLogicalAnd :: ConstParser Int
parseLogicalAnd = do
  lhs <- parseBitOr
  parseLogicalAndTail lhs

parseLogicalAndTail :: Int -> ConstParser Int
parseLogicalAndTail lhs = do
  found <- constEatPunct "&&"
  if found
    then do
      rhs <- parseBitOr
      parseLogicalAndTail (truth (lhs /= 0 && rhs /= 0))
    else pure lhs

parseBitOr :: ConstParser Int
parseBitOr = do
  lhs <- parseBitXor
  parseBitOrTail lhs

parseBitOrTail :: Int -> ConstParser Int
parseBitOrTail lhs = do
  found <- constEatPunct "|"
  if found
    then do
      rhs <- parseBitXor
      parseBitOrTail (bitOrInt lhs rhs)
    else pure lhs

parseBitXor :: ConstParser Int
parseBitXor = do
  lhs <- parseBitAnd
  parseBitXorTail lhs

parseBitXorTail :: Int -> ConstParser Int
parseBitXorTail lhs = do
  found <- constEatPunct "^"
  if found
    then do
      rhs <- parseBitAnd
      parseBitXorTail (bitXorInt lhs rhs)
    else pure lhs

parseBitAnd :: ConstParser Int
parseBitAnd = do
  lhs <- parseEq
  parseBitAndTail lhs

parseBitAndTail :: Int -> ConstParser Int
parseBitAndTail lhs = do
  found <- constEatPunct "&"
  if found
    then do
      rhs <- parseEq
      parseBitAndTail (bitAndInt lhs rhs)
    else pure lhs

parseEq :: ConstParser Int
parseEq = do
  lhs <- parseRel
  eq <- constEatPunct "=="
  if eq
    then compareTail (==) lhs
    else do
      ne <- constEatPunct "!="
      if ne then compareTail (/=) lhs else pure lhs

parseRel :: ConstParser Int
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

compareTail :: (Int -> Int -> Bool) -> Int -> ConstParser Int
compareTail op lhs = do
  rhs <- parseShift
  pure (truth (lhs `op` rhs))

parseShift :: ConstParser Int
parseShift = do
  lhs <- parseAdd
  parseShiftTail lhs

parseShiftTail :: Int -> ConstParser Int
parseShiftTail lhs = do
  left <- constEatPunct "<<"
  if left
    then do
      rhs <- parseAdd
      parseShiftTail (shiftLeftInt lhs (max 0 rhs))
    else do
      right <- constEatPunct ">>"
      if right
        then do
          rhs <- parseAdd
          parseShiftTail (shiftRightInt lhs (max 0 rhs))
        else pure lhs

parseAdd :: ConstParser Int
parseAdd = do
  lhs <- parseMul
  parseAddTail lhs

parseAddTail :: Int -> ConstParser Int
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

parseMul :: ConstParser Int
parseMul = do
  lhs <- parseUnary
  parseMulTail lhs

parseMulTail :: Int -> ConstParser Int
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

parseUnary :: ConstParser Int
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
                  pure (bitNotInt value)
                else parsePrimary

parsePrimary :: ConstParser Int
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

parseDefinedOperator :: ConstParser Int
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

truth :: Bool -> Int
truth value = if value then 1 else 0

constTokenKind :: Token -> TokenKind
constTokenKind (Token _ kind) = kind

parseIntLiteral :: String -> Int
parseIntLiteral value = case readNumber (map toLowerAscii (stripIntSuffix value)) of
  Just n -> n
  Nothing -> 0

stripIntSuffix :: String -> String
stripIntSuffix text = reverse (dropWhile (`elem` "uUlL") (reverse text))

readNumber :: String -> Maybe Int
readNumber text = case text of
  '0':'x':digits -> readRadix 16 hexDigitValue digits
  '0':digits | any isOctDigit digits -> readRadix 8 octDigitValue digits
  _ -> readRadix 10 decDigitValue text

readRadix :: Int -> (Char -> Maybe Int) -> String -> Maybe Int
readRadix radix valueOf text = go 0 text where
  go acc rest = case rest of
    [] -> Just acc
    c:cs -> case valueOf c of
      Just value -> go (acc * radix + value) cs
      Nothing -> Nothing

charInt :: String -> Int
charInt text = case text of
  '\'':'\\':c:_ -> escapeChar c
  '\'':c:_ -> charCode c
  _ -> 0

escapeChar :: Char -> Int
escapeChar c = case c of
  'n' -> 10
  'r' -> 13
  't' -> 9
  '0' -> 0
  '\\' -> 92
  '\'' -> 39
  '"' -> 34
  _ -> charCode c

toLowerAscii :: Char -> Char
toLowerAscii c =
  if c >= 'A' && c <= 'Z'
  then toEnum (fromEnum c + 32)
  else c

isOctDigit :: Char -> Bool
isOctDigit c = c >= '0' && c <= '7'

decDigitValue :: Char -> Maybe Int
decDigitValue c =
  if c >= '0' && c <= '9'
  then Just (charCode c - charCode '0')
  else Nothing

octDigitValue :: Char -> Maybe Int
octDigitValue c =
  if c >= '0' && c <= '7'
  then Just (charCode c - charCode '0')
  else Nothing

hexDigitValue :: Char -> Maybe Int
hexDigitValue c
  | c >= '0' && c <= '9' = Just (charCode c - charCode '0')
  | c >= 'a' && c <= 'f' = Just (10 + charCode c - charCode 'a')
  | otherwise = Nothing

charCode :: Char -> Int
charCode = fromEnum

bitNotInt :: Int -> Int
bitNotInt value = 0 - value - 1

bitAndInt :: Int -> Int -> Int
bitAndInt lhs rhs = bitFoldInt bitAndBits lhs rhs 1 0

bitOrInt :: Int -> Int -> Int
bitOrInt lhs rhs = bitFoldInt bitOrBits lhs rhs 1 0

bitXorInt :: Int -> Int -> Int
bitXorInt lhs rhs = bitFoldInt bitXorBits lhs rhs 1 0

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

bitAndBits :: Bool -> Bool -> Bool
bitAndBits lhs rhs = lhs && rhs

bitOrBits :: Bool -> Bool -> Bool
bitOrBits lhs rhs = lhs || rhs

bitXorBits :: Bool -> Bool -> Bool
bitXorBits lhs rhs = lhs /= rhs

shiftLeftInt :: Int -> Int -> Int
shiftLeftInt value amount = value * powerOfTwo amount

shiftRightInt :: Int -> Int -> Int
shiftRightInt value amount = value `div` powerOfTwo amount

powerOfTwo :: Int -> Int
powerOfTwo amount =
  if amount <= 0
  then 1
  else 2 * powerOfTwo (amount - 1)
