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
  c == ' ' || c == '\n' || c == '\x09' || c == '\x0d' || c == '\x0b' || c == '\x0c'

isDigitChar :: Char -> Bool
isDigitChar c = c >= '0' && c <= '9'

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
