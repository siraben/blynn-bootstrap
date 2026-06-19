module ConstExpr
  ( parseConstExpr
  ) where

import Base
import Literal
import Operators (binopArith)
import ParseLite
import TypesToken

type ConstParser a = P [(String, Int)] Token String a

parseConstExpr :: [(String, Int)] -> [Token] -> Either String (Int, [Token])
parseConstExpr = parseRest (expression True 0)

expression :: Bool -> Int -> ConstParser Int
expression live minPrec = do
  lhs <- parseUnary live
  climb lhs
  where
    climb lhs = do
      mtok <- pPeekMaybe
      case mtok of
        Just tok -> case constTokenKind tok of
          TokPunct "?" | minPrec <= 2 -> do
            advance
            yes <- expression (live && lhs /= 0) 0
            constNeedPunct ":" "expected ':' in constant expression"
            no <- expression (live && lhs == 0) 2
            climb (if lhs /= 0 then yes else no)
          TokPunct op | Just (prec, _) <- binopArith op, prec >= minPrec -> do
            advance
            rhs <- expression (live && rhsLive op lhs) (prec + 1)
            value <- applyOp live op lhs rhs
            climb value
          _ -> pure lhs
        Nothing -> pure lhs

rhsLive :: String -> Int -> Bool
rhsLive op lhs = case op of
  "&&" -> lhs /= 0
  "||" -> lhs == 0
  _ -> True

applyOp :: Bool -> String -> Int -> Int -> ConstParser Int
applyOp live op a b = case op of
  "+" -> pure (a + b)
  "-" -> pure (a - b)
  "*" -> pure (a * b)
  "/" -> if b == 0 then divByZero live "division by zero in constant expression" else pure (a `div` b)
  "%" -> if b == 0 then divByZero live "modulo by zero in constant expression" else pure (a `mod` b)
  "<<" -> pure (shiftLeftInt a (max 0 b))
  ">>" -> pure (shiftRightInt a (max 0 b))
  "<" -> pure (boolToInt (a < b))
  "<=" -> pure (boolToInt (a <= b))
  ">" -> pure (boolToInt (a > b))
  ">=" -> pure (boolToInt (a >= b))
  "==" -> pure (boolToInt (a == b))
  "!=" -> pure (boolToInt (a /= b))
  "&" -> pure (bitAndInt a b)
  "^" -> pure (bitXorInt a b)
  "|" -> pure (bitOrInt a b)
  "&&" -> pure (boolToInt (a /= 0 && b /= 0))
  "||" -> pure (boolToInt (a /= 0 || b /= 0))
  _ -> pFail ("unhandled operator in constant expression: " ++ op)

divByZero :: Bool -> String -> ConstParser Int
divByZero live msg = if live then pFail msg else pure 0

parseUnary :: Bool -> ConstParser Int
parseUnary live = do
  mtok <- pPeekMaybe
  case mtok of
    Just tok -> case constTokenKind tok of
      TokPunct "!" -> advance >> (boolToInt . (== 0) <$> parseUnary live)
      TokPunct "+" -> advance >> parseUnary live
      TokPunct "-" -> advance >> (negate <$> parseUnary live)
      TokPunct "~" -> advance >> (bitNotInt <$> parseUnary live)
      _ -> parsePrimary live
    Nothing -> pFail "empty constant expression"

parsePrimary :: Bool -> ConstParser Int
parsePrimary live = do
  paren <- constEatPunct "("
  if paren
    then do
      value <- expression live 0
      constNeedPunct ")" "expected ')' in constant expression"
      pure value
    else do
      tok <- pTake "empty constant expression"
      case constTokenKind tok of
        TokIdent "defined" -> parseDefinedOperator
        TokIdent name -> maybe 0 id . lookup name <$> pEnv
        TokInt value -> pure (parseInt value)
        TokChar value -> pure (charValue value)
        _ -> pFail "unsupported token in constant expression"

parseDefinedOperator :: ConstParser Int
parseDefinedOperator = do
  paren <- constEatPunct "("
  name <- constNeedIdent "bad defined operator in #if expression"
  when paren (constNeedPunct ")" "bad defined operator in #if expression")
  pure (boolToInt (name /= ""))

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
