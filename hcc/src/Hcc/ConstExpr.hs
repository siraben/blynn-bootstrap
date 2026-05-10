module ConstExpr
  ( parseConstExpr
  ) where

import Base
import Literal
import ParseLite
import TypesToken

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
        TokInt value -> pure (parseInt value)
        TokChar value -> pure (charValue value)
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
