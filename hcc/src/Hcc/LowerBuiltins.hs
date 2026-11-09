module LowerBuiltins
  ( builtinConstant
  , allowsImplicitFunction
  , isIgnoredSideEffectCall
  ) where

import Base

builtinConstant :: String -> Maybe Int
builtinConstant name = case name of
  "NULL" -> Just 0
  "__null" -> Just 0
  "__LINE__" -> Just 0
  "char" -> Just 1
  "short" -> Just 2
  "int" -> Just 4
  "long" -> Just 8
  _ -> Nothing

isIgnoredSideEffectCall :: String -> Bool
isIgnoredSideEffectCall name = case name of
  "oputs" -> True
  "eputs" -> True
  _ -> False


-- These names have statement-only bootstrap handling, not implicit prototypes.
allowsImplicitFunction :: String -> Bool
allowsImplicitFunction name = name /= "asm" && not (isIgnoredSideEffectCall name)
