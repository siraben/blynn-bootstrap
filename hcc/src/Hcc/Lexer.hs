module Lexer
  ( LexError(..)
  , lexC
  ) where

import Base
import TextUtil
import TypesToken

data LexError = LexError SrcPos String

data LexState = LexState
  { lsInput :: String
  , lsPos :: SrcPos
  , lsBol :: Bool
  }

data NumberClass = NumberInt | NumberFloat

lexC :: String -> Either LexError [Token]
lexC source = go (LexState source (SrcPos 1 1) True) [] where
  go st acc = case lsInput st of
    [] -> Right (reverse acc)
    c:cs
      | lexerIsSpace c -> go (advanceSpace c st { lsInput = cs }) acc
      | isDirectiveStart st c -> lexDirective st >>= \(tok, st') -> go st' (tok:acc)
      | startsLineComment (lsInput st) -> go (skipLineComment st) acc
      | startsBlockComment (lsInput st) -> skipBlockComment st >>= \st' -> go st' acc
      | isIdentStart c -> let (tok, st') = lexIdent st in go st' (tok:acc)
      | isDigit c -> lexNumber st >>= \(tok, st') -> go st' (tok:acc)
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
startsLineComment s = case s of
  '/':'/':_ -> True
  _ -> False

startsBlockComment :: String -> Bool
startsBlockComment s = case s of
  '/':'*':_ -> True
  _ -> False

skipLineComment :: LexState -> LexState
skipLineComment st = snd (takeUntilNewline st)

skipBlockComment :: LexState -> Either LexError LexState
skipBlockComment st = case go (advanceMany "/*" st { lsInput = drop 2 (lsInput st) }) of
  Left err -> Left err
  Right st' -> Right st' { lsBol = lsBol st }
  where
    start = lsPos st
    go cur = case lsInput cur of
      [] -> Left (LexError start "unterminated block comment")
      '*':'/':cs -> Right (advanceMany "*/" cur { lsInput = cs })
      c:cs -> go (advance c cur { lsInput = cs })

lexIdent :: LexState -> (Token, LexState)
lexIdent st = (Token (Span start end) (TokIdent text), st') where
  start = lsPos st
  (text, st') = takeIdent st
  end = lsPos st'

takeIdent :: LexState -> (String, LexState)
takeIdent st = go st [] where
  go cur acc = case lsInput cur of
    c:cs | isIdentChar c -> go (advance c cur { lsInput = cs }) (c:acc)
    _ -> (reverse acc, cur)

lexNumber :: LexState -> Either LexError (Token, LexState)
lexNumber st = case takeNumber st of
  Left err -> Left err
  Right (text, cls, st') -> Right (Token (Span (lsPos st) (lsPos st')) (kind cls text), st')
  where
    kind NumberInt = TokInt
    kind NumberFloat = TokFloat

takeNumber :: LexState -> Either LexError (String, NumberClass, LexState)
takeNumber st = case lsInput st of
  '0':'x':rest -> takeHexNumber "0x" rest st
  '0':'X':rest -> takeHexNumber "0X" rest st
  _ -> Right (takeDecimalNumber st)

takeHexNumber :: String -> String -> LexState -> Either LexError (String, NumberClass, LexState)
takeHexNumber prefix rest st =
  let st0 = advanceMany prefix st { lsInput = rest }
      (digits, st1) = takeWhileState isHexDigit st0
      (fraction, st2) = takeHexFraction st1
      (exponentText, st3) = takeExponent "pP" st2
      (suffix, st4) =
        if null fraction && null exponentText
          then takeWhileState isIntSuffix st3
          else takeWhileState isFloatSuffix st3
      cls = if null fraction && null exponentText then NumberInt else NumberFloat
  in if null digits && null fraction
     then Left (LexError (lsPos st) ("hexadecimal constant requires at least one digit: " ++ prefix ++ suffix))
     else Right (prefix ++ digits ++ fraction ++ exponentText ++ suffix, cls, st4)

takeHexFraction :: LexState -> (String, LexState)
takeHexFraction st = case lsInput st of
  '.':'.':_ -> ("", st)
  '.':rest ->
    let st0 = advance '.' st { lsInput = rest }
        (digits, st1) = takeWhileState isHexDigit st0
    in ('.':digits, st1)
  _ -> ("", st)

takeDecimalNumber :: LexState -> (String, NumberClass, LexState)
takeDecimalNumber st =
  let (digits, st1) = takeWhileState isDigit st
      (fraction, st2) = takeFraction st1
      (exponentText, st3) = takeExponent "eE" st2
      (suffix, st4) = takeWhileState isNumberSuffix st3
      cls =
        if null fraction && null exponentText && not (hasFloatSuffix suffix)
          then NumberInt
          else NumberFloat
  in (digits ++ fraction ++ exponentText ++ suffix, cls, st4)

isIntSuffix :: Char -> Bool
isIntSuffix c = elem c "uUlL"

isNumberSuffix :: Char -> Bool
isNumberSuffix c = elem c "uUlLfF"

isFloatSuffix :: Char -> Bool
isFloatSuffix c = elem c "fFlL"

hasFloatSuffix :: String -> Bool
hasFloatSuffix text = case text of
  [] -> False
  c:rest -> c == 'f' || c == 'F' || hasFloatSuffix rest

takeFraction :: LexState -> (String, LexState)
takeFraction st = case lsInput st of
  '.':'.':_ -> ("", st)
  '.':rest ->
    let st0 = advance '.' st { lsInput = rest }
        (digits, st1) = takeWhileState isDigit st0
    in ('.':digits, st1)
  _ -> ("", st)

takeExponent :: String -> LexState -> (String, LexState)
takeExponent markers st = case lsInput st of
  c:rest | elem c markers ->
    let st0 = advance c st { lsInput = rest }
        (signText, st1) = takeExponentSign st0
        (digits, st2) = takeWhileState isDigit st1
    in if null digits then ("", st) else (c:signText ++ digits, st2)
  _ -> ("", st)

takeExponentSign :: LexState -> (String, LexState)
takeExponentSign st = case lsInput st of
  c:rest | c == '+' || c == '-' -> ([c], advance c st { lsInput = rest })
  _ -> ("", st)

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
lexPunct st = case lsInput st of
  '<':'<':'=':rest -> punct "<<=" rest
  '>':'>':'=':rest -> punct ">>=" rest
  '.':'.':'.':rest -> punct "..." rest
  '+':'+':rest -> punct "++" rest
  '-':'-':rest -> punct "--" rest
  '-':'>':rest -> punct "->" rest
  '+':'=':rest -> punct "+=" rest
  '-':'=':rest -> punct "-=" rest
  '*':'=':rest -> punct "*=" rest
  '/':'=':rest -> punct "/=" rest
  '%':'=':rest -> punct "%=" rest
  '&':'=':rest -> punct "&=" rest
  '|':'=':rest -> punct "|=" rest
  '^':'=':rest -> punct "^=" rest
  '=':'=':rest -> punct "==" rest
  '!':'=':rest -> punct "!=" rest
  '<':'=':rest -> punct "<=" rest
  '>':'=':rest -> punct ">=" rest
  '&':'&':rest -> punct "&&" rest
  '|':'|':rest -> punct "||" rest
  '<':'<':rest -> punct "<<" rest
  '>':'>':rest -> punct ">>" rest
  '#':'#':rest -> punct "##" rest
  '{':rest -> punct "{" rest
  '}':rest -> punct "}" rest
  '[':rest -> punct "[" rest
  ']':rest -> punct "]" rest
  '(':rest -> punct "(" rest
  ')':rest -> punct ")" rest
  '.':rest -> punct "." rest
  '&':rest -> punct "&" rest
  '*':rest -> punct "*" rest
  '+':rest -> punct "+" rest
  '-':rest -> punct "-" rest
  '~':rest -> punct "~" rest
  '!':rest -> punct "!" rest
  '/':rest -> punct "/" rest
  '%':rest -> punct "%" rest
  '<':rest -> punct "<" rest
  '>':rest -> punct ">" rest
  '^':rest -> punct "^" rest
  '|':rest -> punct "|" rest
  '?':rest -> punct "?" rest
  ':':rest -> punct ":" rest
  ';':rest -> punct ";" rest
  '=':rest -> punct "=" rest
  ',':rest -> punct "," rest
  '#':rest -> punct "#" rest
  _ -> Nothing
  where
    punct text rest =
      let st' = advancePunct text st { lsInput = rest }
      in Just (Token (Span (lsPos st) (lsPos st')) (TokPunct text), st')

takeWhileState :: (Char -> Bool) -> LexState -> (String, LexState)
takeWhileState predicate st = go st [] where
  go cur acc = case lsInput cur of
    c:cs | predicate c -> go (advance c cur { lsInput = cs }) (c:acc)
    _ -> (reverse acc, cur)

advanceMany :: String -> LexState -> LexState
advanceMany s st = foldl (flip advance) st s

advancePunct :: String -> LexState -> LexState
advancePunct text st = st { lsPos = addColumns (length text) (lsPos st), lsBol = False }

addColumns :: Int -> SrcPos -> SrcPos
addColumns count pos = case pos of
  SrcPos line col -> SrcPos line (col + count)

advance :: Char -> LexState -> LexState
advance c st = st { lsPos = nextPos c (lsPos st), lsBol = nextBol c (lsBol st) }

advanceSpace :: Char -> LexState -> LexState
advanceSpace c st = st { lsPos = nextPos c (lsPos st), lsBol = c == '\n' || lsBol st }

nextPos :: Char -> SrcPos -> SrcPos
nextPos c (SrcPos line col) =
  if c == '\n' then SrcPos (line + 1) 1 else SrcPos line (col + 1)

nextBol :: Char -> Bool -> Bool
nextBol c bol =
  c == '\n' || lexerIsSpaceNoNewline c && bol

lexerIsSpace :: Char -> Bool
lexerIsSpace c =
  c == ' ' || c == '\n' || lexerIsSpaceNoNewline c

lexerIsSpaceNoNewline :: Char -> Bool
lexerIsSpaceNoNewline c =
  let code = charCode c
  in code == 9 || code == 13 || code == 11 || code == 12

isDigit :: Char -> Bool
isDigit c = c >= '0' && c <= '9'

isHexDigit :: Char -> Bool
isHexDigit c = isDigit c || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
