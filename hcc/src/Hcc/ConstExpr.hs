module ConstExpr
  ( parseConstExpr
  ) where

import Base
import Literal
import Operators
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
          TokPunct op | Just prec <- binop op, prec >= minPrec -> do
            advance
            rhs <- expression (prec + 1)
            value <- applyOp op lhs rhs
            climb value
          _ -> pure lhs
        Nothing -> pure lhs

binop :: String -> Maybe Int
binop op = case op of
  "||" -> Just 3
  "&&" -> Just 4
  "|" -> Just 5
  "^" -> Just 6
  "&" -> Just 7
  "==" -> Just 8
  "!=" -> Just 8
  "<" -> Just 9
  "<=" -> Just 9
  ">" -> Just 9
  ">=" -> Just 9
  "<<" -> Just 10
  ">>" -> Just 10
  "+" -> Just 11
  "-" -> Just 11
  "*" -> Just 12
  _ -> Nothing

applyOp :: String -> Int -> Int -> ConstParser Int
applyOp op a b = case op of
  "+" -> pure (a + b)
  "-" -> pure (a - b)
  "*" -> pure (a * b)
  "<<" -> pure (shiftLeftInt a (max 0 b))
  ">>" -> pure (shiftRightInt a (max 0 b))
  "<" -> pure (truth (a < b))
  "<=" -> pure (truth (a <= b))
  ">" -> pure (truth (a > b))
  ">=" -> pure (truth (a >= b))
  "==" -> pure (truth (a == b))
  "!=" -> pure (truth (a /= b))
  "&" -> pure (bitAndInt a b)
  "^" -> pure (bitXorInt a b)
  "|" -> pure (bitOrInt a b)
  "&&" -> pure (truth (a /= 0 && b /= 0))
  "||" -> pure (truth (a /= 0 || b /= 0))
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

constTokenKind :: Token -> TokenKind
constTokenKind (Token _ kind) = kind
