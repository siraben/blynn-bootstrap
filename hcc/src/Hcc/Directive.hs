module Directive
  ( Directive(..)
  , parseDirective
  , directiveName
  , directiveNameFromLine
  , directiveArgument
  , directiveRest
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

directiveNameFromLine :: String -> Maybe String
directiveNameFromLine line = case parseDirective line of
  Directive "" _ -> Nothing
  Directive name _ -> Just name

directiveArgument :: String -> String -> Maybe String
directiveArgument directive line = case parseDirective line of
  Directive name rest | name == directive -> directiveName rest
  _ -> Nothing

directiveRest :: String -> String -> String
directiveRest directive line = case parseDirective line of
  Directive name rest | name == directive -> rest
  _ -> ""

isDirectiveChar :: Char -> Bool
isDirectiveChar c = isAsciiAlphaNum c || c == '_'

dropSpaces :: String -> String
dropSpaces = dropWhile isSpaceChar
