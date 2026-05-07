module Hcc.ConstExpr
  ( parseConstExpr
  , parseIntLiteral
  ) where

import Data.Bits ((.&.), (.|.), complement, shiftL, shiftR, xor)
import Data.Char (isOctDigit, ord, toLower)
import Numeric (readDec, readHex, readOct)

import Hcc.Token

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
parseIntLiteral value = case readNumber (map toLower (stripIntSuffix value)) of
  Just n -> n
  Nothing -> 0

stripIntSuffix :: String -> String
stripIntSuffix text = reverse (dropWhile (`elem` "uUlL") (reverse text))

readNumber :: String -> Maybe Integer
readNumber text = case text of
  '0':'x':digits -> readWhole readHex digits
  '0':digits | any isOctDigit digits -> readWhole readOct digits
  _ -> readWhole readDec text

readWhole :: (String -> [(Integer, String)]) -> String -> Maybe Integer
readWhole reader text = case reader text of
  [(value, "")] -> Just value
  _ -> Nothing

charInt :: String -> Integer
charInt text = case text of
  '\'':'\\':c:_ -> escapeChar c
  '\'':c:_ -> fromIntegral (ord c)
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
  _ -> fromIntegral (ord c)
