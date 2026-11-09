module Directive
  ( Directive(..)
  , parseDirective
  , directiveName
  , isDirectiveChar
  ) where

import Base
import TextUtil

data Directive = Directive String String

parseDirective :: String -> Directive
parseDirective text = case dropSpaces text of
  '#':rest ->
    let rest' = dropSpaces rest
        (name, body) = span isDirectiveChar rest'
    in Directive name (dropSpaces body)
  _ -> Directive "" ""

directiveName :: String -> Maybe String
directiveName text = case dropSpaces text of
  c:_ | isIdentStart c -> Just (takeWhile isIdentChar (dropSpaces text))
  _ -> Nothing

isDirectiveChar :: Char -> Bool
isDirectiveChar c = isAsciiAlphaNum c || c == '_'

dropSpaces :: String -> String
dropSpaces = dropWhile isSpaceChar
