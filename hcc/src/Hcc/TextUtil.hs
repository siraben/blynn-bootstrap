module TextUtil
  ( charCode
  , prefixOf
  , suffixOf
  , trim
  , isSpaceChar
  , isDigitChar
  , isAsciiAlpha
  , isAsciiAlphaNum
  , isIdentStart
  , isIdentChar
  , mapMaybe
  ) where

import Base

charCode :: Char -> Int
charCode = fromEnum

prefixOf :: String -> String -> Bool
prefixOf prefix text = take (length prefix) text == prefix

suffixOf :: String -> String -> Bool
suffixOf suffix text = reverse suffix `prefixOf` reverse text

trim :: String -> String
trim = reverse . dropWhile isSpaceChar . reverse . dropWhile isSpaceChar

isSpaceChar :: Char -> Bool
isSpaceChar c =
  c == ' ' || c == '\n' || code == 9 || code == 13 || code == 11 || code == 12
  where
    code = charCode c

isDigitChar :: Char -> Bool
isDigitChar c = c >= '0' && c <= '9'

isAsciiAlpha :: Char -> Bool
isAsciiAlpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')

isAsciiAlphaNum :: Char -> Bool
isAsciiAlphaNum c = isAsciiAlpha c || isDigitChar c

isIdentStart :: Char -> Bool
isIdentStart c = isAsciiAlpha c || c == '_'

isIdentChar :: Char -> Bool
isIdentChar c = isAsciiAlphaNum c || c == '_'

mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe f xs = case xs of
  [] -> []
  x:rest -> case f x of
    Just y -> y : mapMaybe f rest
    Nothing -> mapMaybe f rest
