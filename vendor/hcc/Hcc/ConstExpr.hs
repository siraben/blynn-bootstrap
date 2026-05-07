module ConstExpr
  ( parseConstExpr
  , parseIntLiteral
  ) where

import Data.Bits ((.&.), (.|.), complement, shiftL, shiftR, xor)

import Token

parseConstExpr :: [(String, Integer)] -> [Token] -> Either String (Integer, [Token])
parseConstExpr env = parseCond
  where
    parseCond toks = do
      (cond, rest) <- parseOr toks
      case rest of
        Token _ (TokPunct "?"):xs -> do
          (yes, xs') <- parseConstExpr env xs
          case xs' of
            Token _ (TokPunct ":"):ys -> do
              (no, ys') <- parseCond ys
              Right (if cond /= 0 then yes else no, ys')
            _ -> Left "expected ':' in constant expression"
        _ -> Right (cond, rest)

    parseOr toks = do
      (lhs, rest) <- parseLogicalAnd toks
      parseTail lhs rest
      where
        parseTail lhs rest = case rest of
          Token _ (TokPunct "||"):xs -> do
            (rhs, xs') <- parseLogicalAnd xs
            parseTail (truth (lhs /= 0 || rhs /= 0)) xs'
          _ -> Right (lhs, rest)

    parseLogicalAnd toks = do
      (lhs, rest) <- parseBitOr toks
      parseTail lhs rest
      where
        parseTail lhs rest = case rest of
          Token _ (TokPunct "&&"):xs -> do
            (rhs, xs') <- parseBitOr xs
            parseTail (truth (lhs /= 0 && rhs /= 0)) xs'
          _ -> Right (lhs, rest)

    parseBitOr toks = do
      (lhs, rest) <- parseBitXor toks
      parseTail lhs rest
      where
        parseTail lhs rest = case rest of
          Token _ (TokPunct "|"):xs -> do
            (rhs, xs') <- parseBitXor xs
            parseTail (lhs .|. rhs) xs'
          _ -> Right (lhs, rest)

    parseBitXor toks = do
      (lhs, rest) <- parseBitAnd toks
      parseTail lhs rest
      where
        parseTail lhs rest = case rest of
          Token _ (TokPunct "^"):xs -> do
            (rhs, xs') <- parseBitAnd xs
            parseTail (lhs `xor` rhs) xs'
          _ -> Right (lhs, rest)

    parseBitAnd toks = do
      (lhs, rest) <- parseEq toks
      parseTail lhs rest
      where
        parseTail lhs rest = case rest of
          Token _ (TokPunct "&"):xs -> do
            (rhs, xs') <- parseEq xs
            parseTail (lhs .&. rhs) xs'
          _ -> Right (lhs, rest)

    parseEq toks = do
      (lhs, rest) <- parseRel toks
      case rest of
        Token _ (TokPunct "=="):xs -> compareTail (==) lhs xs
        Token _ (TokPunct "!="):xs -> compareTail (/=) lhs xs
        _ -> Right (lhs, rest)

    parseRel toks = do
      (lhs, rest) <- parseShift toks
      case rest of
        Token _ (TokPunct "<"):xs -> compareTail (<) lhs xs
        Token _ (TokPunct "<="):xs -> compareTail (<=) lhs xs
        Token _ (TokPunct ">"):xs -> compareTail (>) lhs xs
        Token _ (TokPunct ">="):xs -> compareTail (>=) lhs xs
        _ -> Right (lhs, rest)

    compareTail op lhs toks = do
      (rhs, rest) <- parseShift toks
      Right (truth (lhs `op` rhs), rest)

    parseShift toks = do
      (lhs, rest) <- parseAdd toks
      parseTail lhs rest
      where
        parseTail lhs rest = case rest of
          Token _ (TokPunct "<<"):xs -> do
            (rhs, xs') <- parseAdd xs
            parseTail (lhs `shiftL` fromInteger (max 0 rhs)) xs'
          Token _ (TokPunct ">>"):xs -> do
            (rhs, xs') <- parseAdd xs
            parseTail (lhs `shiftR` fromInteger (max 0 rhs)) xs'
          _ -> Right (lhs, rest)

    parseAdd toks = do
      (lhs, rest) <- parseMul toks
      parseTail lhs rest
      where
        parseTail lhs rest = case rest of
          Token _ (TokPunct "+"):xs -> do
            (rhs, xs') <- parseMul xs
            parseTail (lhs + rhs) xs'
          Token _ (TokPunct "-"):xs -> do
            (rhs, xs') <- parseMul xs
            parseTail (lhs - rhs) xs'
          _ -> Right (lhs, rest)

    parseMul toks = do
      (lhs, rest) <- parseUnary toks
      parseTail lhs rest
      where
        parseTail lhs rest = case rest of
          Token _ (TokPunct "*"):xs -> do
            (rhs, xs') <- parseUnary xs
            parseTail (lhs * rhs) xs'
          Token _ (TokPunct "/"):xs -> do
            (rhs, xs') <- parseUnary xs
            if rhs == 0 then Left "division by zero in constant expression" else parseTail (lhs `div` rhs) xs'
          Token _ (TokPunct "%"):xs -> do
            (rhs, xs') <- parseUnary xs
            if rhs == 0 then Left "modulo by zero in constant expression" else parseTail (lhs `mod` rhs) xs'
          _ -> Right (lhs, rest)

    parseUnary toks = case toks of
      Token _ (TokPunct "!"):rest -> do
        (value, rest') <- parseUnary rest
        Right (truth (value == 0), rest')
      Token _ (TokPunct "+"):rest -> parseUnary rest
      Token _ (TokPunct "-"):rest -> do
        (value, rest') <- parseUnary rest
        Right (-value, rest')
      Token _ (TokPunct "~"):rest -> do
        (value, rest') <- parseUnary rest
        Right (complement value, rest')
      _ -> parsePrimary toks

    parsePrimary toks = case toks of
      Token _ (TokPunct "("):rest -> do
        (value, rest') <- parseConstExpr env rest
        case rest' of
          Token _ (TokPunct ")"):xs -> Right (value, xs)
          _ -> Left "expected ')' in constant expression"
      Token _ (TokIdent "defined"):Token _ (TokPunct "("):Token _ (TokIdent name):Token _ (TokPunct ")"):rest ->
        Right (truth (name /= ""), rest)
      Token _ (TokIdent "defined"):Token _ (TokIdent name):rest ->
        Right (truth (name /= ""), rest)
      Token _ (TokIdent name):rest ->
        Right (maybe 0 id (lookup name env), rest)
      Token _ (TokInt value):rest ->
        Right (parseIntLiteral value, rest)
      Token _ (TokChar value):rest ->
        Right (charInt value, rest)
      [] -> Left "empty constant expression"
      _ -> Left "unsupported token in constant expression"

truth :: Bool -> Integer
truth value = if value then 1 else 0

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
