module ParserScan
  ( collectEnumConstants
  , collectTypedefNames
  ) where

import Base
import ConstExpr
import SymbolTable
import TextUtil
import TypesToken

collectEnumConstants :: [Token] -> [(String, Int)]
collectEnumConstants toks = reverse (go [] toks) where
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

parseEnumBody :: [(String, Int)] -> Int -> [Token] -> ([(String, Int)], [Token])
parseEnumBody env nextValue toks = case toks of
  [] -> (env, [])
  Token _ (TokPunct "}"):rest -> (env, rest)
  Token _ (TokPunct ","):rest -> parseEnumBody env nextValue rest
  Token _ (TokIdent name):rest ->
    let (value, afterValue) = enumValue env nextValue rest
        env' = (name, value) : env
    in parseEnumBody env' (value + 1) afterValue
  Token _ (TokPunct "{"):rest ->
    parseEnumBody env nextValue (dropBalancedBrace 1 rest)
  _:rest ->
    parseEnumBody env nextValue rest

enumValue :: [(String, Int)] -> Int -> [Token] -> (Int, [Token])
enumValue env nextValue toks = case toks of
  Token _ (TokPunct "="):rest ->
    let (exprToks, tailToks) = takeEnumValueExpr rest
    in case parseConstExpr env exprToks of
      Right (value, []) -> (value, tailToks)
      Right (value, trailing) | all ignorableEnumExprTail trailing -> (value, tailToks)
      _ -> (nextValue, tailToks)
  _ -> (nextValue, toks)

ignorableEnumExprTail :: Token -> Bool
ignorableEnumExprTail tok = case scanTokenKind tok of
  TokPunct ")" -> True
  _ -> False

takeEnumValueExpr :: [Token] -> ([Token], [Token])
takeEnumValueExpr = go 0 0 0 [] where
  go :: Int -> Int -> Int -> [Token] -> [Token] -> ([Token], [Token])
  go braces parens brackets acc toks = case toks of
    [] -> (reverse acc, [])
    tok:rest -> case scanTokenKind tok of
      TokPunct "," | braces == 0 && parens == 0 && brackets == 0 -> (reverse acc, toks)
      TokPunct "}" | braces == 0 && parens == 0 && brackets == 0 -> (reverse acc, toks)
      TokPunct "{" -> go (braces + 1) parens brackets (tok:acc) rest
      TokPunct "}" -> go (max 0 (braces - 1)) parens brackets (tok:acc) rest
      TokPunct "(" -> go braces (parens + 1) brackets (tok:acc) rest
      TokPunct ")" -> go braces (max 0 (parens - 1)) brackets (tok:acc) rest
      TokPunct "[" -> go braces parens (brackets + 1) (tok:acc) rest
      TokPunct "]" -> go braces parens (max 0 (brackets - 1)) (tok:acc) rest
      _ -> go braces parens brackets (tok:acc) rest

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
    tok:rest -> case scanTokenKind tok of
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
typedefName toks = case functionDeclaratorName toks of
  Just name -> Just name
  Nothing -> case pointerDeclaratorName toks of
    Just name -> Just name
    Nothing -> lastIdentifier toks

functionDeclaratorName :: [Token] -> Maybe String
functionDeclaratorName = go 0 0 where
  go :: Int -> Int -> [Token] -> Maybe String
  go parens brackets toks = case toks of
    Token _ (TokIdent name):Token _ (TokPunct "("):_
      | parens == 0 && brackets == 0 && not (isCKeyword name) -> Just name
    Token _ (TokPunct "("):rest -> go (parens + 1) brackets rest
    Token _ (TokPunct ")"):rest -> go (max 0 (parens - 1)) brackets rest
    Token _ (TokPunct "["):rest -> go parens (brackets + 1) rest
    Token _ (TokPunct "]"):rest -> go parens (max 0 (brackets - 1)) rest
    _:rest -> go parens brackets rest
    [] -> Nothing

pointerDeclaratorName :: [Token] -> Maybe String
pointerDeclaratorName toks = case toks of
  Token _ (TokPunct "("):Token _ (TokPunct "*"):Token _ (TokIdent name):Token _ (TokPunct ")"):_ ->
    Just name
  _:rest -> pointerDeclaratorName rest
  [] -> Nothing

lastIdentifier :: [Token] -> Maybe String
lastIdentifier = go Nothing where
  go found toks = case toks of
    [] -> found
    Token _ (TokIdent name):rest | not (isCKeyword name) -> go (Just name) rest
    _:rest -> go found rest

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
      tok:rest -> case scanTokenKind tok of
        TokPunct "{" -> dropBalancedBrace (depth + 1) rest
        TokPunct "}" -> dropBalancedBrace (depth - 1) rest
        _ -> dropBalancedBrace depth rest

splitTopLevelCommas :: [Token] -> [[Token]]
splitTopLevelCommas = go 0 0 [] [] where
  go :: Int -> Int -> [Token] -> [[Token]] -> [Token] -> [[Token]]
  go parens brackets current acc toks = case toks of
    [] -> reverse (reverse current : acc)
    tok:rest -> case scanTokenKind tok of
      TokPunct "," | parens == 0 && brackets == 0 ->
        go parens brackets [] (reverse current : acc) rest
      TokPunct "(" -> go (parens + 1) brackets (tok:current) acc rest
      TokPunct ")" -> go (max 0 (parens - 1)) brackets (tok:current) acc rest
      TokPunct "[" -> go parens (brackets + 1) (tok:current) acc rest
      TokPunct "]" -> go parens (max 0 (brackets - 1)) (tok:current) acc rest
      _ -> go parens brackets (tok:current) acc rest

unique :: [String] -> [String]
unique = go symbolSetEmpty where
  go seen names = case names of
    [] -> []
    x:xs ->
      if symbolSetMember x seen
      then go seen xs
      else x : go (symbolSetInsert x seen) xs

isCKeyword :: String -> Bool
isCKeyword name = name `elem`
  [ "void", "char", "short", "int", "long", "float", "double", "signed", "unsigned"
  , "struct", "union", "enum", "const", "volatile", "static", "extern", "register", "inline"
  , "auto", "typedef"
  ]

scanTokenKind :: Token -> TokenKind
scanTokenKind (Token _ kind) = kind
