module LowerBuiltins
  ( builtinConstant
  , isIgnoredSideEffectCall
  , isSignedNamedInteger
  , namedIntegerSize
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
  "asm" -> True
  "oputs" -> True
  "eputs" -> True
  _ -> False

isSignedNamedInteger :: String -> Bool
isSignedNamedInteger name = case name of
  "signed_short" -> True
  "int8_t" -> True
  "int16_t" -> True
  "int32_t" -> True
  "int64_t" -> True
  "ssize_t" -> True
  "time_t" -> True
  "ptrdiff_t" -> True
  "intptr_t" -> True
  "Elf32_Sword" -> True
  "Elf64_Sword" -> True
  "Elf32_Sxword" -> True
  "Elf64_Sxword" -> True
  _ -> False

namedIntegerSize :: String -> Maybe Int
namedIntegerSize name = case name of
  "int8_t" -> Just 1
  "uint8_t" -> Just 1
  "signed_short" -> Just 2
  "unsigned_short" -> Just 2
  "int16_t" -> Just 2
  "uint16_t" -> Just 2
  "Elf32_Half" -> Just 2
  "Elf64_Half" -> Just 2
  "Elf32_Section" -> Just 2
  "Elf64_Section" -> Just 2
  "Elf32_Versym" -> Just 2
  "Elf64_Versym" -> Just 2
  "int32_t" -> Just 4
  "uint32_t" -> Just 4
  "Elf32_Word" -> Just 4
  "Elf64_Word" -> Just 4
  "Elf32_Sword" -> Just 4
  "Elf64_Sword" -> Just 4
  "Elf32_Addr" -> Just 4
  "Elf32_Off" -> Just 4
  "unsigned_long" -> Just 8
  "int64_t" -> Just 8
  "uint64_t" -> Just 8
  "size_t" -> Just 8
  "ssize_t" -> Just 8
  "time_t" -> Just 8
  "ptrdiff_t" -> Just 8
  "intptr_t" -> Just 8
  "uintptr_t" -> Just 8
  "addr_t" -> Just 8
  "Elf32_Xword" -> Just 8
  "Elf32_Sxword" -> Just 8
  "Elf64_Xword" -> Just 8
  "Elf64_Sxword" -> Just 8
  "Elf64_Addr" -> Just 8
  "Elf64_Off" -> Just 8
  _ -> Nothing
