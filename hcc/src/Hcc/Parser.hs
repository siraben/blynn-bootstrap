module Parser
  ( ParseError(..)
  , parseProgram
  ) where

import Base
import TypesAst
import ParseLite
import ParserScan
import SymbolTable
import TypesToken

data ParseError = ParseError SrcPos String

type Parser a = P SymbolSet Token ParseError a

parseProgram :: [Token] -> Either ParseError Program
parseProgram toks = case parseRest program (symbolSetFromList (builtinTypeNames ++ collectTypedefNames toks)) toks of
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
  emptyDecl <- eatPunct ";"
  if emptyDecl
    then pure TypeDecl
    else topDeclNonEmpty

topDeclNonEmpty :: Parser TopDecl
topDeclNonEmpty = do
  typedef <- eatIdent "typedef"
  if typedef
    then do
      structDecl <- optionalP (tryP typedefAggregateDecl)
      case structDecl of
        Just decl -> pure decl
        Nothing -> skipUntilTopLevelSemi >> pure TypeDecl
    else topDeclNoTypedef

topDeclNoTypedef :: Parser TopDecl
topDeclNoTypedef = do
  structDecl <- optionalP (tryP standaloneAggregateDecl)
  case structDecl of
    Just decl -> pure decl
    Nothing -> topDeclNoStruct

topDeclNoStruct :: Parser TopDecl
topDeclNoStruct = do
  isExtern <- leadingExternQualifier
  ty0 <- ctype
  standalone <- eatPunct ";"
  if standalone
    then pure TypeDecl
    else do
      (ty, name) <- declarator ty0
      ifM (eatPunct "(")
        (do
          params <- parameters
          skipAttributes
          isPrototype <- eatPunct ";"
          if isPrototype
            then pure (Prototype ty name params)
            else do
              body <- compound
              pure (Function ty name params body))
        (do
          initExpr <- optionalP (eatPunct "=" >> initializerExpr)
          rest <- declarationItemsTail ty0
          pure (globalDecl isExtern ((ty, name, initExpr):rest)))

globalDecl :: Bool -> [(CType, String, Maybe Expr)] -> TopDecl
globalDecl isExtern decls =
  if isExtern && all uninitialized decls
    then ExternGlobals (map externPair decls)
    else case decls of
      [(ty, name, initExpr)] -> Global ty name initExpr
      _ -> Globals decls
  where
    uninitialized (_, _, initExpr) = case initExpr of
      Nothing -> True
      Just _ -> False
    externPair (ty, name, _) = (ty, name)

leadingExternQualifier :: Parser Bool
leadingExternQualifier = pRaw $ \_env toks -> Unconsumed (Ok (go toks) toks) where
  go ts = case ts of
    Token _ (TokIdent "extern"):_ -> True
    Token _ (TokIdent name):rest | name `elem` ["const", "volatile", "static", "register", "inline"] -> go rest
    _ -> False

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
parameterVoidOnly = pRaw $ \_env toks -> case toks of
  Token _ (TokIdent "void"):Token _ (TokPunct ")"):rest -> Consumed (Ok True rest)
  _ -> Unconsumed (Ok False toks)

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
    TokIdent name -> do
      isLabel <- peekSecondPunct ":"
      if isLabel
        then advanceToken >> needPunct ":" >> pure (SLabel name)
        else do
          startsDecl <- identifierStartsDeclaration
          if startsDecl then parseDeclStmt else parseExprStmt
    _ | tokIsType -> parseDeclStmt
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
    _ -> do
      first <- stmt
      case first of
        SLabel _ -> do
          body <- stmt
          pure [first, body]
        _ -> pure [first]

parseDeclStmt :: Parser Stmt
parseDeclStmt = do
  ty0 <- ctype
  standalone <- eatPunct ";"
  if standalone
    then pure (SExpr (EInt "0"))
    else do
      prototype <- optionalP (tryP (localPrototype ty0))
      case prototype of
        Just _ -> pure (SExpr (EInt "0"))
        Nothing -> do
          first <- declarationItem ty0
          rest <- declarationItemsTail ty0
          pure (declStmt (first:rest))

localPrototype :: CType -> Parser ()
localPrototype ty0 = do
  _ty <- pointerStars ty0
  _name <- needIdent
  needPunct "("
  skipBalanced "(" ")"
  skipAttributes
  needPunct ";"

declStmt :: [(CType, String, Maybe Expr)] -> Stmt
declStmt decls = case decls of
  [(ty, name, initExpr)] -> SDecl ty name initExpr
  _ -> SDecls decls

declarationItem :: CType -> Parser (CType, String, Maybe Expr)
declarationItem ty0 = do
  (ty, name) <- declarator ty0
  skipAttributes
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
      TokIdent "short" -> advanceToken >> optionalShortInt
      TokIdent "long" -> advanceToken >> longBaseType
      TokIdent "float" -> advanceToken >> pure CFloat
      TokIdent "double" -> advanceToken >> pure CDouble
      TokIdent "struct" -> aggregateType CStruct CStructNamed CStructDef
      TokIdent "union" -> aggregateType CUnion CUnionNamed CUnionDef
      TokIdent "enum" -> enumType
      TokIdent name -> do
        advanceToken
        pure (CNamed name)
      _ -> failAt tok "expected type"

typeName :: Parser CType
typeName = ctype >>= pointerStars

signedBaseType :: Parser CType
signedBaseType = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "char") -> advanceToken >> pure CChar
    Just (TokIdent "short") -> advanceToken >> optionalShortInt
    Just (TokIdent "int") -> advanceToken >> pure CInt
    _ -> pure CInt

optionalShortInt :: Parser CType
optionalShortInt = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "int") -> advanceToken >> pure (CNamed "signed_short")
    _ -> pure (CNamed "signed_short")

unsignedBaseType :: Parser CType
unsignedBaseType = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "char") -> advanceToken >> pure CUnsignedChar
    Just (TokIdent "short") -> advanceToken >> optionalUnsignedShortInt
    Just (TokIdent "long") -> advanceToken >> unsignedLongTail
    Just (TokIdent "int") -> advanceToken >> pure CUnsigned
    _ -> pure CUnsigned

optionalUnsignedShortInt :: Parser CType
optionalUnsignedShortInt = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "int") -> advanceToken >> pure (CNamed "unsigned_short")
    _ -> pure (CNamed "unsigned_short")

unsignedLongTail :: Parser CType
unsignedLongTail = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "long") -> advanceToken >> optionalUnsignedLongInt
    Just (TokIdent "int") -> advanceToken >> pure (CNamed "unsigned_long")
    _ -> pure (CNamed "unsigned_long")

optionalUnsignedLongInt :: Parser CType
optionalUnsignedLongInt = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "int") -> advanceToken >> pure (CNamed "unsigned_long")
    _ -> pure (CNamed "unsigned_long")

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
    Just (TokIdent name) | name `elem` ["__attribute__", "__extension__"] ->
      skipAttributes >> skipQualifiers
    _ -> pure ()

skipAttributes :: Parser ()
skipAttributes = do
  tok <- peekMaybe
  case fmap tokenKind tok of
    Just (TokIdent "__attribute__") -> do
      advanceToken
      skipOptionalBalancedParens
      skipAttributes
    Just (TokIdent "__extension__") ->
      advanceToken >> skipAttributes
    _ -> pure ()

skipOptionalBalancedParens :: Parser ()
skipOptionalBalancedParens = do
  open <- eatPunct "("
  if open then skipBalanced "(" ")" else pure ()

declarator :: CType -> Parser (CType, String)
declarator ty0 = do
  ty <- pointerStars ty0
  directDeclarator ty

directDeclarator :: CType -> Parser (CType, String)
directDeclarator ty = do
  grouped <- eatPunct "("
  if grouped
    then do
      (innerTy, name) <- declarator ty
      needPunct ")"
      ty' <- groupedDeclaratorSuffixes innerTy
      skipAttributes
      pure (ty', name)
    else do
      name <- needIdent
      ty' <- arraySuffixes ty
      skipAttributes
      pure (ty', name)

groupedDeclaratorSuffixes :: CType -> Parser CType
groupedDeclaratorSuffixes ty = do
  open <- eatPunct "("
  if open
    then skipBalanced "(" ")" >> groupedDeclaratorSuffixes ty
    else arraySuffixes ty

pointerStars :: CType -> Parser CType
pointerStars ty = do
  star <- eatPunct "*"
  if star
    then skipQualifiers >> pointerStars (CPtr ty)
    else pure ty

arraySuffixes :: CType -> Parser CType
arraySuffixes ty = do
  open <- eatPunct "["
  if open
    then do
      boundExpr <- optionalP expr
      needPunct "]"
      arraySuffixes (CArray ty boundExpr)
    else pure ty

expr :: Parser Expr
expr = expression 0

assignExpr :: Parser Expr
assignExpr = expression 1

initializerExpr :: Parser Expr
initializerExpr = do
  braced <- eatPunct "{"
  if braced
    then EInitList <$> initializerList
    else assignExpr

initializerList :: Parser [Expr]
initializerList = do
  done <- eatPunct "}"
  if done
    then pure []
    else do
      value <- initializerExpr
      comma <- eatPunct ","
      if comma
        then do
          end <- eatPunct "}"
          if end
            then pure [value]
            else do
              rest <- initializerList
              pure (value:rest)
        else do
          needPunct "}"
          pure [value]

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
            rhs <- expression (if rightAssoc assoc then prec else prec + 1)
            let node = assignNode op lhs rhs
            climb node
          _ -> pure lhs
        Nothing -> pure lhs

data Assoc = LeftAssoc | RightAssoc

rightAssoc :: Assoc -> Bool
rightAssoc assoc = case assoc of
  RightAssoc -> True
  LeftAssoc -> False

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
    then sizeofParen
    else ESizeofExpr <$> (postfix =<< unary)

sizeofParen :: Parser Expr
sizeofParen = pRaw $ \env toks ->
  case toks of
    tok:_ | tokenStartsTypeInEnv env tok ->
      case forceConsumed (runP (typeName <* needPunct ")") env toks) of
        Ok ty rest | not (postfixContinues rest) -> Consumed (Ok (ESizeofType ty) rest)
        _ -> runP sizeofParenExpr env toks
    _ -> runP sizeofParenExpr env toks

sizeofParenExpr :: Parser Expr
sizeofParenExpr = do
  value <- expr
  needPunct ")"
  ESizeofExpr <$> postfix value

postfixContinues :: [Token] -> Bool
postfixContinues toks = case toks of
  Token _ (TokPunct p):_ -> p `elem` ["(", "[", ".", "->", "++", "--"]
  _ -> False

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

tokenStartsTypeInEnv :: SymbolSet -> Token -> Bool
tokenStartsTypeInEnv env tok = case tokenKind tok of
  TokIdent name -> startsType tok || symbolSetMember name env
  _ -> False

identifierStartsDeclaration :: Parser Bool
identifierStartsDeclaration = pRaw $ \env toks -> Unconsumed (Ok (go env toks) toks) where
  go env toks = case toks of
    Token _ (TokIdent name):rest
      | startsTypeName name -> True
      | symbolSetMember name env -> typedefDeclaratorFollows rest
      | otherwise -> False
    _ -> False

  startsTypeName name =
    name `elem` (builtinTypeNames ++ ["const", "volatile", "static", "extern", "register", "inline", "typedef"])

  typedefDeclaratorFollows toks = case dropLeadingQualifiers toks of
    Token _ (TokPunct "*"):_ -> True
    Token _ (TokIdent _):_ -> True
    _ -> False

  dropLeadingQualifiers toks = case toks of
    Token _ (TokIdent name):rest | name `elem` ["const", "volatile", "static", "extern", "register", "inline"] ->
      dropLeadingQualifiers rest
    _ -> toks

isKnownTypeNameP :: String -> Parser Bool
isKnownTypeNameP name = do
  env <- pEnv
  pure (symbolSetMember name env)

manyP :: Parser a -> Parser [a]
manyP = pMany

manyUntil :: Parser Bool -> Parser a -> Parser [a]
manyUntil = pManyUntil

skipUntilTopLevelSemi :: Parser ()
skipUntilTopLevelSemi = go (0 :: Int) (0 :: Int) (0 :: Int) where
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
optionalP = pOptional

tryP :: Parser a -> Parser a
tryP = pTry

ifM :: Parser Bool -> Parser a -> Parser a -> Parser a
ifM test yes no = do
  b <- test
  if b then yes else no

eatPunct :: String -> Parser Bool
eatPunct s = pRaw $ \_env toks -> case toks of
  Token _ (TokPunct p):rest | p == s -> Consumed (Ok True rest)
  _ -> Unconsumed (Ok False toks)

needPunct :: String -> Parser ()
needPunct s = do
  ok <- eatPunct s
  if ok then pure () else peek >>= \tok -> failAt tok ("expected " ++ show s)

eatIdent :: String -> Parser Bool
eatIdent s = pRaw $ \_env toks -> case toks of
  Token _ (TokIdent p):rest | p == s -> Consumed (Ok True rest)
  _ -> Unconsumed (Ok False toks)

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
peek = do
  mtok <- peekMaybe
  case mtok of
    Nothing -> pFail unexpectedEof
    Just tok -> pure tok

peekMaybe :: Parser (Maybe Token)
peekMaybe = pPeekMaybe

peekSecondPunct :: String -> Parser Bool
peekSecondPunct punct = pRaw $ \_env toks -> case toks of
  _:Token _ (TokPunct p):_ | p == punct -> Unconsumed (Ok True toks)
  _ -> Unconsumed (Ok False toks)

nextStartsType :: Parser Bool
nextStartsType = do
  mtok <- peekMaybe
  case mtok of
    Just tok -> tokenStartsType tok
    Nothing -> pure False

advanceToken :: Parser ()
advanceToken = pTake unexpectedEof >> pure ()

failAt :: Token -> String -> Parser a
failAt tok msg = pFail (parseErrorAt tok msg)

unexpectedEof :: ParseError
unexpectedEof = ParseError (SrcPos 1 1) "unexpected end of input"

parseErrorAt :: Token -> String -> ParseError
parseErrorAt (Token (Span pos _) kind) msg = ParseError pos (msg ++ " near " ++ show (tokenText kind))

tokenKind :: Token -> TokenKind
tokenKind (Token _ kind) = kind
