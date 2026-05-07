module Hcc.Parser
  ( ParseError(..)
  , parseProgram
  ) where

import Hcc.Ast
import Hcc.Token

data ParseError = ParseError SrcPos String
  deriving (Eq, Show)

newtype Parser a = Parser { runParser :: [Token] -> Either ParseError (a, [Token]) }

instance Functor Parser where
  fmap f p = Parser $ \toks -> case runParser p toks of
    Left err -> Left err
    Right (x, rest) -> Right (f x, rest)

instance Applicative Parser where
  pure x = Parser $ \toks -> Right (x, toks)
  pf <*> px = Parser $ \toks -> case runParser pf toks of
    Left err -> Left err
    Right (f, rest) -> case runParser px rest of
      Left err -> Left err
      Right (x, rest') -> Right (f x, rest')

instance Monad Parser where
  return = pure
  p >>= f = Parser $ \toks -> case runParser p toks of
    Left err -> Left err
    Right (x, rest) -> runParser (f x) rest

parseProgram :: [Token] -> Either ParseError Program
parseProgram toks = case runParser program toks of
  Left err -> Left err
  Right (ast, []) -> Right ast
  Right (_, tok:_) -> Left (parseErrorAt tok "trailing tokens")

program :: Parser Program
program = Program <$> topDecls

topDecls :: Parser [TopDecl]
topDecls = do
  mtok <- peekMaybe
  case mtok of
    Nothing -> pure []
    Just _ -> do
      decl <- topDecl
      rest <- topDecls
      pure (decl:rest)

topDecl :: Parser TopDecl
topDecl = do
  ty0 <- ctype
  (ty, name) <- declarator ty0
  ifM (eatPunct "(")
    (do
      params <- parameters
      isPrototype <- eatPunct ";"
      if isPrototype
        then pure (Prototype ty name params)
        else do
          body <- compound
          pure (Function ty name params body))
    (do
      initExpr <- optionalP (eatPunct "=" >> expr)
      needPunct ";"
      pure (Global ty name initExpr))

parameters :: Parser [Param]
parameters = do
  done <- eatPunct ")"
  if done
    then pure []
    else do
      voidOnly <- parameterVoidOnly
      if voidOnly
        then pure []
        else parseNonEmptyParams

parameterVoidOnly :: Parser Bool
parameterVoidOnly = Parser $ \toks -> case toks of
  Token _ (TokIdent "void"):Token _ (TokPunct ")"):rest -> Right (True, rest)
  _ -> Right (False, toks)

parseNonEmptyParams :: Parser [Param]
parseNonEmptyParams = do
  first <- parameter
  rest <- manyP (needPunct "," >> parameter)
  needPunct ")"
  pure (first:rest)

parameter :: Parser Param
parameter = do
  ty0 <- ctype
  ty <- pointerStars ty0
  name <- optionalIdent
  pure (Param ty name)

compound :: Parser [Stmt]
compound = needPunct "{" >> manyUntil (eatPunct "}") stmt

stmt :: Parser Stmt
stmt = do
  tok <- peek
  case tokenKind tok of
    TokIdent "return" -> advanceToken >> parseReturn
    TokIdent "if" -> advanceToken >> parseIf
    TokIdent "while" -> advanceToken >> parseWhile
    TokIdent "do" -> advanceToken >> parseDoWhile
    TokIdent "for" -> advanceToken >> parseFor
    TokIdent "goto" -> advanceToken >> parseGoto
    _ | startsType tok -> parseDeclStmt
    TokIdent name -> do
      isLabel <- peekSecondPunct ":"
      if isLabel
        then advanceToken >> needPunct ":" >> pure (SLabel name)
        else parseExprStmt
    TokPunct "{" -> SBlock <$> compound
    _ -> parseExprStmt

parseExprStmt :: Parser Stmt
parseExprStmt = do
  e <- expr
  needPunct ";"
  pure (SExpr e)

parseGoto :: Parser Stmt
parseGoto = do
  name <- needIdent
  needPunct ";"
  pure (SGoto name)

parseReturn :: Parser Stmt
parseReturn = do
  semi <- eatPunct ";"
  if semi
    then pure (SReturn Nothing)
    else do
      e <- expr
      needPunct ";"
      pure (SReturn (Just e))

parseIf :: Parser Stmt
parseIf = do
  needPunct "("
  cond <- expr
  needPunct ")"
  yes <- stmtAsBlock
  hasElse <- eatIdent "else"
  no <- if hasElse then stmtAsBlock else pure []
  pure (SIf cond yes no)

parseWhile :: Parser Stmt
parseWhile = do
  needPunct "("
  cond <- expr
  needPunct ")"
  body <- stmtAsBlock
  pure (SWhile cond body)

parseDoWhile :: Parser Stmt
parseDoWhile = do
  body <- stmtAsBlock
  needIdentValue "while"
  needPunct "("
  cond <- expr
  needPunct ")"
  needPunct ";"
  pure (SDoWhile body cond)

parseFor :: Parser Stmt
parseFor = do
  needPunct "("
  initExpr <- optionalExprUntil ";"
  cond <- optionalExprUntil ";"
  stepExpr <- optionalExprUntil ")"
  body <- stmtAsBlock
  pure (SFor initExpr cond stepExpr body)

optionalExprUntil :: String -> Parser (Maybe Expr)
optionalExprUntil punct = do
  done <- eatPunct punct
  if done
    then pure Nothing
    else do
      e <- expr
      needPunct punct
      pure (Just e)

stmtAsBlock :: Parser [Stmt]
stmtAsBlock = do
  tok <- peek
  case tokenKind tok of
    TokPunct "{" -> compound
    _ -> (:[]) <$> stmt

parseDeclStmt :: Parser Stmt
parseDeclStmt = do
  ty0 <- ctype
  (ty, name) <- declarator ty0
  initExpr <- optionalP (eatPunct "=" >> expr)
  needPunct ";"
  pure (SDecl ty name initExpr)

ctype :: Parser CType
ctype = skipQualifiers >> baseType where
  baseType = do
    tok <- peek
    case tokenKind tok of
      TokIdent "void" -> advanceToken >> pure CVoid
      TokIdent "int" -> advanceToken >> pure CInt
      TokIdent "char" -> advanceToken >> pure CChar
      TokIdent "signed" -> advanceToken >> signedBaseType
      TokIdent "unsigned" -> advanceToken >> unsignedBaseType
      TokIdent "long" -> advanceToken >> pure CLong
      TokIdent name | isKnownTypeName name -> advanceToken >> pure (CNamed name)
      _ -> failAt tok "expected type"

signedBaseType :: Parser CType
signedBaseType = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "char") -> advanceToken >> pure CChar
    Just (TokIdent "int") -> advanceToken >> pure CInt
    _ -> pure CInt

unsignedBaseType :: Parser CType
unsignedBaseType = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "char") -> advanceToken >> pure CUnsignedChar
    Just (TokIdent "short") -> advanceToken >> pure CUnsigned
    Just (TokIdent "int") -> advanceToken >> pure CUnsigned
    _ -> pure CUnsigned

skipQualifiers :: Parser ()
skipQualifiers = do
  tok <- peekMaybe
  case fmap tokenKind tok of
    Just (TokIdent name) | name `elem` ["const", "volatile", "static", "extern", "register"] ->
      advanceToken >> skipQualifiers
    _ -> pure ()

declarator :: CType -> Parser (CType, String)
declarator ty0 = do
  ty <- pointerStars ty0
  name <- needIdent
  ty' <- arraySuffixes ty
  pure (ty', name)

pointerStars :: CType -> Parser CType
pointerStars ty = do
  star <- eatPunct "*"
  if star
    then pointerStars (CPtr ty)
    else pure ty

arraySuffixes :: CType -> Parser CType
arraySuffixes ty = do
  open <- eatPunct "["
  if open
    then optionalP expr >> needPunct "]" >> arraySuffixes (CPtr ty)
    else pure ty

expr :: Parser Expr
expr = expression 1

expression :: Int -> Parser Expr
expression minPrec = do
  lhs <- postfix =<< unary
  climb lhs where
    climb lhs = do
      mtok <- peekMaybe
      case mtok of
        Just tok -> case tokenKind tok of
          TokPunct op | Just (prec, assoc) <- binop op, prec >= minPrec -> do
            advanceToken
            rhs <- expression (if assoc == RightAssoc then prec else prec + 1)
            let node = assignNode op lhs rhs
            climb node
          _ -> pure lhs
        Nothing -> pure lhs

data Assoc = LeftAssoc | RightAssoc
  deriving (Eq, Show)

binop :: String -> Maybe (Int, Assoc)
binop op = case op of
  "=" -> Just (1, RightAssoc)
  "+=" -> Just (1, RightAssoc)
  "-=" -> Just (1, RightAssoc)
  "||" -> Just (2, LeftAssoc)
  "&&" -> Just (3, LeftAssoc)
  "|" -> Just (4, LeftAssoc)
  "^" -> Just (5, LeftAssoc)
  "&" -> Just (6, LeftAssoc)
  "==" -> Just (7, LeftAssoc)
  "!=" -> Just (7, LeftAssoc)
  "<" -> Just (8, LeftAssoc)
  "<=" -> Just (8, LeftAssoc)
  ">" -> Just (8, LeftAssoc)
  ">=" -> Just (8, LeftAssoc)
  "<<" -> Just (9, LeftAssoc)
  ">>" -> Just (9, LeftAssoc)
  "+" -> Just (10, LeftAssoc)
  "-" -> Just (10, LeftAssoc)
  "*" -> Just (11, LeftAssoc)
  "/" -> Just (11, LeftAssoc)
  "%" -> Just (11, LeftAssoc)
  _ -> Nothing

unary :: Parser Expr
unary = do
  tok <- peek
  case tokenKind tok of
    TokPunct op | op `elem` ["++", "--"] ->
      advanceToken >> EUnary op <$> (postfix =<< unary)
    TokPunct op | op `elem` ["+", "-", "!", "~", "*", "&"] ->
      advanceToken >> EUnary op <$> (postfix =<< unary)
    TokIdent "sizeof" ->
      advanceToken >> EUnary "sizeof" <$> (postfix =<< unary)
    TokInt s -> advanceToken >> pure (EInt s)
    TokChar s -> advanceToken >> pure (EChar s)
    TokString s -> advanceToken >> pure (EString s)
    TokIdent s -> advanceToken >> pure (EVar s)
    TokPunct "(" -> do
      advanceToken
      isCast <- nextStartsType
      if isCast
        then do
          ty <- ctype
          needPunct ")"
          ECast ty <$> (postfix =<< unary)
        else do
          e <- expr
          needPunct ")"
          pure e
    _ -> failAt tok "expected expression"

assignNode :: String -> Expr -> Expr -> Expr
assignNode op lhs rhs = case op of
  "=" -> EAssign lhs rhs
  "+=" -> EAssign lhs (EBinary "+" lhs rhs)
  "-=" -> EAssign lhs (EBinary "-" lhs rhs)
  _ -> EBinary op lhs rhs

postfix :: Expr -> Parser Expr
postfix base = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokPunct "(") -> do
      advanceToken
      args <- arguments
      postfix (ECall base args)
    Just (TokPunct "[") -> do
      advanceToken
      ix <- expr
      needPunct "]"
      postfix (EIndex base ix)
    Just (TokPunct "++") -> do
      advanceToken
      postfix (EPostfix "++" base)
    Just (TokPunct "--") -> do
      advanceToken
      postfix (EPostfix "--" base)
    _ -> pure base

arguments :: Parser [Expr]
arguments = do
  done <- eatPunct ")"
  if done
    then pure []
    else do
      first <- expr
      rest <- manyP (needPunct "," >> expr)
      needPunct ")"
      pure (first:rest)

startsType :: Token -> Bool
startsType tok = case tokenKind tok of
  TokIdent name -> name `elem` ["void", "int", "char", "signed", "unsigned", "long", "const", "volatile", "static", "extern", "register"] || isKnownTypeName name
  _ -> False

isKnownTypeName :: String -> Bool
isKnownTypeName name = name `elem` ["FILE", "FUNCTION", "size_t"]

manyP :: Parser a -> Parser [a]
manyP p = do
  mx <- optionalP p
  case mx of
    Nothing -> pure []
    Just x -> (x:) <$> manyP p

manyUntil :: Parser Bool -> Parser a -> Parser [a]
manyUntil end p = do
  done <- end
  if done
    then pure []
    else do
      x <- p
      xs <- manyUntil end p
      pure (x:xs)

optionalP :: Parser a -> Parser (Maybe a)
optionalP p = Parser $ \toks -> case runParser p toks of
  Left _ -> Right (Nothing, toks)
  Right (x, rest) -> Right (Just x, rest)

ifM :: Parser Bool -> Parser a -> Parser a -> Parser a
ifM test yes no = do
  b <- test
  if b then yes else no

eatPunct :: String -> Parser Bool
eatPunct s = Parser $ \toks -> case toks of
  Token _ (TokPunct p):rest | p == s -> Right (True, rest)
  _ -> Right (False, toks)

needPunct :: String -> Parser ()
needPunct s = do
  ok <- eatPunct s
  if ok then pure () else peek >>= \tok -> failAt tok ("expected " ++ show s)

eatIdent :: String -> Parser Bool
eatIdent s = Parser $ \toks -> case toks of
  Token _ (TokIdent p):rest | p == s -> Right (True, rest)
  _ -> Right (False, toks)

needIdent :: Parser String
needIdent = do
  tok <- peek
  case tokenKind tok of
    TokIdent s -> advanceToken >> pure s
    _ -> failAt tok "expected identifier"

optionalIdent :: Parser String
optionalIdent = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent s) -> advanceToken >> pure s
    _ -> pure ""

needIdentValue :: String -> Parser ()
needIdentValue expected = do
  tok <- peek
  case tokenKind tok of
    TokIdent s | s == expected -> advanceToken
    _ -> failAt tok ("expected " ++ show expected)

peek :: Parser Token
peek = Parser $ \toks -> case toks of
  [] -> Left (ParseError (SrcPos 1 1) "unexpected end of input")
  tok:_ -> Right (tok, toks)

peekMaybe :: Parser (Maybe Token)
peekMaybe = Parser $ \toks -> Right (case toks of [] -> Nothing; tok:_ -> Just tok, toks)

peekSecondPunct :: String -> Parser Bool
peekSecondPunct punct = Parser $ \toks -> case toks of
  _:Token _ (TokPunct p):_ | p == punct -> Right (True, toks)
  _ -> Right (False, toks)

nextStartsType :: Parser Bool
nextStartsType = do
  mtok <- peekMaybe
  pure (case mtok of
    Just tok -> startsType tok
    Nothing -> False)

advanceToken :: Parser ()
advanceToken = Parser $ \toks -> case toks of
  [] -> Left (ParseError (SrcPos 1 1) "unexpected end of input")
  _:rest -> Right ((), rest)

failAt :: Token -> String -> Parser a
failAt tok msg = Parser $ \_ -> Left (parseErrorAt tok msg)

parseErrorAt :: Token -> String -> ParseError
parseErrorAt (Token (Span pos _) _) msg = ParseError pos msg

tokenKind :: Token -> TokenKind
tokenKind (Token _ kind) = kind
