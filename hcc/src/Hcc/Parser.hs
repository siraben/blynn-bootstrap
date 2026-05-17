module Parser
  ( ParseError(..)
  , parseProgram
  ) where

import Base
import ConstExpr
import Operators
import ParseLite
import ScopeMap
import SymbolTable
import TypesAst
import TypesToken

data ParseError = ParseError SrcPos String

data ParserEnv = ParserEnv (ScopeMap CType) [(String, Int)] (SymbolMap Int)

type Parser a = P ParserEnv Token ParseError a

initialParserEnv :: ParserEnv
initialParserEnv = ParserEnv (builtinTypeEnv builtinTypeAliases) [] symbolMapEmpty

builtinTypeEnv :: [(String, CType)] -> ScopeMap CType
builtinTypeEnv aliases = case aliases of
  [] -> scopeMapEmpty
  (name, ty):rest -> scopeMapInsert name ty (builtinTypeEnv rest)

builtinTypeAliases :: [(String, CType)]
builtinTypeAliases =
  [ ("FILE", CStruct "FILE")
  , ("FUNCTION", CLong)
  , ("size_t", CNamed "size_t")
  , ("ssize_t", CNamed "ssize_t")
  , ("time_t", CNamed "time_t")
  , ("ptrdiff_t", CNamed "ptrdiff_t")
  , ("intptr_t", CNamed "intptr_t")
  , ("uintptr_t", CNamed "uintptr_t")
  , ("int8_t", CNamed "int8_t")
  , ("int16_t", CNamed "int16_t")
  , ("int32_t", CNamed "int32_t")
  , ("int64_t", CNamed "int64_t")
  , ("uint8_t", CNamed "uint8_t")
  , ("uint16_t", CNamed "uint16_t")
  , ("uint32_t", CNamed "uint32_t")
  , ("uint64_t", CNamed "uint64_t")
  , ("va_list", CPtr CVoid)
  , ("__builtin_va_list", CPtr CVoid)
  , ("jmp_buf", CPtr CVoid)
  ]

lookupParserType :: String -> Parser (Maybe CType)
lookupParserType name = do
  env <- pEnv
  pure (case env of
    ParserEnv types _ _ -> scopeMapLookup name types)

bindParserType :: String -> CType -> Parser ()
bindParserType name ty = do
  env <- pEnv
  case env of
    ParserEnv types constants constantMap ->
      pSetEnv (ParserEnv (scopeMapInsert name ty types) constants constantMap)

lookupParserConstant :: String -> Parser (Maybe Int)
lookupParserConstant name = do
  env <- pEnv
  pure (case env of
    ParserEnv _ _ constantMap -> symbolMapLookup name constantMap)

bindParserConstant :: String -> Int -> Parser ()
bindParserConstant name value = do
  env <- pEnv
  case env of
    ParserEnv types constants constantMap ->
      pSetEnv (ParserEnv types ((name, value):constants) (symbolMapInsert name value constantMap))

parserConstants :: Parser [(String, Int)]
parserConstants = do
  env <- pEnv
  pure (case env of
    ParserEnv _ constants _ -> constants)

enterParserScope :: ParserEnv -> ParserEnv
enterParserScope env = case env of
  ParserEnv types constants constantMap -> ParserEnv (scopeMapEnter types) constants constantMap

leaveParserScope :: ParserEnv -> ParserEnv -> ParserEnv
leaveParserScope outer inner = case outer of
  ParserEnv _ outerConstants outerConstantMap -> case inner of
    ParserEnv innerTypes _ _ -> ParserEnv (scopeMapLeave innerTypes) outerConstants outerConstantMap

withParserScope :: Parser a -> Parser a
withParserScope = pLocalEnv enterParserScope leaveParserScope

parseProgram :: [Token] -> Either ParseError Program
parseProgram toks = case parseRestWithEnv program initialParserEnv toks of
  Left err -> Left err
  Right (Program decls, _env, []) -> Right (Program decls)
  Right (_, _, tok:_) -> Left (parseErrorAt tok "trailing tokens")

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
    then pure (TypeDecl [])
    else topDeclNonEmpty

topDeclNonEmpty :: Parser TopDecl
topDeclNonEmpty = do
  typedef <- eatIdent "typedef"
  if typedef
    then typedefDecl
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
    then pure (TypeDecl [ty0])
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
leadingExternQualifier = pRaw $ \env toks -> Unconsumed (Ok (go toks) env toks) where
  go ts = case ts of
    Token _ (TokIdent "extern"):_ -> True
    Token _ (TokIdent name):rest | name `elem` storageAndTypeQualifiers -> go rest
    _ -> False

typedefDecl :: Parser TopDecl
typedefDecl = do
  ty0 <- ctype
  first <- typedefItem ty0
  rest <- typedefItemsTail ty0
  mapM_ bindTypedef (first:rest)
  pure (TypeDecl (map typedefType (first:rest)))
  where
    typedefType item = case item of
      (_, ty) -> ty

typedefItem :: CType -> Parser (String, CType)
typedefItem ty0 = do
  (ty, name) <- declarator ty0
  ty' <- optionalFunctionSuffix ty
  skipAttributes
  pure (name, ty')

typedefItemsTail :: CType -> Parser [(String, CType)]
typedefItemsTail ty0 = do
  semi <- eatPunct ";"
  if semi
    then pure []
    else do
      needPunct ","
      item <- typedefItem ty0
      rest <- typedefItemsTail ty0
      pure (item:rest)

bindTypedef :: (String, CType) -> Parser ()
bindTypedef item = case item of
  ("", _) -> pure ()
  (name, ty) -> bindParserType name ty

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
      fnParams <- if fnTail then parameters else pure []
      let fnTy = if fnTail then functionSuffixType ty fnParams else CPtr ty
      ty' <- arraySuffixes fnTy
      pure (Field ty' name)
    else do
      ty <- pointerStars ty0
      name <- optionalIdent
      bitfield <- eatPunct ":"
      ty' <- if bitfield
        then assignExpr >> pure ty
        else arraySuffixes ty
      pure (Field ty' name)

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
parameterVoidOnly = pRaw $ \env toks -> case toks of
  Token _ (TokIdent "void"):Token _ (TokPunct ")"):rest -> Consumed (Ok True env rest)
  _ -> Unconsumed (Ok False env toks)

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
      fnParams <- if fnTail then parameters else pure []
      pure (if fnTail then functionSuffixType ty fnParams else CPtr ty, name)
    else do
      ty <- pointerStars ty0
      name <- optionalIdent
      fnTail <- eatPunct "("
      fnParams <- if fnTail then parameters else pure []
      let tyWithFunction = if fnTail then CPtr (CFunc ty (paramTypes fnParams)) else ty
      ty' <- arraySuffixes tyWithFunction
      pure (ty', name)

compound :: Parser [Stmt]
compound = needPunct "{" >> withParserScope (manyUntil (eatPunct "}") stmt)

stmt :: Parser Stmt
stmt = do
  tok <- peek
  tokIsType <- tokenStartsType tok
  case tokenKind tok of
    TokIdent "typedef" -> advanceToken >> typedefStmt
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

typedefStmt :: Parser Stmt
typedefStmt = typedefDecl >> pure STypedef

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
      TokIdent "_Bool" -> advanceToken >> pure CBool
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
        known <- lookupParserType name
        pure (case known of
          Just ty -> ty
          Nothing -> CNamed name)
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
    Just (TokIdent "int") -> advanceToken >> pure CShort
    _ -> pure CShort

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
    Just (TokIdent "int") -> advanceToken >> pure CUnsignedShort
    _ -> pure CUnsignedShort

unsignedLongTail :: Parser CType
unsignedLongTail = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "long") -> advanceToken >> optionalUnsignedLongLongInt
    Just (TokIdent "int") -> advanceToken >> pure CUnsignedLong
    _ -> pure CUnsignedLong

optionalUnsignedLongLongInt :: Parser CType
optionalUnsignedLongLongInt = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent "int") -> advanceToken >> pure CUnsignedLongLong
    _ -> pure CUnsignedLongLong

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
    Just (TokIdent "int") -> advanceToken >> pure CLongLong
    _ -> pure CLongLong

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
  if hasBody then parseEnumBody 0 else pure ()
  pure (CEnum name)

parseEnumBody :: Int -> Parser ()
parseEnumBody nextValue = do
  done <- eatPunct "}"
  if done
    then pure ()
    else do
      comma <- eatPunct ","
      if comma
        then parseEnumBody nextValue
        else do
          name <- needIdent
          value <- enumValue nextValue
          bindParserConstant name value
          after <- eatPunct ","
          if after
            then do
              end <- eatPunct "}"
              if end then pure () else parseEnumBody (value + 1)
            else do
              needPunct "}"

enumValue :: Int -> Parser Int
enumValue nextValue = do
  hasValue <- eatPunct "="
  if not hasValue
    then pure nextValue
    else do
      toks <- takeEnumValueExpr
      constants <- parserConstants
      case parseConstExpr constants toks of
        Right (value, []) -> pure value
        Right (value, trailing) ->
          if all ignorableEnumExprTail trailing
          then pure value
          else pure nextValue
        Left _ -> pure nextValue

takeEnumValueExpr :: Parser [Token]
takeEnumValueExpr = pRaw $ \env toks ->
  let result = takeEnumValueExprFrom 0 0 0 [] toks
  in case result of
    (exprToks, rest) -> Consumed (Ok exprToks env rest)

takeEnumValueExprFrom :: Int -> Int -> Int -> [Token] -> [Token] -> ([Token], [Token])
takeEnumValueExprFrom braces parens brackets acc toks = case toks of
  [] -> (reverse acc, [])
  tok:rest -> case tokenKind tok of
    TokPunct "," | braces == 0 && parens == 0 && brackets == 0 -> (reverse acc, toks)
    TokPunct "}" | braces == 0 && parens == 0 && brackets == 0 -> (reverse acc, toks)
    TokPunct "{" -> takeEnumValueExprFrom (braces + 1) parens brackets (tok:acc) rest
    TokPunct "}" -> takeEnumValueExprFrom (max 0 (braces - 1)) parens brackets (tok:acc) rest
    TokPunct "(" -> takeEnumValueExprFrom braces (parens + 1) brackets (tok:acc) rest
    TokPunct ")" -> takeEnumValueExprFrom braces (max 0 (parens - 1)) brackets (tok:acc) rest
    TokPunct "[" -> takeEnumValueExprFrom braces parens (brackets + 1) (tok:acc) rest
    TokPunct "]" -> takeEnumValueExprFrom braces parens (max 0 (brackets - 1)) (tok:acc) rest
    _ -> takeEnumValueExprFrom braces parens brackets (tok:acc) rest

ignorableEnumExprTail :: Token -> Bool
ignorableEnumExprTail tok = case tokenKind tok of
  TokPunct ")" -> True
  _ -> False

skipQualifiers :: Parser ()
skipQualifiers = do
  tok <- peekMaybe
  case fmap tokenKind tok of
    Just (TokIdent name) | name `elem` storageAndTypeQualifiers ->
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
    then do
      params <- parameters
      groupedDeclaratorSuffixes (functionSuffixType ty params)
    else arraySuffixes ty

functionSuffixType :: CType -> [Param] -> CType
functionSuffixType ty params = case ty of
  CPtr inner -> CPtr (CFunc inner (paramTypes params))
  _ -> CFunc ty (paramTypes params)

optionalFunctionSuffix :: CType -> Parser CType
optionalFunctionSuffix ty = do
  open <- eatPunct "("
  if open
    then do
      params <- parameters
      pure (CFunc ty (paramTypes params))
    else pure ty

paramTypes :: [Param] -> [CType]
paramTypes params = case params of
  [] -> []
  Param ty _:rest -> ty : paramTypes rest

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

binop :: String -> Maybe (Int, Assoc)
binop op = case op of
  ","   -> Just (0, LeftAssoc)
  "="   -> Just (1, RightAssoc)
  "+="  -> Just (1, RightAssoc)
  "-="  -> Just (1, RightAssoc)
  "*="  -> Just (1, RightAssoc)
  "/="  -> Just (1, RightAssoc)
  "%="  -> Just (1, RightAssoc)
  "<<=" -> Just (1, RightAssoc)
  ">>=" -> Just (1, RightAssoc)
  "&="  -> Just (1, RightAssoc)
  "^="  -> Just (1, RightAssoc)
  "|="  -> Just (1, RightAssoc)
  _     -> binopArith op

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
    TokFloat s -> advanceToken >> pure (EFloat s)
    TokChar s -> advanceToken >> pure (EChar s)
    TokString _ -> EString <$> stringLiteral
    TokIdent s -> do
      advanceToken
      constant <- lookupParserConstant s
      pure (case constant of
        Just value -> EInt (show value)
        Nothing -> EVar s)
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
        Ok ty env' rest | not (postfixContinues rest) -> Consumed (Ok (ESizeofType ty) env' rest)
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
  TokIdent name -> name `elem` (builtinTypeNames ++ storageAndTypeQualifiers ++ ["typedef"])
  _ -> False

builtinTypeNames :: [String]
builtinTypeNames =
  [ "void", "_Bool", "int", "char", "signed", "unsigned", "short", "long", "float", "double"
  , "struct", "union", "enum"
  ]

storageAndTypeQualifiers :: [String]
storageAndTypeQualifiers =
  ["const", "volatile", "static", "extern", "register", "inline", "auto"]

tokenStartsType :: Token -> Parser Bool
tokenStartsType tok = case tokenKind tok of
  TokIdent name | startsType tok -> pure True
                | otherwise -> isKnownTypeNameP name
  _ -> pure False

tokenStartsTypeInEnv :: ParserEnv -> Token -> Bool
tokenStartsTypeInEnv env tok = case tokenKind tok of
  TokIdent name -> startsType tok || parserEnvHasType name env
  _ -> False

identifierStartsDeclaration :: Parser Bool
identifierStartsDeclaration = pRaw $ \env toks -> Unconsumed (Ok (go env toks) env toks) where
  go env toks = case toks of
    Token _ (TokIdent name):rest
      | startsTypeName name -> True
      | parserEnvHasType name env -> typedefDeclaratorFollows rest
      | otherwise -> False
    _ -> False

  startsTypeName name =
    name `elem` (builtinTypeNames ++ storageAndTypeQualifiers ++ ["typedef"])

  typedefDeclaratorFollows toks = case dropLeadingQualifiers toks of
    Token _ (TokPunct "*"):_ -> True
    Token _ (TokIdent _):_ -> True
    _ -> False

  dropLeadingQualifiers toks = case toks of
    Token _ (TokIdent name):rest | name `elem` storageAndTypeQualifiers ->
      dropLeadingQualifiers rest
    _ -> toks

isKnownTypeNameP :: String -> Parser Bool
isKnownTypeNameP name = do
  known <- lookupParserType name
  pure (case known of
    Just _ -> True
    Nothing -> False)

parserEnvHasType :: String -> ParserEnv -> Bool
parserEnvHasType name env = case env of
  ParserEnv types _ _ -> case scopeMapLookup name types of
    Just _ -> True
    Nothing -> False

manyP :: Parser a -> Parser [a]
manyP = pMany

manyUntil :: Parser Bool -> Parser a -> Parser [a]
manyUntil = pManyUntil

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
eatPunct s = pRaw $ \env toks -> case toks of
  Token _ (TokPunct p):rest | p == s -> Consumed (Ok True env rest)
  _ -> Unconsumed (Ok False env toks)

needPunct :: String -> Parser ()
needPunct s = do
  ok <- eatPunct s
  if ok then pure () else peek >>= \tok -> failAt tok ("expected " ++ show s)

eatIdent :: String -> Parser Bool
eatIdent s = pRaw $ \env toks -> case toks of
  Token _ (TokIdent p):rest | p == s -> Consumed (Ok True env rest)
  _ -> Unconsumed (Ok False env toks)

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
peekSecondPunct punct = pRaw $ \env toks -> case toks of
  _:Token _ (TokPunct p):_ | p == punct -> Unconsumed (Ok True env toks)
  _ -> Unconsumed (Ok False env toks)

nextStartsType :: Parser Bool
nextStartsType = do
  mtok <- peekMaybe
  case mtok of
    Just tok -> tokenStartsType tok
    Nothing -> pure False

advanceToken :: Parser ()
advanceToken = pSkip unexpectedEof

failAt :: Token -> String -> Parser a
failAt tok msg = pFail (parseErrorAt tok msg)

unexpectedEof :: ParseError
unexpectedEof = ParseError (SrcPos 1 1) "unexpected end of input"

parseErrorAt :: Token -> String -> ParseError
parseErrorAt (Token (Span pos _) kind) msg = ParseError pos (msg ++ " near " ++ show (tokenText kind))

tokenKind :: Token -> TokenKind
tokenKind (Token _ kind) = kind
