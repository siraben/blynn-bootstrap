module Target
  ( Target
  , defaultHccTarget
  , parseHccTarget
  , hccTargetName
  , hccTargetWordBits
  ) where

import Base

data Target = Target String Int

defaultHccTarget :: Target
defaultHccTarget = Target "amd64" 64

parseHccTarget :: String -> Maybe Target
parseHccTarget target = case target of
  "amd64" -> Just (Target "amd64" 64)
  "x86_64" -> Just (Target "amd64" 64)
  "aarch64" -> Just (Target "aarch64" 64)
  "arm64" -> Just (Target "aarch64" 64)
  "riscv64" -> Just (Target "riscv64" 64)
  "i386" -> Just (Target "i386" 32)
  "x86" -> Just (Target "i386" 32)
  _ -> Nothing

hccTargetName :: Target -> String
hccTargetName (Target name _) = name

hccTargetWordBits :: Target -> Int
hccTargetWordBits (Target _ bits) = bits
