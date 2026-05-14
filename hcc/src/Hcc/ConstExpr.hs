module ConstExpr
  ( parseConstExpr
  ) where

import Base
import Literal
import Operators
import ParseLite
import TypesToken

type ConstParser a = P [(String, Int)] Token String a

-- Values carry a "this operand is unsigned" flag so that comparisons, shifts,
-- and division can pick the correct semantics. Per C11 6.10.1p4 the usual
-- arithmetic conversions apply, so if either operand of a binary op is
-- unsigned, the result is unsigned.
type CValue = (Int, Bool)

parseConstExpr :: [(String, Int)] -> [Token] -> Either String (Int, [Token])
parseConstExpr env toks = case parseRest (expression 0) env toks of
  Left err -> Left err
  Right (value, rest) -> Right (fst value, rest)

expression :: Int -> ConstParser CValue
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
            climb (if fst lhs /= 0 then yes else no)
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

applyOp :: String -> CValue -> CValue -> ConstParser CValue
applyOp op lv rv = case op of
  "+" -> pure (a + b, u)
  "-" -> pure (a - b, u)
  "*" -> pure (a * b, u)
  "/" -> if b == 0
    then pFail "division by zero in constant expression"
    else if u
      then pure (unsignedDiv a b, True)
      else pure (a `div` b, False)
  "%" -> if b == 0
    then pFail "modulo by zero in constant expression"
    else if u
      then pure (unsignedMod a b, True)
      else pure (a `mod` b, False)
  "<<" -> pure (shiftLeftInt a (max 0 b), u)
  ">>" -> if u
    then pure (unsignedShiftRight a (max 0 b), True)
    else pure (shiftRightInt a (max 0 b), False)
  "<" -> pure (truth (compareLt u a b), False)
  "<=" -> pure (truth (compareLe u a b), False)
  ">" -> pure (truth (compareLt u b a), False)
  ">=" -> pure (truth (compareLe u b a), False)
  "==" -> pure (truth (a == b), False)
  "!=" -> pure (truth (a /= b), False)
  "&" -> pure (bitAndInt a b, u)
  "^" -> pure (bitXorInt a b, u)
  "|" -> pure (bitOrInt a b, u)
  "&&" -> pure (truth (a /= 0 && b /= 0), False)
  "||" -> pure (truth (a /= 0 || b /= 0), False)
  _ -> pFail ("unhandled operator in constant expression: " ++ op)
  where
    a = fst lv
    b = fst rv
    u = snd lv || snd rv

-- C11 6.10.1p4 + 6.3.1.8: relational operators on operands of differing
-- signedness take the unsigned conversion. Treat the Int value as a 64-bit
-- two's-complement word and pick the comparison accordingly.
compareLt :: Bool -> Int -> Int -> Bool
compareLt unsigned a b =
  if unsigned
    then unsignedLt a b
    else a < b

compareLe :: Bool -> Int -> Int -> Bool
compareLe unsigned a b = compareLt unsigned a b || a == b

unsignedLt :: Int -> Int -> Bool
unsignedLt a b =
  if a < 0
    then if b < 0 then a < b else False
    else if b < 0 then True else a < b

-- Unsigned division reduces to signed division when both operands are
-- non-negative. When either has bit 63 set we fall back to a slow loop so
-- the result matches uintmax_t arithmetic; #if rarely needs this path.
unsignedDiv :: Int -> Int -> Int
unsignedDiv a b =
  if a >= 0 && b > 0
    then a `div` b
    else unsignedQuotRemQuot a b

unsignedMod :: Int -> Int -> Int
unsignedMod a b =
  if a >= 0 && b > 0
    then a `mod` b
    else a - unsignedQuotRemQuot a b * b

unsignedQuotRemQuot :: Int -> Int -> Int
unsignedQuotRemQuot a b =
  if unsignedLt a b
    then 0
    else 1 + unsignedQuotRemQuot (a - b) b

unsignedShiftRight :: Int -> Int -> Int
unsignedShiftRight a count =
  if a >= 0
    then shiftRightInt a count
    else
      -- Logical shift: move the sign bit into a normal bit position before
      -- the loop-based shiftRightInt sees it.
      shiftRightInt (a `div` 2 + 4611686018427387904) (max 0 (count - 1))

parseUnary :: ConstParser CValue
parseUnary = do
  mtok <- pPeekMaybe
  case mtok of
    Just tok -> case constTokenKind tok of
      TokPunct "!" -> do
        advance
        inner <- parseUnary
        pure (truth (fst inner == 0), False)
      TokPunct "+" -> advance >> parseUnary
      TokPunct "-" -> do
        advance
        inner <- parseUnary
        pure (negate (fst inner), snd inner)
      TokPunct "~" -> do
        advance
        inner <- parseUnary
        pure (bitNotInt (fst inner), snd inner)
      _ -> parsePrimary
    Nothing -> pFail "empty constant expression"

parsePrimary :: ConstParser CValue
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
          pure (maybe 0 id (lookup name env), False)
        TokInt value -> pure (parseInt value, intLiteralIsUnsigned value)
        TokChar value -> pure (charValue value, False)
        _ -> pFail "unsupported token in constant expression"

parseDefinedOperator :: ConstParser CValue
parseDefinedOperator = do
  paren <- constEatPunct "("
  if paren
    then do
      name <- constNeedIdent "bad defined operator in #if expression"
      constNeedPunct ")" "bad defined operator in #if expression"
      pure (truth (name /= ""), False)
    else do
      name <- constNeedIdent "bad defined operator in #if expression"
      pure (truth (name /= ""), False)

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
