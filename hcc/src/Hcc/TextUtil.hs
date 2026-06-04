module TextUtil
  ( prefixOf
  , suffixOf
  , trim
  , isSpaceChar
  , isDigitChar
  , isAsciiAlpha
  , isAsciiAlphaNum
  , isIdentStart
  , isIdentChar
  ) where

import Base

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
    code = fromEnum c

isDigitChar :: Char -> Bool
isDigitChar c = fromEnum c >= fromEnum '0' && fromEnum c <= fromEnum '9'

isAsciiAlpha :: Char -> Bool
isAsciiAlpha c = isAsciiLower c || isAsciiUpper c

isAsciiAlphaNum :: Char -> Bool
isAsciiAlphaNum c = isAsciiAlpha c || isDigitChar c

isIdentStart :: Char -> Bool
isIdentStart c = isAsciiAlpha c || c == '_'

isIdentChar :: Char -> Bool
isIdentChar c = isAsciiAlphaNum c || c == '_'

isAsciiLower :: Char -> Bool
isAsciiLower c = c >= 'a' && c <= 'z'

isAsciiUpper :: Char -> Bool
isAsciiUpper c = c >= 'A' && c <= 'Z'
