module LowerBuiltins where

import LowerCommon

builtinConstant :: String -> Maybe Int
builtinConstant name = case name of
  "NULL" -> Just 0
  "__null" -> Just 0
  "__LINE__" -> Just 0
  "CH_EOB" -> Just 92
  "EINTR" -> Just 4
  "char" -> Just 1
  "short" -> Just 2
  "int" -> Just 4
  "long" -> Just 8
  "TOKSYM_TAL_LIMIT" -> Just 256
  "TOKSTR_TAL_LIMIT" -> Just 1024
  "TOKSYM_TAL_SIZE" -> Just (768 * 1024)
  "TOKSTR_TAL_SIZE" -> Just (768 * 1024)
  "TOK_ALLOC_INCR" -> Just 512
  "TOK_IDENT" -> Just 256
  "SYM_FIRST_ANOM" -> Just 268435456
  _ -> Nothing

isIgnoredSideEffectCall :: String -> Bool
isIgnoredSideEffectCall name = stringMember name ignoredSideEffectCalls

ignoredSideEffectCalls :: [String]
ignoredSideEffectCalls = "asm" : "oputs" : "eputs" : []

isSignedNamedInteger :: String -> Bool
isSignedNamedInteger name = stringMember name signedNamedIntegerTypes

namedIntegerSize :: String -> Maybe Int
namedIntegerSize name =
  if stringMember name namedIntegerSize1
    then Just 1
    else if stringMember name namedIntegerSize2
      then Just 2
      else if stringMember name namedIntegerSize4
        then Just 4
        else if stringMember name namedIntegerSize8
          then Just 8
          else Nothing

namedIntegerSize1 :: [String]
namedIntegerSize1 = "int8_t" : "uint8_t" : []

namedIntegerSize2 :: [String]
namedIntegerSize2 =
  "signed_short" : "unsigned_short" : "int16_t" : "uint16_t" :
  "Elf32_Half" : "Elf64_Half" : "Elf32_Section" : "Elf64_Section" :
  "Elf32_Versym" : "Elf64_Versym" : []

namedIntegerSize4 :: [String]
namedIntegerSize4 =
  "int32_t" : "uint32_t" : "Elf32_Word" : "Elf64_Word" :
  "Elf32_Sword" : "Elf64_Sword" : "Elf32_Addr" : "Elf32_Off" : []

namedIntegerSize8 :: [String]
namedIntegerSize8 =
  "unsigned_long" : "int64_t" : "uint64_t" : "size_t" :
  "ssize_t" : "time_t" : "ptrdiff_t" : "intptr_t" :
  "uintptr_t" : "addr_t" : "Elf32_Xword" : "Elf32_Sxword" :
  "Elf64_Xword" : "Elf64_Sxword" : "Elf64_Addr" : "Elf64_Off" : []

signedNamedIntegerTypes :: [String]
signedNamedIntegerTypes =
  "signed_short" : "int8_t" : "int16_t" : "int32_t" : "int64_t" :
  "ssize_t" : "time_t" : "ptrdiff_t" : "intptr_t" :
  "Elf32_Sword" : "Elf64_Sword" : "Elf32_Sxword" : "Elf64_Sxword" :
  []
