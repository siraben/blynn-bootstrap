replicateM = (sequence .) . replicate
readNatural = foldl (\n d -> toInteger 10*n + toInteger (ord d - ord '0')) (toInteger 0)
readInteger ('-':t) = negate $ readNatural t
readInteger s = readNatural s
doubleFromInt = fromIntegral
wordFromInt = fromIntegral
rawDouble _ f = f 0 0
forM = flip mapM
