module ConstExpr
  ( parseConstExpr
  , parsePPConstExpr
  ) where

import Base
import Literal
import Operators (binopArith)
import ParseLite
import TypesToken

type ConstParser a = P [(String, Int)] Token String a

-- Retain the parser's Int-facing API. All intermediate arithmetic, including
-- comparisons and conditional common types, is target-width byte arithmetic.
parseConstExpr :: [(String, Int)] -> [Token] -> Either String (Int, [Token])
parseConstExpr env toks = do
  (value, rest) <- parseRest (expression False True 0) env toks
  Right (constantToInt value, rest)

-- #if has a different integer model: signed and unsigned integer types act as
-- intmax_t and uintmax_t, including otherwise 32-bit unsuffixed constants.
parsePPConstExpr :: [Token] -> Either String (Bool, [Token])
parsePPConstExpr toks = do
  (value, rest) <- parseRest (expression True True 0) [] toks
  Right (constantTrue value, rest)

expression :: Bool -> Bool -> Int -> ConstParser Constant
expression pp live minPrec = do
  lhs <- parseUnary pp live
  climb lhs
  where
    climb lhs = do
      mtok <- pPeekMaybe
      case mtok of
        Just tok -> case constTokenKind tok of
          TokPunct "?" | minPrec <= 2 -> do
            advance
            yes <- expression pp (live && constantTrue lhs) 0
            constNeedPunct ":" "expected ':' in constant expression"
            no <- expression pp (live && not (constantTrue lhs)) 2
            let (yes', no') = constantCommon yes no
            climb (if constantTrue lhs then yes' else no')
          TokPunct op | Just (prec, _) <- binopArith op, prec >= minPrec -> do
            advance
            rhs <- expression pp (live && rhsLive op lhs) (prec + 1)
            value <- applyOp pp live op lhs rhs
            climb value
          _ -> pure lhs
        Nothing -> pure lhs

rhsLive :: String -> Constant -> Bool
rhsLive op lhs = case op of
  "&&" -> constantTrue lhs
  "||" -> not (constantTrue lhs)
  _ -> True

constInt :: Bool -> Int -> Constant
constInt pp = constantInt (if pp then 8 else 4)

applyOp :: Bool -> Bool -> String -> Constant -> Constant -> ConstParser Constant
applyOp pp live op a b = case constantBinary op a b of
  Left msg ->
    if live then pFail msg
    else case (if op == "<<" || op == ">>" then a else fst (constantCommon a b)) of
      Constant size unsigned _ -> pure (Constant size unsigned (replicate size 0))
  Right value -> pure (if op `elem` ["<", "<=", ">", ">=", "==", "!=", "&&", "||"]
                      then constInt pp (boolToInt (constantTrue value)) else value)

parseUnary :: Bool -> Bool -> ConstParser Constant
parseUnary pp live = do
  mtok <- pPeekMaybe
  case mtok of
    Just tok -> case constTokenKind tok of
      TokPunct "!" -> advance >> (constInt pp . boolToInt . not . constantTrue <$> parseUnary pp live)
      TokPunct "+" -> advance >> parseUnary pp live
      TokPunct "-" -> advance >> (constantUnary "-" <$> parseUnary pp live)
      TokPunct "~" -> advance >> (constantUnary "~" <$> parseUnary pp live)
      _ -> parsePrimary pp live
    Nothing -> pFail "empty constant expression"

parsePrimary :: Bool -> Bool -> ConstParser Constant
parsePrimary pp live = do
  paren <- constEatPunct "("
  if paren
    then do
      value <- expression pp live 0
      constNeedPunct ")" "expected ')' in constant expression"
      pure value
    else do
      tok <- pTake "empty constant expression"
      case constTokenKind tok of
        TokIdent name -> constInt pp . maybe 0 id . lookup name <$> pEnv
        TokInt value -> pure (constantLiteral pp value)
        TokChar value -> pure (constInt pp (charValue value))
        _ -> pFail "unsupported token in constant expression"

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

constTokenKind :: Token -> TokenKind
constTokenKind (Token _ kind) = kind
