module Hcc.Parser
  ( ParseError(..)
  , parseProgram
  ) where

import Hcc.Ast
import Hcc.ConstExpr
import Hcc.Token

data ParseError = ParseError SrcPos String
  deriving (Eq, Show)

newtype Parser a = Parser { runParser :: [String] -> [Token] -> Either ParseError (a, [Token]) }

instance Functor Parser where
  fmap f p = Parser $ \env toks -> case runParser p env toks of
    Left err -> Left err
    Right (x, rest) -> Right (f x, rest)

instance Applicative Parser where
  pure x = Parser $ \_env toks -> Right (x, toks)
  pf <*> px = Parser $ \env toks -> case runParser pf env toks of
    Left err -> Left err
    Right (f, rest) -> case runParser px env rest of
      Left err -> Left err
      Right (x, rest') -> Right (f x, rest')

instance Monad Parser where
  return = pure
  p >>= f = Parser $ \env toks -> case runParser p env toks of
    Left err -> Left err
    Right (x, rest) -> runParser (f x) env rest

parseProgram :: [Token] -> Either ParseError Program
parseProgram toks = case runParser program (builtinTypeNames ++ collectTypedefNames toks) toks of
  Left err -> Left err
  Right (Program decls, []) -> Right (Program (EnumConstants (collectEnumConstants toks) : decls))
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
  typedef <- eatIdent "typedef"
  if typedef
    then do
      structDecl <- optionalP typedefAggregateDecl
      case structDecl of
        Just decl -> pure decl
        Nothing -> skipUntilTopLevelSemi >> pure TypeDecl
    else topDeclNoTypedef

topDeclNoTypedef :: Parser TopDecl
topDeclNoTypedef = do
  structDecl <- optionalP standaloneAggregateDecl
  case structDecl of
    Just decl -> pure decl
    Nothing -> topDeclNoStruct

topDeclNoStruct :: Parser TopDecl
topDeclNoStruct = do
  ty0 <- ctype
  standalone <- eatPunct ";"
  if standalone
    then pure TypeDecl
    else do
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
          initExpr <- optionalP (eatPunct "=" >> initializerExpr)
          rest <- declarationItemsTail ty0
          pure (globalDecl ((ty, name, initExpr):rest)))

globalDecl :: [(CType, String, Maybe Expr)] -> TopDecl
globalDecl decls = case decls of
  [(ty, name, initExpr)] -> Global ty name initExpr
  _ -> Globals decls

typedefAggregateDecl :: Parser TopDecl
typedefAggregateDecl = do
  isUnion <- aggregateKeyword
  tag <- optionalIdent
  fields <- aggregateBody
  alias <- optionalIdent
  skipTypedefDeclaratorTail
  pure (StructDecl isUnion (structDeclName tag alias) fields)

standaloneAggregateDecl :: Parser TopDecl
standaloneAggregateDecl = do
  isUnion <- aggregateKeyword
  tag <- optionalIdent
  fields <- aggregateBody
  needPunct ";"
  pure (StructDecl isUnion tag fields)

aggregateKeyword :: Parser Bool
aggregateKeyword = do
  tok <- peek
  case tokenKind tok of
    TokIdent "struct" -> advanceToken >> pure False
    TokIdent "union" -> advanceToken >> pure True
    _ -> failAt tok "expected aggregate declaration"

structDeclName :: String -> String -> String
structDeclName tag alias =
  if tag /= "" then tag else alias

aggregateBody :: Parser [Field]
aggregateBody = do
  needPunct "{"
  concat <$> manyUntil (eatPunct "}") fieldDecl

fieldDecl :: Parser [Field]
fieldDecl = do
  ty0 <- ctype
  fields <- fieldDeclarators ty0
  needPunct ";"
  pure fields

fieldDeclarators :: CType -> Parser [Field]
fieldDeclarators ty0 = do
  first <- fieldDeclarator ty0
  rest <- manyP (needPunct "," >> fieldDeclarator ty0)
  pure (first:rest)

fieldDeclarator :: CType -> Parser Field
fieldDeclarator ty0 = do
  grouped <- eatPunct "("
  if grouped
    then do
      ty <- pointerStars ty0
      name <- optionalIdent
      needPunct ")"
      fnTail <- eatPunct "("
      if fnTail then skipBalanced "(" ")" else pure ()
      ty' <- arraySuffixes (CPtr ty)
      pure (Field ty' name)
    else do
      ty <- pointerStars ty0
      name <- optionalIdent
      bitfield <- eatPunct ":"
      ty' <- if bitfield
        then assignExpr >> pure ty
        else arraySuffixes ty
      pure (Field ty' name)

skipTypedefDeclaratorTail :: Parser ()
skipTypedefDeclaratorTail = do
  comma <- eatPunct ","
  if comma
    then skipUntilTopLevelSemi
    else needPunct ";"

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
parameterVoidOnly = Parser $ \_env toks -> case toks of
  Token _ (TokIdent "void"):Token _ (TokPunct ")"):rest -> Right (True, rest)
  _ -> Right (False, toks)

parseNonEmptyParams :: Parser [Param]
parseNonEmptyParams = do
  first <- parameter
  rest <- parameterTail
  needPunct ")"
  pure (first:rest)

parameterTail :: Parser [Param]
parameterTail = do
  comma <- eatPunct ","
  if not comma
    then pure []
    else do
      variadic <- eatPunct "..."
      if variadic
        then pure []
        else do
          p <- parameter
          ps <- parameterTail
          pure (p:ps)

parameter :: Parser Param
parameter = do
  ty0 <- ctype
  (ty, name) <- parameterDeclarator ty0
  pure (Param ty name)

parameterDeclarator :: CType -> Parser (CType, String)
parameterDeclarator ty0 = do
  grouped <- eatPunct "("
  if grouped
    then do
      ty <- pointerStars ty0
      name <- optionalIdent
      needPunct ")"
      fnTail <- eatPunct "("
      if fnTail then skipBalanced "(" ")" else pure ()
      pure (CPtr ty, name)
    else do
      ty <- pointerStars ty0
      name <- optionalIdent
      ty' <- arraySuffixes ty
      pure (ty', name)

compound :: Parser [Stmt]
compound = needPunct "{" >> manyUntil (eatPunct "}") stmt

stmt :: Parser Stmt
stmt = do
  tok <- peek
  tokIsType <- tokenStartsType tok
  case tokenKind tok of
    TokIdent "return" -> advanceToken >> parseReturn
    TokIdent "if" -> advanceToken >> parseIf
    TokIdent "while" -> advanceToken >> parseWhile
    TokIdent "do" -> advanceToken >> parseDoWhile
    TokIdent "for" -> advanceToken >> parseFor
    TokIdent "switch" -> advanceToken >> parseSwitch
    TokIdent "case" -> advanceToken >> parseCase
    TokIdent "default" -> advanceToken >> needPunct ":" >> pure SDefault
    TokIdent "break" -> advanceToken >> needPunct ";" >> pure SBreak
    TokIdent "continue" -> advanceToken >> needPunct ";" >> pure SContinue
    TokIdent "goto" -> advanceToken >> parseGoto
    TokPunct ";" -> advanceToken >> pure (SExpr (EInt "0"))
    _ | tokIsType -> parseDeclStmt
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

parseSwitch :: Parser Stmt
parseSwitch = do
  needPunct "("
  value <- expr
  needPunct ")"
  body <- stmtAsBlock
  pure (SSwitch value body)

parseCase :: Parser Stmt
parseCase = do
  value <- expr
  needPunct ":"
  pure (SCase value)

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
    TokPunct "{" -> (:[]) . SBlock <$> compound
    _ -> (:[]) <$> stmt

parseDeclStmt :: Parser Stmt
parseDeclStmt = do
  ty0 <- ctype
  standalone <- eatPunct ";"
  if standalone
    then pure (SExpr (EInt "0"))
    else do
      first <- declarationItem ty0
      rest <- declarationItemsTail ty0
      pure (declStmt (first:rest))

declStmt :: [(CType, String, Maybe Expr)] -> Stmt
declStmt decls = case decls of
  [(ty, name, initExpr)] -> SDecl ty name initExpr
  _ -> SDecls decls

declarationItem :: CType -> Parser (CType, String, Maybe Expr)
declarationItem ty0 = do
  (ty, name) <- declarator ty0
  initExpr <- optionalP (eatPunct "=" >> initializerExpr)
  pure (ty, name, initExpr)

declarationItemsTail :: CType -> Parser [(CType, String, Maybe Expr)]
declarationItemsTail ty0 = do
  semi <- eatPunct ";"
  if semi
    then pure []
    else do
      needPunct ","
      item <- declarationItem ty0
      rest <- declarationItemsTail ty0
      pure (item:rest)

ctype :: Parser CType
ctype = do
  skipQualifiers
  ty <- baseType
  skipQualifiers
  pure ty
  where
  baseType = do
    tok <- peek
    case tokenKind tok of
      TokIdent "void" -> advanceToken >> pure CVoid
      TokIdent "int" -> advanceToken >> pure CInt
      TokIdent "char" -> advanceToken >> pure CChar
      TokIdent "signed" -> advanceToken >> signedBaseType
      TokIdent "unsigned" -> advanceToken >> unsignedBaseType
      TokIdent "short" -> advanceToken >> pure CInt
      TokIdent "long" -> advanceToken >> longBaseType
      TokIdent "float" -> advanceToken >> pure CFloat
      TokIdent "double" -> advanceToken >> pure CDouble
      TokIdent "struct" -> aggregateType CStruct CStructNamed CStructDef
      TokIdent "union" -> aggregateType CUnion CUnionNamed CUnionDef
      TokIdent "enum" -> enumType
      TokIdent name -> do
        known <- isKnownTypeNameP name
        if known
          then advanceToken >> pure (CNamed name)
          else failAt tok "expected type"
      _ -> failAt tok "expected type"

typeName :: Parser CType
typeName = ctype >>= pointerStars

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
    Just (TokIdent "long") -> advanceToken >> unsignedLongTail
    Just (TokIdent "int") -> advanceToken >> pure CUnsigned
    _ -> pure CUnsigned

unsignedLongTail :: Parser CType
unsignedLongTail = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "long") -> advanceToken >> optionalUnsignedLongInt
    Just (TokIdent "int") -> advanceToken >> pure CUnsigned
    _ -> pure CUnsigned

optionalUnsignedLongInt :: Parser CType
optionalUnsignedLongInt = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "int") -> advanceToken >> pure CUnsigned
    _ -> pure CUnsigned

longBaseType :: Parser CType
longBaseType = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "double") -> advanceToken >> pure CLongDouble
    Just (TokIdent "int") -> advanceToken >> pure CLong
    Just (TokIdent "long") -> advanceToken >> optionalLongLongTail
    _ -> pure CLong

optionalLongLongTail :: Parser CType
optionalLongLongTail = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "int") -> advanceToken >> pure CLong
    _ -> pure CLong

aggregateType :: (String -> CType) -> (String -> [Field] -> CType) -> ([Field] -> CType) -> Parser CType
aggregateType mkType mkNamed mkInline = do
  advanceToken
  name <- optionalIdent
  hasBody <- eatPunct "{"
  if hasBody
    then do
      fields <- aggregateBodyAfterOpen
      pure (if name == "" then mkInline fields else mkNamed name fields)
    else pure (mkType name)

aggregateBodyAfterOpen :: Parser [Field]
aggregateBodyAfterOpen = concat <$> manyUntil (eatPunct "}") fieldDecl

enumType :: Parser CType
enumType = do
  advanceToken
  name <- optionalIdent
  hasBody <- eatPunct "{"
  if hasBody then skipBalanced "{" "}" else pure ()
  pure (CEnum name)

skipQualifiers :: Parser ()
skipQualifiers = do
  tok <- peekMaybe
  case fmap tokenKind tok of
    Just (TokIdent name) | name `elem` ["const", "volatile", "static", "extern", "register", "inline"] ->
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
    then do
      boundExpr <- optionalP expr
      needPunct "]"
      arraySuffixes (CArray ty (boundValue boundExpr))
    else pure ty

boundValue :: Maybe Expr -> Maybe Int
boundValue value = case value of
  Just (EInt text) -> Just (parseBoundInt text)
  _ -> Nothing

parseBoundInt :: String -> Int
parseBoundInt text = case text of
  '0':'x':xs -> readBoundHex xs
  '0':'X':xs -> readBoundHex xs
  _ -> read (stripBoundSuffix text)

stripBoundSuffix :: String -> String
stripBoundSuffix text = reverse (dropWhile isSuffix (reverse text)) where
  isSuffix c = c `elem` "uUlL"

readBoundHex :: String -> Int
readBoundHex = go 0 . stripBoundSuffix where
  go n xs = case xs of
    [] -> n
    c:rest -> go (n * 16 + hexDigit c) rest

hexDigit :: Char -> Int
hexDigit c
  | c >= '0' && c <= '9' = fromEnum c - fromEnum '0'
  | c >= 'a' && c <= 'f' = 10 + fromEnum c - fromEnum 'a'
  | c >= 'A' && c <= 'F' = 10 + fromEnum c - fromEnum 'A'
  | otherwise = 0

expr :: Parser Expr
expr = expression 0

assignExpr :: Parser Expr
assignExpr = expression 1

initializerExpr :: Parser Expr
initializerExpr = do
  braced <- eatPunct "{"
  if braced
    then skipBalanced "{" "}" >> pure (EInt "0")
    else assignExpr

expression :: Int -> Parser Expr
expression minPrec = do
  lhs <- postfix =<< unary
  climb lhs where
    climb lhs = do
      mtok <- peekMaybe
      case mtok of
        Just tok -> case tokenKind tok of
          TokPunct "?" | minPrec <= 2 -> do
            advanceToken
            yes <- expr
            needPunct ":"
            no <- expression 2
            climb (ECond lhs yes no)
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
  "," -> Just (0, LeftAssoc)
  "=" -> Just (1, RightAssoc)
  "+=" -> Just (1, RightAssoc)
  "-=" -> Just (1, RightAssoc)
  "*=" -> Just (1, RightAssoc)
  "/=" -> Just (1, RightAssoc)
  "%=" -> Just (1, RightAssoc)
  "<<=" -> Just (1, RightAssoc)
  ">>=" -> Just (1, RightAssoc)
  "&=" -> Just (1, RightAssoc)
  "^=" -> Just (1, RightAssoc)
  "|=" -> Just (1, RightAssoc)
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

unary :: Parser Expr
unary = do
  tok <- peek
  case tokenKind tok of
    TokPunct op | op `elem` ["++", "--"] ->
      advanceToken >> EUnary op <$> (postfix =<< unary)
    TokPunct op | op `elem` ["+", "-", "!", "~", "*", "&"] ->
      advanceToken >> EUnary op <$> (postfix =<< unary)
    TokIdent "sizeof" ->
      advanceToken >> parseSizeof
    TokInt s -> advanceToken >> pure (EInt s)
    TokChar s -> advanceToken >> pure (EChar s)
    TokString _ -> EString <$> stringLiteral
    TokIdent s -> advanceToken >> pure (EVar s)
    TokPunct "(" -> do
      advanceToken
      isCast <- nextStartsType
      if isCast
        then do
          ty <- typeName
          needPunct ")"
          ECast ty <$> (postfix =<< unary)
        else do
          e <- expr
          needPunct ")"
          pure e
    _ -> failAt tok "expected expression"

parseSizeof :: Parser Expr
parseSizeof = do
  paren <- eatPunct "("
  if paren
    then do
      isTy <- nextStartsType
      if isTy
        then do
          ty <- typeName
          needPunct ")"
          pure (ESizeofType ty)
        else do
          value <- expr
          needPunct ")"
          pure (ESizeofExpr value)
    else ESizeofExpr <$> (postfix =<< unary)

assignNode :: String -> Expr -> Expr -> Expr
assignNode op lhs rhs = case op of
  "=" -> EAssign lhs rhs
  "+=" -> EAssign lhs (EBinary "+" lhs rhs)
  "-=" -> EAssign lhs (EBinary "-" lhs rhs)
  "*=" -> EAssign lhs (EBinary "*" lhs rhs)
  "/=" -> EAssign lhs (EBinary "/" lhs rhs)
  "%=" -> EAssign lhs (EBinary "%" lhs rhs)
  "<<=" -> EAssign lhs (EBinary "<<" lhs rhs)
  ">>=" -> EAssign lhs (EBinary ">>" lhs rhs)
  "&=" -> EAssign lhs (EBinary "&" lhs rhs)
  "^=" -> EAssign lhs (EBinary "^" lhs rhs)
  "|=" -> EAssign lhs (EBinary "|" lhs rhs)
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
    Just (TokPunct ".") -> do
      advanceToken
      name <- needIdent
      postfix (EMember base name)
    Just (TokPunct "->") -> do
      advanceToken
      name <- needIdent
      postfix (EPtrMember base name)
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
      first <- assignExpr
      rest <- manyP (needPunct "," >> assignExpr)
      needPunct ")"
      pure (first:rest)

stringLiteral :: Parser String
stringLiteral = do
  first <- needString
  rest <- manyP needString
  pure (joinStrings (first:rest))

needString :: Parser String
needString = do
  tok <- peek
  case tokenKind tok of
    TokString s -> advanceToken >> pure s
    _ -> failAt tok "expected string literal"

joinStrings :: [String] -> String
joinStrings strings = "\"" ++ concatMap stringBody strings ++ "\""

stringBody :: String -> String
stringBody text = case text of
  '"':rest -> reverse (dropQuote (reverse rest))
  _ -> text
  where
    dropQuote xs = case xs of
      '"':ys -> ys
      _ -> xs

startsType :: Token -> Bool
startsType tok = case tokenKind tok of
  TokIdent name -> name `elem` (builtinTypeNames ++ ["const", "volatile", "static", "extern", "register", "inline", "typedef"])
  _ -> False

builtinTypeNames :: [String]
builtinTypeNames =
  [ "void", "int", "char", "signed", "unsigned", "short", "long", "float", "double"
  , "struct", "union", "enum", "FILE", "FUNCTION", "size_t"
  , "int8_t", "int16_t", "int32_t", "int64_t"
  , "uint8_t", "uint16_t", "uint32_t", "uint64_t"
  , "intptr_t", "uintptr_t", "ptrdiff_t", "size_t", "ssize_t", "time_t"
  , "va_list", "__builtin_va_list", "jmp_buf"
  ]

tokenStartsType :: Token -> Parser Bool
tokenStartsType tok = case tokenKind tok of
  TokIdent name | startsType tok -> pure True
                | otherwise -> isKnownTypeNameP name
  _ -> pure False

isKnownTypeNameP :: String -> Parser Bool
isKnownTypeNameP name = Parser $ \env toks -> Right (name `elem` env, toks)

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

skipUntilTopLevelSemi :: Parser ()
skipUntilTopLevelSemi = go 0 0 0 where
  go :: Int -> Int -> Int -> Parser ()
  go braces parens brackets = do
    tok <- peek
    case tokenKind tok of
      TokPunct ";" | braces == 0 && parens == 0 && brackets == 0 -> advanceToken
      TokPunct "{" -> advanceToken >> go (braces + 1) parens brackets
      TokPunct "}" -> advanceToken >> go (max 0 (braces - 1)) parens brackets
      TokPunct "(" -> advanceToken >> go braces (parens + 1) brackets
      TokPunct ")" -> advanceToken >> go braces (max 0 (parens - 1)) brackets
      TokPunct "[" -> advanceToken >> go braces parens (brackets + 1)
      TokPunct "]" -> advanceToken >> go braces parens (max 0 (brackets - 1))
      _ -> advanceToken >> go braces parens brackets

skipBalanced :: String -> String -> Parser ()
skipBalanced open close = go (1 :: Int) where
  go depth
    | depth <= 0 = pure ()
    | otherwise = do
        tok <- peek
        case tokenKind tok of
          TokPunct p | p == open -> advanceToken >> go (depth + 1)
          TokPunct p | p == close -> advanceToken >> go (depth - 1)
          _ -> advanceToken >> go depth

optionalP :: Parser a -> Parser (Maybe a)
optionalP p = Parser $ \env toks -> case runParser p env toks of
  Left _ -> Right (Nothing, toks)
  Right (x, rest) -> Right (Just x, rest)

ifM :: Parser Bool -> Parser a -> Parser a -> Parser a
ifM test yes no = do
  b <- test
  if b then yes else no

eatPunct :: String -> Parser Bool
eatPunct s = Parser $ \_env toks -> case toks of
  Token _ (TokPunct p):rest | p == s -> Right (True, rest)
  _ -> Right (False, toks)

needPunct :: String -> Parser ()
needPunct s = do
  ok <- eatPunct s
  if ok then pure () else peek >>= \tok -> failAt tok ("expected " ++ show s)

eatIdent :: String -> Parser Bool
eatIdent s = Parser $ \_env toks -> case toks of
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
peek = Parser $ \_env toks -> case toks of
  [] -> Left (ParseError (SrcPos 1 1) "unexpected end of input")
  tok:_ -> Right (tok, toks)

peekMaybe :: Parser (Maybe Token)
peekMaybe = Parser $ \_env toks -> Right (case toks of [] -> Nothing; tok:_ -> Just tok, toks)

peekSecondPunct :: String -> Parser Bool
peekSecondPunct punct = Parser $ \_env toks -> case toks of
  _:Token _ (TokPunct p):_ | p == punct -> Right (True, toks)
  _ -> Right (False, toks)

nextStartsType :: Parser Bool
nextStartsType = do
  mtok <- peekMaybe
  case mtok of
    Just tok -> tokenStartsType tok
    Nothing -> pure False

advanceToken :: Parser ()
advanceToken = Parser $ \_env toks -> case toks of
  [] -> Left (ParseError (SrcPos 1 1) "unexpected end of input")
  _:rest -> Right ((), rest)

failAt :: Token -> String -> Parser a
failAt tok msg = Parser $ \_env _ -> Left (parseErrorAt tok msg)

parseErrorAt :: Token -> String -> ParseError
parseErrorAt (Token (Span pos _) kind) msg = ParseError pos (msg ++ " near " ++ show (tokenText kind))

tokenKind :: Token -> TokenKind
tokenKind (Token _ kind) = kind

collectEnumConstants :: [Token] -> [(String, Int)]
collectEnumConstants toks = map toInt (reverse (go [] toks)) where
  toInt (name, value) = (name, fromInteger value)

  go env rest = case rest of
    [] -> env
    Token _ (TokIdent "enum"):xs ->
      let afterTag = skipOptionalEnumTag xs
      in case afterTag of
        Token _ (TokPunct "{"):body ->
          let (env', tailToks) = parseEnumBody env 0 body
          in go env' tailToks
        _ -> go env xs
    _:xs -> go env xs

skipOptionalEnumTag :: [Token] -> [Token]
skipOptionalEnumTag toks = case toks of
  Token _ (TokIdent _):rest -> rest
  _ -> toks

parseEnumBody :: [(String, Integer)] -> Integer -> [Token] -> ([(String, Integer)], [Token])
parseEnumBody env nextValue toks = case toks of
  [] -> (env, [])
  Token _ (TokPunct "}"):rest -> (env, rest)
  Token _ (TokPunct ","):rest -> parseEnumBody env nextValue rest
  Token _ (TokIdent name):rest ->
    let (value, afterValue) = enumValue env nextValue rest
        env' = (name, value) : removeEnumConstant name env
    in parseEnumBody env' (value + 1) afterValue
  Token _ (TokPunct "{"):rest ->
    parseEnumBody env nextValue (dropBalancedBrace 1 rest)
  _:rest ->
    parseEnumBody env nextValue rest

enumValue :: [(String, Integer)] -> Integer -> [Token] -> (Integer, [Token])
enumValue env nextValue toks = case toks of
  Token _ (TokPunct "="):rest ->
    let (exprToks, tailToks) = takeEnumValueExpr rest
    in case parseConstExpr env exprToks of
      Right (value, []) -> (value, tailToks)
      Right (value, trailing) | all ignorableEnumExprTail trailing -> (value, tailToks)
      _ -> (nextValue, tailToks)
  _ -> (nextValue, toks)

ignorableEnumExprTail :: Token -> Bool
ignorableEnumExprTail tok = case tokenKind tok of
  TokPunct ")" -> True
  _ -> False

takeEnumValueExpr :: [Token] -> ([Token], [Token])
takeEnumValueExpr = go 0 0 0 [] where
  go :: Int -> Int -> Int -> [Token] -> [Token] -> ([Token], [Token])
  go braces parens brackets acc toks = case toks of
    [] -> (reverse acc, [])
    tok:rest -> case tokenKind tok of
      TokPunct "," | braces == 0 && parens == 0 && brackets == 0 -> (reverse acc, toks)
      TokPunct "}" | braces == 0 && parens == 0 && brackets == 0 -> (reverse acc, toks)
      TokPunct "{" -> go (braces + 1) parens brackets (tok:acc) rest
      TokPunct "}" -> go (max 0 (braces - 1)) parens brackets (tok:acc) rest
      TokPunct "(" -> go braces (parens + 1) brackets (tok:acc) rest
      TokPunct ")" -> go braces (max 0 (parens - 1)) brackets (tok:acc) rest
      TokPunct "[" -> go braces parens (brackets + 1) (tok:acc) rest
      TokPunct "]" -> go braces parens (max 0 (brackets - 1)) (tok:acc) rest
      _ -> go braces parens brackets (tok:acc) rest

removeEnumConstant :: String -> [(String, Integer)] -> [(String, Integer)]
removeEnumConstant name constants = case constants of
  [] -> []
  (k, v):rest | k == name -> removeEnumConstant name rest
              | otherwise -> (k, v) : removeEnumConstant name rest

collectTypedefNames :: [Token] -> [String]
collectTypedefNames toks = unique (go toks) where
  go rest = case rest of
    [] -> []
    Token _ (TokIdent "typedef"):xs ->
      let (body, tailToks) = takeTypedefBody xs
      in typedefNames body ++ go tailToks
    _:xs -> go xs

takeTypedefBody :: [Token] -> ([Token], [Token])
takeTypedefBody = go 0 0 0 [] where
  go :: Int -> Int -> Int -> [Token] -> [Token] -> ([Token], [Token])
  go braces parens brackets acc toks = case toks of
    [] -> (reverse acc, [])
    tok:rest -> case tokenKind tok of
      TokPunct ";" | braces == 0 && parens == 0 && brackets == 0 -> (reverse acc, rest)
      TokPunct "{" -> go (braces + 1) parens brackets (tok:acc) rest
      TokPunct "}" -> go (max 0 (braces - 1)) parens brackets (tok:acc) rest
      TokPunct "(" -> go braces (parens + 1) brackets (tok:acc) rest
      TokPunct ")" -> go braces (max 0 (parens - 1)) brackets (tok:acc) rest
      TokPunct "[" -> go braces parens (brackets + 1) (tok:acc) rest
      TokPunct "]" -> go braces parens (max 0 (brackets - 1)) (tok:acc) rest
      _ -> go braces parens brackets (tok:acc) rest

typedefNames :: [Token] -> [String]
typedefNames toks = mapMaybe typedefName (splitTopLevelCommas (dropBraceBodies toks))

typedefName :: [Token] -> Maybe String
typedefName toks = case pointerDeclaratorName toks of
  Just name -> Just name
  Nothing -> lastIdentifier toks

pointerDeclaratorName :: [Token] -> Maybe String
pointerDeclaratorName toks = case toks of
  Token _ (TokPunct "("):Token _ (TokPunct "*"):Token _ (TokIdent name):Token _ (TokPunct ")"):_ ->
    Just name
  _:rest -> pointerDeclaratorName rest
  [] -> Nothing

lastIdentifier :: [Token] -> Maybe String
lastIdentifier toks = case reverse toks of
  [] -> Nothing
  Token _ (TokIdent name):_ | not (isCKeyword name) -> Just name
  _:rest -> lastIdentifier (reverse rest)

dropBraceBodies :: [Token] -> [Token]
dropBraceBodies toks = case toks of
  [] -> []
  Token _ (TokPunct "{"):rest -> dropBraceBodies (dropBalancedBrace 1 rest)
  tok:rest -> tok : dropBraceBodies rest

dropBalancedBrace :: Int -> [Token] -> [Token]
dropBalancedBrace depth toks
  | depth <= 0 = toks
  | otherwise = case toks of
      [] -> []
      tok:rest -> case tokenKind tok of
        TokPunct "{" -> dropBalancedBrace (depth + 1) rest
        TokPunct "}" -> dropBalancedBrace (depth - 1) rest
        _ -> dropBalancedBrace depth rest

splitTopLevelCommas :: [Token] -> [[Token]]
splitTopLevelCommas = go 0 0 [] [] where
  go :: Int -> Int -> [Token] -> [[Token]] -> [Token] -> [[Token]]
  go parens brackets current acc toks = case toks of
    [] -> reverse (reverse current : acc)
    tok:rest -> case tokenKind tok of
      TokPunct "," | parens == 0 && brackets == 0 ->
        go parens brackets [] (reverse current : acc) rest
      TokPunct "(" -> go (parens + 1) brackets (tok:current) acc rest
      TokPunct ")" -> go (max 0 (parens - 1)) brackets (tok:current) acc rest
      TokPunct "[" -> go parens (brackets + 1) (tok:current) acc rest
      TokPunct "]" -> go parens (max 0 (brackets - 1)) (tok:current) acc rest
      _ -> go parens brackets (tok:current) acc rest

unique :: [String] -> [String]
unique names = case names of
  [] -> []
  x:xs -> x : unique (filter (/= x) xs)

mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe f xs = case xs of
  [] -> []
  x:rest -> case f x of
    Just y -> y : mapMaybe f rest
    Nothing -> mapMaybe f rest

isCKeyword :: String -> Bool
isCKeyword name = name `elem`
  [ "void", "char", "short", "int", "long", "float", "double", "signed", "unsigned"
  , "struct", "union", "enum", "const", "volatile", "static", "extern", "register", "inline"
  , "auto", "typedef"
  ]
