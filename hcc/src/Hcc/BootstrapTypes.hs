module BootstrapTypes
  ( builtinTypeAliases
  , isSignedNamedInteger
  , namedIntegerSize
  , isNamedInteger
  , isPointerLikeName
  ) where

import Base
import TypesAst

-- Width zero means target word size. Seeding and pointer compatibility are
-- independent: Elf spellings remain permissive named types, not parser typedefs.
data BootstrapInteger = BootstrapInteger
  { bootstrapName :: String
  , bootstrapWidth :: Int
  , bootstrapSigned :: Bool
  , bootstrapSeeded :: Bool
  , bootstrapPointerLike :: Bool
  }

bootstrapIntegers :: [BootstrapInteger]
bootstrapIntegers =
  [ BootstrapInteger "int8_t" 1 True True False
  , BootstrapInteger "uint8_t" 1 False True False
  , BootstrapInteger "signed_short" 2 True False False
  , BootstrapInteger "unsigned_short" 2 False False False
  , BootstrapInteger "int16_t" 2 True True False
  , BootstrapInteger "uint16_t" 2 False True False
  , BootstrapInteger "Elf32_Half" 2 False False False
  , BootstrapInteger "Elf64_Half" 2 False False False
  , BootstrapInteger "Elf32_Section" 2 False False False
  , BootstrapInteger "Elf64_Section" 2 False False False
  , BootstrapInteger "Elf32_Versym" 2 False False False
  , BootstrapInteger "Elf64_Versym" 2 False False False
  , BootstrapInteger "int32_t" 4 True True False
  , BootstrapInteger "uint32_t" 4 False True False
  , BootstrapInteger "Elf32_Word" 4 False False False
  , BootstrapInteger "Elf64_Word" 4 False False False
  , BootstrapInteger "Elf32_Sword" 4 True False False
  , BootstrapInteger "Elf64_Sword" 4 True False False
  , BootstrapInteger "Elf32_Addr" 4 False False False
  , BootstrapInteger "Elf32_Off" 4 False False False
  , BootstrapInteger "unsigned_long" 0 False False False
  , BootstrapInteger "int64_t" 8 True True False
  , BootstrapInteger "uint64_t" 8 False True False
  , BootstrapInteger "size_t" 0 False True False
  , BootstrapInteger "ssize_t" 0 True True False
  , BootstrapInteger "time_t" 0 True True False
  , BootstrapInteger "ptrdiff_t" 0 True True False
  , BootstrapInteger "intptr_t" 0 True True True
  , BootstrapInteger "uintptr_t" 0 False True True
  , BootstrapInteger "addr_t" 0 False False False
  , BootstrapInteger "Elf32_Xword" 8 False False False
  , BootstrapInteger "Elf32_Sxword" 8 True False False
  , BootstrapInteger "Elf64_Xword" 8 False False False
  , BootstrapInteger "Elf64_Sxword" 8 True False False
  , BootstrapInteger "Elf64_Addr" 8 False False False
  , BootstrapInteger "Elf64_Off" 8 False False False
  ]

bootstrapInteger :: String -> Maybe BootstrapInteger
bootstrapInteger name = find (\entry -> bootstrapName entry == name) bootstrapIntegers

builtinTypeAliases :: [(String, CType)]
builtinTypeAliases =
  [ ("FILE", CStruct "FILE")
  , ("FUNCTION", CLong)
  , ("va_list", CPtr CVoid)
  , ("__builtin_va_list", CPtr CVoid)
  , ("jmp_buf", CPtr CVoid)
  ] ++ concatMap seededAlias bootstrapIntegers

seededAlias :: BootstrapInteger -> [(String, CType)]
seededAlias entry =
  let name = bootstrapName entry
  in if bootstrapSeeded entry then [(name, CNamed name)] else []

isSignedNamedInteger :: String -> Bool
isSignedNamedInteger name = maybe False bootstrapSigned (bootstrapInteger name)

namedIntegerSize :: Int -> String -> Maybe Int
namedIntegerSize word name = case bootstrapInteger name of
  Just entry -> let width = bootstrapWidth entry in Just (if width == 0 then word else width)
  Nothing -> Nothing

isNamedInteger :: String -> Bool
isNamedInteger name = maybe False (const True) (bootstrapInteger name)

-- Preserve pointer-compatible casts/initializers for intptr aliases; ordinary
-- arithmetic still treats them as integers, not as pointers with an element type.
isPointerLikeName :: String -> Bool
isPointerLikeName name = maybe False bootstrapPointerLike (bootstrapInteger name)
