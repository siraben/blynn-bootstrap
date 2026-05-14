module TokenIr
  ( encodeTokens
  , decodeTokens
  , isTokenIr
  ) where

import Base
import IntTable
import SymbolTable
import TypesToken

magic :: String
magic = "HCC-TOKENS-1\n"

isTokenIr :: String -> Bool
isTokenIr text = take (length magic) text == magic

encodeTokens :: [Token] -> String
encodeTokens toks =
  magic ++ renderStrings strings ++ "T\n" ++ renderTokenRefs refs
  where
    (strings, refs) = internTokens toks

internTokens :: [Token] -> ([String], [(Char, Int)])
internTokens toks = finish (go toks symbolMapEmpty [] 0 []) where
  finish (_, _, stringsRev, _, refsRev) = (reverse stringsRev, reverse refsRev)

  go rest tab strings next refs = case rest of
    [] -> (rest, tab, strings, next, refs)
    tok:more ->
      let (tag, text) = tokenParts tok in
      case symbolMapLookup text tab of
        Just n -> go more tab strings next ((tag, n):refs)
        Nothing ->
          go more
            (symbolMapInsert text next tab)
            (text:strings)
            (next + 1)
            ((tag, next):refs)

tokenParts :: Token -> (Char, String)
tokenParts (Token _ kind) = case kind of
  TokIdent s -> ('I', s)
  TokInt s -> ('N', s)
  TokFloat s -> ('F', s)
  TokChar s -> ('C', s)
  TokString s -> ('S', s)
  TokPunct s -> ('P', s)
  TokDirective s -> ('D', s)

renderStrings :: [String] -> String
renderStrings strings = foldr renderString "" strings

renderString :: String -> String -> String
renderString text rest = 'S' : show (length text) ++ ":" ++ text ++ "\n" ++ rest

renderTokenRefs :: [(Char, Int)] -> String
renderTokenRefs refs = foldr renderTokenRef "" refs

renderTokenRef :: (Char, Int) -> String -> String
renderTokenRef (tag, index) rest =
  if index < compactRefBase
    then shortRefTag tag : refDigit index : rest
    else if index < compactRefLimit
    then tag : encodeRefIndex index rest
    else 'X' : tag : show index ++ "\n" ++ rest

decodeTokens :: String -> Maybe [Token]
decodeTokens text =
  case stripPrefix magic text of
    Nothing -> Nothing
    Just body -> case parseStrings body intMapEmpty 0 of
      Nothing -> Nothing
      Just (strings, refsText) -> decodeRefs strings refsText

stripPrefix :: String -> String -> Maybe String
stripPrefix prefix text =
  if take (length prefix) text == prefix
    then Just (drop (length prefix) text)
    else Nothing

parseStrings :: String -> IntMap String -> Int -> Maybe (IntMap String, String)
parseStrings text acc nextIndex = case text of
  'T':'\n':rest -> Just (acc, rest)
  'S':rest -> case parseNat rest of
    Just (len, ':':payload) ->
      let value = take len payload
          afterValue = drop len payload
      in if length value == len
          then case afterValue of
            '\n':more -> parseStrings more (intMapInsert nextIndex value acc) (nextIndex + 1)
            _ -> Nothing
          else Nothing
    _ -> Nothing
  _ -> Nothing

decodeRefs :: IntMap String -> String -> Maybe [Token]
decodeRefs strings text = go text [] where
  go rest acc = case rest of
    [] -> Just (reverse acc)
    'X':tag:more -> case parseNat more of
      Just (index, '\n':next) -> addDecoded tag index next acc
      _ -> Nothing
    tag:a:next -> case longRefTag tag of
      Just fullTag -> case refValue a of
        Just index -> addDecoded fullTag index next acc
        Nothing -> Nothing
      Nothing -> case next of
        b:more -> case decodeRefIndex a b of
          Just index -> addDecoded tag index more acc
          Nothing -> Nothing
        [] -> Nothing
    _ -> Nothing

  addDecoded tag index next acc = case intMapLookup index strings of
    Just value -> case tokenKindFrom tag value of
      Just kind -> go next (Token syntheticSpan kind : acc)
      Nothing -> Nothing
    Nothing -> Nothing

tokenKindFrom :: Char -> String -> Maybe TokenKind
tokenKindFrom tag text = case tag of
  'I' -> Just (TokIdent text)
  'N' -> Just (TokInt text)
  'F' -> Just (TokFloat text)
  'C' -> Just (TokChar text)
  'S' -> Just (TokString text)
  'P' -> Just (TokPunct text)
  'D' -> Just (TokDirective text)
  _ -> Nothing

syntheticSpan :: Span
syntheticSpan = Span (SrcPos 1 1) (SrcPos 1 1)

parseNat :: String -> Maybe (Int, String)
parseNat text = go text 0 False where
  go rest acc seen = case rest of
    c:more | c >= '0' && c <= '9' ->
      go more (acc * 10 + fromEnum c - fromEnum '0') True
    _ -> if seen then Just (acc, rest) else Nothing

compactRefBase :: Int
compactRefBase = 94

compactRefLimit :: Int
compactRefLimit = compactRefBase * compactRefBase

shortRefTag :: Char -> Char
shortRefTag tag = case tag of
  'I' -> 'i'
  'N' -> 'n'
  'F' -> 'f'
  'C' -> 'c'
  'S' -> 's'
  'P' -> 'p'
  'D' -> 'd'
  _ -> tag

longRefTag :: Char -> Maybe Char
longRefTag tag = case tag of
  'i' -> Just 'I'
  'n' -> Just 'N'
  'f' -> Just 'F'
  'c' -> Just 'C'
  's' -> Just 'S'
  'p' -> Just 'P'
  'd' -> Just 'D'
  _ -> Nothing

encodeRefIndex :: Int -> String -> String
encodeRefIndex index rest =
  refDigit hi : refDigit lo : rest
  where
    (hi, lo) = divMod index compactRefBase

refDigit :: Int -> Char
refDigit n = toEnum (33 + n)

decodeRefIndex :: Char -> Char -> Maybe Int
decodeRefIndex hi lo =
  case (refValue hi, refValue lo) of
    (Just h, Just l) -> Just (h * compactRefBase + l)
    _ -> Nothing

refValue :: Char -> Maybe Int
refValue c =
  let n = fromEnum c - 33
  in if n >= 0 && n < compactRefBase then Just n else Nothing
