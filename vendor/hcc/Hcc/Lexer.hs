module Hcc.Lexer
  ( LexError(..)
  , lexC
  ) where

import Data.Char (isAlpha, isAlphaNum, isDigit, isSpace)
import Data.List (isPrefixOf)

import Hcc.Token

data LexError = LexError SrcPos String
  deriving (Eq, Show)

data LexState = LexState
  { lsInput :: String
  , lsPos :: SrcPos
  , lsBol :: Bool
  }

lexC :: String -> Either LexError [Token]
lexC source = go (LexState source (SrcPos 1 1) True) [] where
  go st acc = case lsInput st of
    [] -> Right (reverse acc)
    c:cs
      | isSpace c -> go (advance c st { lsInput = cs }) acc
      | isDirectiveStart st c -> lexDirective st >>= \(tok, st') -> go st' (tok:acc)
      | startsLineComment (lsInput st) -> go (skipLineComment st) acc
      | startsBlockComment (lsInput st) -> case skipBlockComment st of
          Left err -> Left err
          Right st' -> go st' acc
      | isIdentStart c -> let (tok, st') = lexIdent st in go st' (tok:acc)
      | isDigit c -> let (tok, st') = lexNumber st in go st' (tok:acc)
      | c == '\'' -> lexQuoted '\'' TokChar st >>= \(tok, st') -> go st' (tok:acc)
      | c == '"' -> lexQuoted '"' TokString st >>= \(tok, st') -> go st' (tok:acc)
      | otherwise -> case lexPunct st of
          Just (tok, st') -> go st' (tok:acc)
          Nothing -> Left (LexError (lsPos st) ("unexpected character: " ++ [c]))

isDirectiveStart :: LexState -> Char -> Bool
isDirectiveStart st c = lsBol st && c == '#'

lexDirective :: LexState -> Either LexError (Token, LexState)
lexDirective st = Right (Token (Span start end) (TokDirective text), st') where
  start = lsPos st
  (text, st') = takeUntilNewline st
  end = lsPos st'

takeUntilNewline :: LexState -> (String, LexState)
takeUntilNewline st = go st [] where
  go cur acc = case lsInput cur of
    [] -> (reverse acc, cur)
    '\n':cs -> (reverse acc, advance '\n' cur { lsInput = cs })
    c:cs -> go (advance c cur { lsInput = cs }) (c:acc)

startsLineComment :: String -> Bool
startsLineComment s = "//" `isPrefixOf` s

startsBlockComment :: String -> Bool
startsBlockComment s = "/*" `isPrefixOf` s

skipLineComment :: LexState -> LexState
skipLineComment st = snd (takeUntilNewline st)

skipBlockComment :: LexState -> Either LexError LexState
skipBlockComment st = go (advanceMany "/*" st { lsInput = drop 2 (lsInput st) }) where
  start = lsPos st
  go cur = case lsInput cur of
    [] -> Left (LexError start "unterminated block comment")
    '*':'/':cs -> Right (advanceMany "*/" cur { lsInput = cs })
    c:cs -> go (advance c cur { lsInput = cs })

lexIdent :: LexState -> (Token, LexState)
lexIdent st = (Token (Span start end) (TokIdent text), st') where
  start = lsPos st
  (text, st') = takeWhileState isIdentChar st
  end = lsPos st'

lexNumber :: LexState -> (Token, LexState)
lexNumber st = (Token (Span start end) (TokInt text), st') where
  start = lsPos st
  (text, st') = takeNumber st
  end = lsPos st'

takeNumber :: LexState -> (String, LexState)
takeNumber st = case lsInput st of
  '0':'x':_ -> takeWhileState isNumberTail st
  '0':'X':_ -> takeWhileState isNumberTail st
  _ -> takeWhileState isNumberTail st

isNumberTail :: Char -> Bool
isNumberTail c =
  isAlphaNum c || c == '_' || c == '.' || c == '+' || c == '-'

lexQuoted :: Char -> (String -> TokenKind) -> LexState -> Either LexError (Token, LexState)
lexQuoted quote mkKind st = go (advance quote st { lsInput = drop 1 (lsInput st) }) [quote] where
  start = lsPos st
  go cur acc = case lsInput cur of
    [] -> Left (LexError start ("unterminated " ++ quotedName quote))
    c:cs
      | c == quote ->
          let st' = advance c cur { lsInput = cs }
              text = reverse (c:acc)
          in Right (Token (Span start (lsPos st')) (mkKind text), st')
      | c == '\\' -> case cs of
          [] -> Left (LexError start ("unterminated " ++ quotedName quote))
          e:rest -> go (advance e (advance c cur { lsInput = rest })) (e:c:acc)
      | c == '\n' -> Left (LexError (lsPos cur) ("newline in " ++ quotedName quote))
      | otherwise -> go (advance c cur { lsInput = cs }) (c:acc)

quotedName :: Char -> String
quotedName quote = if quote == '"' then "string literal" else "character literal"

lexPunct :: LexState -> Maybe (Token, LexState)
lexPunct st = firstMatch punctuators where
  firstMatch ps = case ps of
    [] -> Nothing
    p:rest ->
      if p `isPrefixOf` lsInput st
      then let st' = advanceMany p st { lsInput = drop (length p) (lsInput st) }
           in Just (Token (Span (lsPos st) (lsPos st')) (TokPunct p), st')
      else firstMatch rest

punctuators :: [String]
punctuators =
  [ "<<=", ">>=", "...", "++", "--", "->", "+=", "-=", "*=", "/=", "%="
  , "&=", "|=", "^=", "==", "!=", "<=", ">=", "&&", "||", "<<", ">>"
  , "##", "{", "}", "[", "]", "(", ")", ".", "&", "*", "+", "-", "~"
  , "!", "/", "%", "<", ">", "^", "|", "?", ":", ";", "=", ",", "#"
  ]

takeWhileState :: (Char -> Bool) -> LexState -> (String, LexState)
takeWhileState predicate st = go st [] where
  go cur acc = case lsInput cur of
    c:cs | predicate c -> go (advance c cur { lsInput = cs }) (c:acc)
    _ -> (reverse acc, cur)

isIdentStart :: Char -> Bool
isIdentStart c = isAlpha c || c == '_'

isIdentChar :: Char -> Bool
isIdentChar c = isAlphaNum c || c == '_'

advanceMany :: String -> LexState -> LexState
advanceMany s st = foldl (flip advance) st s

advance :: Char -> LexState -> LexState
advance c st = st { lsPos = nextPos c (lsPos st), lsBol = nextBol c (lsBol st) }

nextPos :: Char -> SrcPos -> SrcPos
nextPos c (SrcPos line col) =
  if c == '\n' then SrcPos (line + 1) 1 else SrcPos line (col + 1)

nextBol :: Char -> Bool -> Bool
nextBol c bol =
  if c == '\n' then True else if isSpace c then bol else False
