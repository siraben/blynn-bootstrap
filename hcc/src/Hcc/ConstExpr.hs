module ConstExpr
  ( parseConstExpr
  ) where

import Base
import Literal
import ParseLite
import TypesToken

type ConstParser a = P [(String, Int)] Token String a

parseConstExpr :: [(String, Int)] -> [Token] -> Either String (Int, [Token])
parseConstExpr env toks = parseRest (expression 0) env toks

expression :: Int -> ConstParser Int
expression minPrec = do
  lhs <- parseUnary
  climb lhs
  where
    climb lhs = do
      mtok <- pPeekMaybe
      case mtok of
        Just tok -> case constTokenKind tok of
          TokPunct "?" | minPrec <= 2 -> do
            advance
            yes <- expression 0
            constNeedPunct ":" "expected ':' in constant expression"
            no <- expression 2
            climb (if lhs /= 0 then yes else no)
          TokPunct op | Just (prec, assoc) <- binop op, prec >= minPrec -> do
            advance
            rhs <- expression (if rightAssoc assoc then prec else prec + 1)
            value <- applyOp op lhs rhs
            climb value
          _ -> pure lhs
        Nothing -> pure lhs

data Assoc = LeftAssoc | RightAssoc

rightAssoc :: Assoc -> Bool
rightAssoc assoc = case assoc of
  RightAssoc -> True
  LeftAssoc -> False

binop :: String -> Maybe (Int, Assoc)
binop op = case op of
  "||" -> Just (3, LeftAssoc)
  "&&" -> Just (4, LeftAssoc)
  "|" -> Just (5, LeftAssoc)
  "^" -> Just (6, LeftAssoc)
  "&" -> Just (7, LeftAssoc)
  "==" -> Just (8, LeftAssoc)
  "!=" -> Just (8, LeftAssoc)
  "<" -> Just (9, LeftAssoc)
  "<=" -> Just (9, LeftAssoc)
  ">" -> Just (9, LeftAssoc)
  ">=" -> Just (9, LeftAssoc)
  "<<" -> Just (10, LeftAssoc)
  ">>" -> Just (10, LeftAssoc)
  "+" -> Just (11, LeftAssoc)
  "-" -> Just (11, LeftAssoc)
  "*" -> Just (12, LeftAssoc)
  "/" -> Just (12, LeftAssoc)
  "%" -> Just (12, LeftAssoc)
  _ -> Nothing

applyOp :: String -> Int -> Int -> ConstParser Int
applyOp op lhs rhs = case op of
  "+" -> pure (lhs + rhs)
  "-" -> pure (lhs - rhs)
  "*" -> pure (lhs * rhs)
  "/" -> if rhs == 0
    then pFail "division by zero in constant expression"
    else pure (lhs `div` rhs)
  "%" -> if rhs == 0
    then pFail "modulo by zero in constant expression"
    else pure (lhs `mod` rhs)
  "<<" -> pure (shiftLeftInt lhs (max 0 rhs))
  ">>" -> pure (shiftRightInt lhs (max 0 rhs))
  "<" -> pure (truth (lhs < rhs))
  "<=" -> pure (truth (lhs <= rhs))
  ">" -> pure (truth (lhs > rhs))
  ">=" -> pure (truth (lhs >= rhs))
  "==" -> pure (truth (lhs == rhs))
  "!=" -> pure (truth (lhs /= rhs))
  "&" -> pure (bitAndInt lhs rhs)
  "^" -> pure (bitXorInt lhs rhs)
  "|" -> pure (bitOrInt lhs rhs)
  "&&" -> pure (truth (lhs /= 0 && rhs /= 0))
  "||" -> pure (truth (lhs /= 0 || rhs /= 0))
  _ -> pFail ("unhandled operator in constant expression: " ++ op)

parseUnary :: ConstParser Int
parseUnary = do
  mtok <- pPeekMaybe
  case mtok of
    Just tok -> case constTokenKind tok of
      TokPunct "!" -> advance >> ((truth . (== 0)) <$> parseUnary)
      TokPunct "+" -> advance >> parseUnary
      TokPunct "-" -> advance >> (negate <$> parseUnary)
      TokPunct "~" -> advance >> (bitNotInt <$> parseUnary)
      _ -> parsePrimary
    Nothing -> pFail "empty constant expression"

parsePrimary :: ConstParser Int
parsePrimary = do
  paren <- constEatPunct "("
  if paren
    then do
      value <- expression 0
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

advance :: ConstParser ()
advance = pSkip "unexpected end of constant expression"

constEatPunct :: String -> ConstParser Bool
constEatPunct expected = pRaw $ \env toks -> case toks of
  Token _ (TokPunct punct):rest | punct == expected -> Consumed (Ok True env rest)
  _ -> Unconsumed (Ok False env toks)

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
