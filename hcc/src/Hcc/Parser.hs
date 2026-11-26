module Parser
  ( ParseError(..)
  , parseProgram
  , parseProgramTarget
  ) where

import Base
import BootstrapTypes
import ConstExpr
import Literal
import Operators
import ParseLite
import ScopeMap
import SymbolTable
import TypesAst
import TypesToken

data ParseError = ParseError SrcPos String

-- Typedefs, enumerators, objects and functions share C's ordinary namespace.
-- Tags and members are deliberately not entered here.
data ParserBinding = ParserType CType | ParserConstant Constant | ParserOrdinary

data ParserEnv = ParserEnv
  { parserBindings :: ScopeMap ParserBinding
  , visibleConstants :: [(String, Constant)]
  , parserBits :: Int
  , parserTags :: ScopeMap (Bool, String)
  , parserScopeDepth :: Int
  , parserNextTag :: Int
  }

type Parser a = P ParserEnv Token ParseError a

initialParserEnv :: Int -> ParserEnv
initialParserEnv bits = ParserEnv (builtinTypeEnv builtinTypeAliases) [] bits scopeMapEmpty 0 0

builtinTypeEnv :: [(String, CType)] -> ScopeMap ParserBinding
builtinTypeEnv aliases = case aliases of
  [] -> scopeMapEmpty
  (name, ty):rest -> scopeMapInsert name (ParserType ty) (builtinTypeEnv rest)

lookupParserType :: String -> Parser (Maybe CType)
lookupParserType name = do
  parserEnvType name <$> pEnv

bindParserType :: String -> CType -> Parser ()
bindParserType name ty = bindParserName name (ParserType ty)

bindParserOrdinary :: String -> Parser ()
bindParserOrdinary name = bindParserName name ParserOrdinary

bindParserName :: String -> ParserBinding -> Parser ()
bindParserName name binding = when (name /= "") (do
  env <- pEnv
  let bindings = parserBindings env
  let constants = visibleConstants env
  let remaining = case scopeMapLookup name bindings of
        Just (ParserConstant _) -> filter (\(key, _) -> key /= name) constants
        _ -> constants
  let constants' = case binding of
        ParserConstant value -> (name, value):remaining
        _ -> remaining
  pSetEnv (env { parserBindings = scopeMapInsert name binding bindings, visibleConstants = constants' }))

lookupParserConstant :: String -> Parser (Maybe Constant)
lookupParserConstant name = do
  env <- pEnv
  pure (case scopeMapLookup name (parserBindings env) of
    Just (ParserConstant value) -> Just value
    _ -> Nothing)

bindParserConstant :: String -> Constant -> Parser ()
bindParserConstant name value = bindParserName name (ParserConstant value)

parserConstants :: Parser [(String, Constant)]
parserConstants = visibleConstants <$> pEnv

parserTargetBits :: Parser Int
parserTargetBits = parserBits <$> pEnv

enterParserScope :: ParserEnv -> ParserEnv
enterParserScope env = env
  { parserBindings = scopeMapEnter (parserBindings env)
  , parserTags = scopeMapEnter (parserTags env)
  , parserScopeDepth = parserScopeDepth env + 1
  }

keepTagCounter :: ParserEnv -> ParserEnv -> ParserEnv
keepTagCounter env inner = env { parserNextTag = parserNextTag inner }

withParserScope :: Parser a -> Parser a
withParserScope = pLocalEnv enterParserScope keepTagCounter

manyP :: Parser a -> Parser [a]
manyP = pMany

manyUntil :: Parser Bool -> Parser a -> Parser [a]
manyUntil = pManyUntil

optionalP :: Parser a -> Parser (Maybe a)
optionalP = pOptional

parseProgram :: [Token] -> Either ParseError Program
parseProgram = parseProgramTarget 64

parseProgramTarget :: Int -> [Token] -> Either ParseError Program
parseProgramTarget bits toks = case parseRestWithEnv program (initialParserEnv bits) toks of
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
    else do
      staticAssert <- eatIdent "_Static_assert"
      if staticAssert
        then parseStaticAssert
        else topDeclNonEmpty

parseStaticAssert :: Parser TopDecl
parseStaticAssert = do
  needPunct "("
  toks <- pRaw $ \env tokens -> case takeStaticAssertExpr 0 [] tokens of
    Just (taken, rest) -> Consumed (Ok taken env rest)
    Nothing -> Unconsumed (Ok [] env tokens)
  constants <- parserConstants
  bits <- parserTargetBits
  case parseTypedConstExprTarget bits constants toks of
    Right (value, []) ->
      if not (constantTrue value)
        then peek >>= \tok -> failAt tok "_Static_assert failed"
        else do
          skipOptionalStaticAssertMessage
          needPunct ")"
          needPunct ";"
          pure (TypeDecl [])
    Right (_, tok:_) -> failAt tok "unexpected tokens in _Static_assert expression"
    Left msg -> peek >>= \tok -> failAt tok ("invalid _Static_assert expression: " ++ msg)

takeStaticAssertExpr :: Int -> [Token] -> [Token] -> Maybe ([Token], [Token])
takeStaticAssertExpr depth acc toks = case toks of
  [] -> Nothing
  tok:rest -> case tokenKind tok of
    TokPunct "(" -> takeStaticAssertExpr (depth + 1) (tok:acc) rest
    TokPunct ")" | depth == 0 -> Just (reverse acc, toks)
    TokPunct ")" -> takeStaticAssertExpr (depth - 1) (tok:acc) rest
    TokPunct "," | depth == 0 -> Just (reverse acc, toks)
    _ -> takeStaticAssertExpr depth (tok:acc) rest

skipOptionalStaticAssertMessage :: Parser ()
skipOptionalStaticAssertMessage = do
  hasComma <- eatPunct ","
  when hasComma
    (do
      tok <- peek
      case tokenKind tok of
        TokString _ -> advanceToken
        _ -> failAt tok "expected string literal in _Static_assert")

topDeclNonEmpty :: Parser TopDecl
topDeclNonEmpty = do
  typedef <- eatIdent "typedef"
  if typedef
    then typedefDecl
    else topDeclNoTypedef

topDeclNoTypedef :: Parser TopDecl
topDeclNoTypedef = do
  externBefore <- leadingStorageClass "extern"
  (after, ty0) <- ctypeTrailing
  let isExtern = externBefore || "extern" `elem` after
  standalone <- eatPunct ";"
  if standalone
    then pure (TypeDecl [ty0])
    else do
      (layers, name) <- declaratorLayers RequiredName False
      case layers of
        FunctionLayer params scope:rest -> do
          let retTy = applyLayers rest ty0
          let params' = adjustParameters params
          isPrototype <- eatPunct ";"
          decl <- if isPrototype
            then pure (Prototype retTy name params')
            else pLocalEnv (keepTagCounter scope) keepTagCounter (do
              mapM_ checkDefinitionParameter params
              Function retTy name params' <$> compound)
          bindParserOrdinary name
          pure decl
        _ -> do
          bindParserOrdinary name
          initExpr <- optionalP (eatPunct "=" >> initializerExpr)
          rest <- declarationItemsTail ty0
          pure (globalDecl isExtern ((applyLayers layers ty0, name, initExpr):rest))

globalDecl :: Bool -> [(CType, String, Maybe Expr)] -> TopDecl
globalDecl isExtern decls =
  if isExtern && all uninitialized decls
    then ExternGlobals (map externPair decls)
    else Globals decls
  where

uninitialized :: (CType, String, Maybe Expr) -> Bool
uninitialized (_, _, initExpr) = case initExpr of
  Nothing -> True
  Just _ -> False

externPair :: (CType, String, Maybe Expr) -> (CType, String)
externPair (ty, name, _) = (ty, name)

leadingStorageClass :: String -> Parser Bool
leadingStorageClass keyword = pRaw $ \env toks -> Unconsumed (Ok (go toks) env toks) where
  go ts = case ts of
    Token _ (TokIdent name):rest
      | name == keyword -> True
      | name `elem` storageAndTypeQualifiers -> go rest
    _ -> False

typedefDecl :: Parser TopDecl
typedefDecl = TypeDecl <$> typedefTypes

typedefTypes :: Parser [CType]
typedefTypes = do
  ty0 <- ctype
  first <- typedefItem ty0
  rest <- typedefItemsTail ty0
  pure (map typedefType (first:rest))
  where
    typedefType item = case item of
      (_, ty) -> ty

typedefItem :: CType -> Parser (String, CType)
typedefItem ty0 = do
  (ty, name) <- declarator ty0
  bindTypedef (name, ty)
  pure (name, ty)

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
  (layers, name) <- declaratorLayers OptionalName False
  bitfield <- eatPunct ":"
  when bitfield (assignExpr >> pure ())
  pure (Field (applyLayers layers ty0) name)

-- A definition keeps this scope through its body; other function declarators
-- discard prototype-scope names at the end of the parameter list.
parametersInScope :: Parser [Param]
parametersInScope = do
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
  bindParserOrdinary name
  pure (Param ty name)

parameterDeclarator :: CType -> Parser (CType, String)
parameterDeclarator ty0 = do
  (layers, name) <- declaratorLayers OptionalName True
  pure (applyLayers layers ty0, name)

skipParameterArrayQualifiers :: Parser ()
skipParameterArrayQualifiers = do
  mtok <- peekMaybe
  case fmap tokenKind mtok of
    Just (TokIdent name) | name `elem` ["const", "volatile", "restrict"] ->
      advanceToken >> skipParameterArrayQualifiers
    _ -> pure ()

-- Keep bounds until we know whether this is a prototype or definition. Only
-- the outermost array is adjusted; inner dimensions remain the pointed-to type.
adjustParameters :: [Param] -> [Param]
adjustParameters = map (\(Param ty name) -> Param (adjustParameterType ty) name)

adjustParameterType :: CType -> CType
adjustParameterType ty = case ty of
  CArray inner _ -> CPtr inner
  CFunc _ _ -> CPtr ty
  _ -> ty

-- Dropping a prototype bound is harmless. A definition would have to execute
-- side effects in a bound on entry; this parser/AST cannot represent that yet.
checkDefinitionParameter :: Param -> Parser ()
checkDefinitionParameter (Param ty _name) = checkBounds ty where
  checkBounds arrayTy = case arrayTy of
    CArray inner bound -> do
      case bound of
        Just value | not (simpleParameterBound value) ->
          peek >>= \tok -> failAt tok "side-effecting or complex array parameter bounds are not supported in definitions"
        _ -> pure ()
      checkBounds inner
    _ -> pure ()

simpleParameterBound :: Expr -> Bool
simpleParameterBound value = case value of
  EInt _ -> True
  EFloat _ -> True
  EChar _ -> True
  EVar _ -> True
  ESizeofType _ -> True
  ESizeofExpr _ -> True
  ECast _ e -> simpleParameterBound e
  EUnary op e -> op `elem` ["+", "-", "!", "~"] && simpleParameterBound e
  EBinary _ a b -> simpleParameterBound a && simpleParameterBound b
  ECond a b c -> simpleParameterBound a && simpleParameterBound b && simpleParameterBound c
  _ -> False

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
typedefStmt = STypeDecl <$> typedefTypes

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
parseIf = withParserScope (do
  needPunct "("
  cond <- expr
  needPunct ")"
  yes <- stmtAsBlock
  hasElse <- eatIdent "else"
  no <- if hasElse then stmtAsBlock else pure []
  pure (SIf cond yes no))

parseWhile :: Parser Stmt
parseWhile = withParserScope (do
  needPunct "("
  cond <- expr
  needPunct ")"
  SWhile cond <$> stmtAsBlock)

parseDoWhile :: Parser Stmt
parseDoWhile = withParserScope (do
  body <- stmtAsBlock
  needIdentValue "while"
  needPunct "("
  cond <- expr
  needPunct ")"
  needPunct ";"
  pure (SDoWhile body cond))

parseFor :: Parser Stmt
parseFor = withParserScope (do
  needPunct "("
  initClause <- forInit
  cond <- optionalExprUntil ";"
  stepExpr <- optionalExprUntil ")"
  body <- stmtAsBlock
  pure (SFor initClause cond stepExpr body))

forInit :: Parser ForInit
forInit = do
  done <- eatPunct ";"
  if done
    then pure ForNoInit
    else do
      tok <- peek
      startsDecl <- tokenStartsType tok
      if startsDecl
        then do
          ty0 <- ctype
          first <- declarationItem ty0
          rest <- declarationItemsTail ty0
          pure (ForDecls (first:rest))
        else do
          initExpr <- expr
          needPunct ";"
          pure (ForExpr initExpr)

parseSwitch :: Parser Stmt
parseSwitch = withParserScope (do
  needPunct "("
  value <- expr
  needPunct ")"
  SSwitch value <$> stmtAsBlock)

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
stmtAsBlock = withParserScope (do
  tok <- peek
  case tokenKind tok of
    TokPunct "{" -> (:[]) . SBlock <$> compound
    _ -> labelledStatement)

labelledStatement :: Parser [Stmt]
labelledStatement = do
  first <- stmt
  case first of
    SLabel _ -> (first:) <$> labelledStatement
    SCase _ -> (first:) <$> labelledStatement
    SDefault -> (first:) <$> labelledStatement
    _ -> pure [first]

parseDeclStmt :: Parser Stmt
parseDeclStmt = do
  start <- peek
  staticBefore <- leadingStorageClass "static"
  externBefore <- leadingStorageClass "extern"
  (after, ty0) <- ctypeTrailing
  let isStatic = staticBefore || "static" `elem` after
  let isExtern = externBefore || "extern" `elem` after
  standalone <- eatPunct ";"
  if standalone
    then pure (STypeDecl [ty0])
    else do
      (ty, name) <- declarator ty0
      case ty of
        CFunc _ _ -> do
          bindParserOrdinary name
          needPunct ";"
          pure (SPrototype ty name)
        _ -> do
          first <- declarationInitializer ty name
          rest <- declarationItemsTail ty0
          let decls = first:rest
          if isStatic
            then pure (SStaticDecls decls)
            else if not isExtern
              then pure (declStmt decls)
              else if all uninitialized decls
                then pure (SExternDecls (map externPair decls))
                else failAt start "a block-scope extern declaration has an initializer"

declStmt :: [(CType, String, Maybe Expr)] -> Stmt
declStmt = SDecls

declarationItem :: CType -> Parser (CType, String, Maybe Expr)
declarationItem ty0 = do
  (ty, name) <- declarator ty0
  declarationInitializer ty name

declarationInitializer :: CType -> String -> Parser (CType, String, Maybe Expr)
declarationInitializer ty name = do
  bindParserOrdinary name
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
ctype = snd <$> ctypeTrailing

ctypeTrailing :: Parser ([String], CType)
ctypeTrailing = do
  skipQualifiers
  ty <- baseType
  after <- qualifierNames
  pure (after, ty)
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
      TokIdent "struct" -> aggregateType False CStruct CStructNamed CStructDef
      TokIdent "union" -> aggregateType True CUnion CUnionNamed CUnionDef
      TokIdent "enum" -> enumType
      TokIdent name -> do
        advanceToken
        known <- lookupParserType name
        pure (case known of
          Just ty -> ty
          Nothing -> CNamed name)
      _ -> failAt tok "expected type"

typeName :: Parser CType
typeName = do
  ty <- ctype
  (layers, _) <- declaratorLayers NoName False
  pure (applyLayers layers ty)

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

aggregateType :: Bool -> (String -> CType) -> (String -> [Field] -> CType) -> ([Field] -> CType) -> Parser CType
aggregateType isUnion mkType mkNamed mkInline = do
  tok <- peek
  advanceToken
  name <- optionalIdent
  hasBody <- eatPunct "{"
  forward <- fmap tokenKind <$> peekMaybe
  let declaresHere = hasBody || case forward of
        Just (TokPunct ";") -> True
        _ -> False
  key <- if name == "" then pure name else resolveAggregateTag tok declaresHere isUnion name
  if hasBody
    then do
      fields <- aggregateBodyAfterOpen
      pure (if name == "" then mkInline fields else mkNamed key fields)
    else pure (mkType key)

-- Lowering and its layout caches see the declaration identity, not the
-- spelling. Keep file-scope keys compatible with bootstrap FILE aliases.
resolveAggregateTag :: Token -> Bool -> Bool -> String -> Parser String
resolveAggregateTag tok declaresHere isUnion name = do
  env <- pEnv
  let tags = parserTags env
  let existing = if declaresHere then scopeMapLookupCurrent name tags else scopeMapLookup name tags
  case existing of
    Just (kind, key) -> if kind == isUnion then pure key else failAt tok ("tag kind mismatch: " ++ name)
    Nothing -> do
      let counter = parserNextTag env
      let key = if parserScopeDepth env == 0 then name else name ++ "#" ++ show counter
      pSetEnv (env { parserTags = scopeMapInsert name (isUnion, key) tags, parserNextTag = counter + 1 })
      pure key

aggregateBodyAfterOpen :: Parser [Field]
aggregateBodyAfterOpen = concat <$> manyUntil (eatPunct "}") fieldDecl

enumType :: Parser CType
enumType = do
  advanceToken
  name <- optionalIdent
  hasBody <- eatPunct "{"
  when hasBody (parseEnumBody (Just (constantInt 4 0)))
  pure (CEnum name)

parseEnumBody :: Maybe Constant -> Parser ()
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
              if end then pure () else parseEnumBody (nextParserConstant value)
            else do
              needPunct "}"

-- Values representable in int are int enumerators, even with a U/LL
-- initializer. Retain wider typed values only for the bootstrap extension
-- (notably TinyCC's UINT32_MAX and UINT64_MAX DWARF enumerators).
normalizeParserConstant :: Constant -> Constant
normalizeParserConstant value = case constantToIntChecked value of
  Just n -> constantInt 4 n
  Nothing -> value

nextParserConstant :: Constant -> Maybe Constant
nextParserConstant value@(Constant _ unsigned _) =
  let wide = constantConvert 8 unsigned value
  in case constantBinary "+" wide (constantInt 8 1) of
    Right next -> case constantBinary ">" next wide of
      Right greater -> if constantTrue greater then Just (normalizeParserConstant next) else Nothing
      Left _ -> Nothing
    Left _ -> Nothing

enumValue :: Maybe Constant -> Parser Constant
enumValue nextValue = do
  hasValue <- eatPunct "="
  if not hasValue
    then case nextValue of
      Just value -> pure value
      Nothing -> peek >>= \tok -> failAt tok "enum value exceeds supported 64-bit range"
    else do
      toks <- takeEnumValueExpr
      constants <- parserConstants
      bits <- parserTargetBits
      case parseTypedConstExprTarget bits constants toks of
        Right (value, trailing) | all ignorableEnumExprTail trailing -> pure (normalizeParserConstant value)
        Right (_, tok:_) ->
          failAt tok ("unexpected tokens in enum initializer: " ++ tokenText (tokenKind tok))
        Right (_, []) ->
          peek >>= \tok -> failAt tok "unexpected tokens in enum initializer"
        Left msg ->
          peek >>= \tok -> failAt tok ("invalid enum initializer: " ++ msg)

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
skipQualifiers = qualifierNames >> pure ()

qualifierNames :: Parser [String]
qualifierNames = do
  tok <- peekMaybe
  case fmap tokenKind tok of
    Just (TokIdent name) | name `elem` unsupportedQualifiers ->
      peek >>= \t -> failAt t (name ++ " is not supported")
    Just (TokIdent "typedef") ->
      peek >>= \t -> failAt t "typedef is not the first specifier"
    Just (TokIdent name) | name `elem` storageAndTypeQualifiers -> do
      advanceToken
      rest <- qualifierNames
      pure (name:rest)
    Just (TokIdent name) | name `elem` ["__attribute__", "__extension__"] ->
      skipAttributes >> qualifierNames
    _ -> pure []

skipAttributes :: Parser ()
skipAttributes = do
  tok <- peekMaybe
  case fmap tokenKind tok of
    Just (TokIdent name) | name `elem` asmLabelNames -> do
      advanceToken
      skipOptionalBalancedParens
      skipAttributes
    Just (TokIdent "__attribute__") -> do
      advanceToken
      skipOptionalBalancedParens
      skipAttributes
    Just (TokIdent "__extension__") ->
      advanceToken >> skipAttributes
    _ -> pure ()

asmLabelNames :: [String]
asmLabelNames = ["asm", "__asm", "__asm__"]

skipOptionalBalancedParens :: Parser ()
skipOptionalBalancedParens = do
  open <- eatPunct "("
  when open (skipBalanced "(" ")")

data DeclName = RequiredName | OptionalName | NoName

-- Layers run from the identifier outward: f() is a function, (*f)() is
-- a pointer. Keep the parameter scope of each function layer until we know
-- which layer, if any, belongs to a definition.
data DeclLayer = PointerLayer | ArrayLayer (Maybe Expr) | FunctionLayer [Param] ParserEnv

applyLayers :: [DeclLayer] -> CType -> CType
applyLayers layers base = case layers of
  [] -> base
  layer:rest -> case layer of
    PointerLayer -> CPtr (applyLayers rest base)
    ArrayLayer bound -> CArray (applyLayers rest base) bound
    FunctionLayer params _ -> CFunc (applyLayers rest base) (paramTypes (adjustParameters params))

declarator :: CType -> Parser (CType, String)
declarator ty = do
  (layers, name) <- declaratorLayers RequiredName False
  pure (applyLayers layers ty, name)

declaratorLayers :: DeclName -> Bool -> Parser ([DeclLayer], String)
declaratorLayers mode parameterMode = do
  pointers <- manyP (needPunct "*" >> skipQualifiers >> pure PointerLayer)
  open <- eatPunct "("
  (inner, name) <- if open
    then declaratorParen mode parameterMode
    else do
      name <- case mode of
        RequiredName -> needIdent
        OptionalName -> optionalIdent
        NoName -> pure ""
      pure ([], name)
  suffix <- declaratorSuffixes parameterMode (null inner)
  skipAttributes
  pure (inner ++ suffix ++ pointers, name)

declaratorParen :: DeclName -> Bool -> Parser ([DeclLayer], String)
declaratorParen mode parameterMode = do
  tok <- peek
  typeStart <- tokenStartsType tok
  let abstractFunction = case mode of
        RequiredName -> False
        _ -> case tokenKind tok of
          TokPunct ")" -> True
          _ -> typeStart
  if abstractFunction
    then do
      layer <- functionLayer
      pure ([layer], "")
    else do
      inner <- declaratorLayers mode parameterMode
      needPunct ")"
      pure inner

functionLayer :: Parser DeclLayer
functionLayer = withParserScope (do
  params <- parametersInScope
  scope <- pEnv
  pure (FunctionLayer params scope))

declaratorSuffixes :: Bool -> Bool -> Parser [DeclLayer]
declaratorSuffixes parameterMode first = do
  tok <- peekMaybe
  case fmap tokenKind tok of
    Just (TokPunct "(") -> do
      advanceToken
      layer <- functionLayer
      rest <- declaratorSuffixes parameterMode False
      pure (layer:rest)
    Just (TokPunct "[") -> do
      advanceToken
      bound <- declaratorArrayBound parameterMode first
      rest <- declaratorSuffixes parameterMode False
      pure (ArrayLayer bound:rest)
    _ -> pure []

declaratorArrayBound :: Bool -> Bool -> Parser (Maybe Expr)
declaratorArrayBound parameterMode first = do
  staticBound <- if parameterMode && first
    then do
      before <- eatIdent "static"
      skipParameterArrayQualifiers
      if before then pure True else eatIdent "static"
    else pure False
  tok <- peek
  case tokenKind tok of
    TokIdent name | name `elem` ["static", "const", "volatile", "restrict"] ->
      failAt tok (if parameterMode then "array parameter modifiers require the outermost dimension" else "array modifiers require a parameter declarator")
    _ -> pure ()
  bound <- if staticBound then Just <$> assignExpr else optionalP assignExpr
  needPunct "]"
  pure bound

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
            rhs <- expression (case assoc of
              RightAssoc -> prec
              LeftAssoc -> prec + 1)
            let node = assignNode op lhs rhs
            climb node
          _ -> pure lhs
        Nothing -> pure lhs

binop :: String -> Maybe (Int, Assoc)
binop op = case op of
  [c] -> case c of
    ',' -> Just (0, LeftAssoc)
    '=' -> Just (1, RightAssoc)
    _ -> binopArith op
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
    TokIdent s | symbolSetMember s builtinTypeWords ->
      failAt tok "a type name is not an expression"
    TokIdent s -> do
      advanceToken
      constant <- lookupParserConstant s
      pure (case constant of
        Just value -> parserConstantExpr value
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

-- EInt contains an unsigned token spelling, not a signed decimal value.
-- Spell a negative constant as -(abs(value)-1)-1: the intermediate fits even
-- at the minimum Int, and a minimum C int enumerator retains int type rather
-- than acquiring the wider type of the positive literal 2147483648.
parserConstantExpr :: Constant -> Expr
parserConstantExpr value@(Constant size unsigned bytes) =
  case constantToIntChecked value of
    Just n -> if n < 0
      then EBinary "-" (EUnary "-" (EInt (show (negate (n + 1))))) (EInt "1")
      else EInt (show n)
    Nothing ->
      let ty = if size <= 4 then CUnsigned else if unsigned then CUnsignedLongLong else CLongLong
          digits = "0123456789abcdef"
          hexByte byte = [digits !! (byte `div` 16), digits !! (byte `mod` 16)]
      in ECast ty (EInt ("0x" ++ concatMap hexByte (reverse bytes) ++ "ULL"))

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
  "+=" -> ECompoundAssign "+" lhs rhs
  "-=" -> ECompoundAssign "-" lhs rhs
  "*=" -> ECompoundAssign "*" lhs rhs
  "/=" -> ECompoundAssign "/" lhs rhs
  "%=" -> ECompoundAssign "%" lhs rhs
  "<<=" -> ECompoundAssign "<<" lhs rhs
  ">>=" -> ECompoundAssign ">>" lhs rhs
  "&=" -> ECompoundAssign "&" lhs rhs
  "^=" -> ECompoundAssign "^" lhs rhs
  "|=" -> ECompoundAssign "|" lhs rhs
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

stringLiteral :: Parser [Int]
stringLiteral = do
  first <- needString
  rest <- manyP needString
  pure (stringLiteralBytes (first:rest))

needString :: Parser String
needString = do
  tok <- peek
  case tokenKind tok of
    TokString s -> advanceToken >> pure s
    _ -> failAt tok "expected string literal"

declarationWords :: SymbolSet
declarationWords = wordSet (builtinTypeNames ++ storageAndTypeQualifiers ++ ["typedef"])

builtinTypeWords :: SymbolSet
builtinTypeWords = wordSet builtinTypeNames

wordSet :: [String] -> SymbolSet
wordSet = foldr symbolSetInsert symbolSetEmpty

builtinTypeNames :: [String]
builtinTypeNames =
  [ "void", "_Bool", "int", "char", "signed", "unsigned", "short", "long", "float", "double"
  , "struct", "union", "enum"
  ]

storageAndTypeQualifiers :: [String]
storageAndTypeQualifiers =
  [ "const", "volatile", "static", "extern", "register", "inline", "auto"
  , "restrict", "_Noreturn", "_Atomic"
  ]

unsupportedQualifiers :: [String]
unsupportedQualifiers =
  ["_Thread_local", "__thread", "_Alignas", "_Generic"]

tokenStartsType :: Token -> Parser Bool
tokenStartsType tok = (\env -> tokenStartsTypeInEnv env tok) <$> pEnv

tokenStartsTypeInEnv :: ParserEnv -> Token -> Bool
tokenStartsTypeInEnv env tok = case tokenKind tok of
  TokIdent name -> symbolSetMember name declarationWords || parserEnvHasType name env
  _ -> False

identifierStartsDeclaration :: Parser Bool
identifierStartsDeclaration = pRaw $ \env toks -> Unconsumed (Ok (go env toks) env toks) where
  go env toks = case toks of
    tok:_ -> tokenStartsTypeInEnv env tok
    [] -> False

parserEnvHasType :: String -> ParserEnv -> Bool
parserEnvHasType name env = case parserEnvType name env of
  Just _ -> True
  Nothing -> False

parserEnvType :: String -> ParserEnv -> Maybe CType
parserEnvType name env = case scopeMapLookup name (parserBindings env) of
  Just (ParserType ty) -> Just ty
  _ -> Nothing

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
