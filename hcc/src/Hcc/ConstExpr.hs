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
parseConstExpr env toks = parseRest (expression True 0) env toks

expression :: Bool -> Int -> ConstParser Int
expression active minPrec = do
  lhs <- parseUnary active
  climb lhs
  where
    climb lhs = do
      mtok <- pPeekMaybe
      case mtok of
        Just tok -> case constTokenKind tok of
          TokPunct "?" | minPrec <= 2 -> do
            advance
            yes <- expression (active && lhs /= 0) 0
            constNeedPunct ":" "expected ':' in constant expression"
            no <- expression (active && lhs == 0) 2
            climb (if not active then 0 else if lhs /= 0 then yes else no)
          TokPunct op | Just prec <- binop op, prec >= minPrec -> do
            advance
            let rhsActive = binaryRhsActive active op lhs
            rhs <- expression rhsActive (prec + 1)
            value <- if active then applyOp op lhs rhs else pure 0
            climb value
          _ -> pure lhs
        Nothing -> pure lhs

binaryRhsActive :: Bool -> String -> Int -> Bool
binaryRhsActive active op lhs =
  active && case op of
    "&&" -> lhs /= 0
    "||" -> lhs == 0
    _ -> True

binop :: String -> Maybe Int
binop op = fmap fst (binopArith op)

applyOp :: String -> Int -> Int -> ConstParser Int
applyOp op a b = case evalConstBinOp op a b of
  Just value -> pure value
  Nothing ->
    if op == "/" || op == "%"
    then pFail "division by zero in constant expression"
    else pFail ("unhandled operator in constant expression: " ++ op)

parseUnary :: Bool -> ConstParser Int
parseUnary active = do
  cast <- constEatCast
  if cast
    then parseUnary active
    else do
      mtok <- pPeekMaybe
      case mtok of
        Just tok -> case constTokenKind tok of
          TokPunct "!" -> advance >> unaryValue active (boolToInt . (== 0)) <$> parseUnary active
          TokPunct "+" -> advance >> parseUnary active
          TokPunct "-" -> advance >> unaryValue active negate <$> parseUnary active
          TokPunct "~" -> advance >> unaryValue active bitNotInt <$> parseUnary active
          _ -> parsePrimary active
        Nothing -> pFail "empty constant expression"

unaryValue :: Bool -> (Int -> Int) -> Int -> Int
unaryValue active f value = if active then f value else 0

parsePrimary :: Bool -> ConstParser Int
parsePrimary active = do
  paren <- constEatPunct "("
  if paren
    then do
      value <- expression active 0
      constNeedPunct ")" "expected ')' in constant expression"
      pure value
    else do
      tok <- pTake "empty constant expression"
      case constTokenKind tok of
        TokIdent "defined" -> parseDefinedOperator
        TokIdent name -> do
          env <- pEnv
          pure (if active then maybe 0 id (lookup name env) else 0)
        TokInt value -> pure (if active then parseInt value else 0)
        TokChar value -> pure (if active then charValue value else 0)
        _ -> pFail "unsupported token in constant expression"

parseDefinedOperator :: ConstParser Int
parseDefinedOperator = do
  paren <- constEatPunct "("
  if paren
    then do
      name <- constNeedIdent "bad defined operator in #if expression"
      constNeedPunct ")" "bad defined operator in #if expression"
      pure (boolToInt (name /= ""))
    else do
      name <- constNeedIdent "bad defined operator in #if expression"
      pure (boolToInt (name /= ""))

advance :: ConstParser ()
advance = pSkip "unexpected end of constant expression"

constEatPunct :: String -> ConstParser Bool
constEatPunct expected = pRaw $ \env toks -> case toks of
  Token _ (TokPunct punct):rest | punct == expected -> Consumed (Ok True env rest)
  _ -> Unconsumed (Ok False env toks)

constEatCast :: ConstParser Bool
constEatCast = pRaw $ \env toks -> case toks of
  Token _ (TokPunct "("):rest -> case skipConstTypeName False rest of
    Just after -> Consumed (Ok True env after)
    Nothing -> Unconsumed (Ok False env toks)
  _ -> Unconsumed (Ok False env toks)

skipConstTypeName :: Bool -> [Token] -> Maybe [Token]
skipConstTypeName seen toks = case toks of
  Token _ (TokIdent name):rest | name `elem` constTypeNameWords ->
    skipConstTypeName True rest
  Token _ (TokPunct "*"):rest | seen ->
    skipConstTypeName True rest
  Token _ (TokPunct ")"):rest | seen ->
    Just rest
  _ -> Nothing

constTypeNameWords :: [String]
constTypeNameWords =
  [ "void", "_Bool", "int", "char", "signed", "unsigned", "short", "long"
  , "float", "double", "const", "volatile"
  ]

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
