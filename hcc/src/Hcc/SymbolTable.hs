module SymbolTable
  ( SymbolMap
  , SymbolSet
  , symbolMapEmpty
  , symbolSetEmpty
  , symbolMapLookup
  , symbolMapInsert
  , symbolMapDelete
  , symbolMapMember
  , symbolSetFromList
  , symbolSetMember
  , symbolSetInsert
  , symbolSetDelete
  ) where

import Base

data Color = R | B

data Tree a
  = E
  | N Color String Int (Maybe a) (Tree a) (Tree a)

data SymbolMap a = SymbolMap (Tree a)

data SymbolSet = SymbolSet (Tree ())

symbolMapEmpty :: SymbolMap a
symbolMapEmpty = SymbolMap E

symbolSetEmpty :: SymbolSet
symbolSetEmpty = SymbolSet E

symbolMapLookup :: String -> SymbolMap a -> Maybe a
symbolMapLookup k (SymbolMap t) = lookupT k t

symbolMapInsert :: String -> a -> SymbolMap a -> SymbolMap a
symbolMapInsert k v (SymbolMap t) = SymbolMap (insertT k v t)

symbolMapDelete :: String -> SymbolMap a -> SymbolMap a
symbolMapDelete k (SymbolMap t) = SymbolMap (deleteT k t)

symbolMapMember :: String -> SymbolMap a -> Bool
symbolMapMember k m = case symbolMapLookup k m of
  Just _ -> True
  Nothing -> False

symbolSetFromList :: [String] -> SymbolSet
symbolSetFromList [] = symbolSetEmpty
symbolSetFromList (x:xt) = symbolSetInsert x (symbolSetFromList xt)

symbolSetMember :: String -> SymbolSet -> Bool
symbolSetMember k (SymbolSet t) = case lookupT k t of
  Just _ -> True
  Nothing -> False

symbolSetInsert :: String -> SymbolSet -> SymbolSet
symbolSetInsert k (SymbolSet t) = SymbolSet (insertT k () t)

symbolSetDelete :: String -> SymbolSet -> SymbolSet
symbolSetDelete k (SymbolSet t) = SymbolSet (deleteT k t)

lookupT :: String -> Tree a -> Maybe a
lookupT k t = lookupH k (hash k) t

lookupH :: String -> Int -> Tree a -> Maybe a
lookupH _ _ E = Nothing
lookupH k kh (N _ x xh v l r) = case cmpHash k kh x xh of
  Lt -> lookupH k kh l
  Eq -> v
  Gt -> lookupH k kh r

insertT :: String -> a -> Tree a -> Tree a
insertT k v t = alterT k (Just v) t

deleteT :: String -> Tree a -> Tree a
deleteT k t = alterT k Nothing t

alterT :: String -> Maybe a -> Tree a -> Tree a
alterT k v t = blacken (go (hash k) t) where
  go kh u = case u of
    E -> N R k kh v E E
    N c x xh old l r -> case cmpHash k kh x xh of
      Lt -> bal c x xh old (go kh l) r
      Eq -> N c k kh v l r
      Gt -> bal c x xh old l (go kh r)

blacken :: Tree a -> Tree a
blacken E = E
blacken (N _ x xh v l r) = N B x xh v l r

bal :: Color -> String -> Int -> Maybe a -> Tree a -> Tree a -> Tree a
bal R x xh v l r = N R x xh v l r
bal B x xh v l r = balL x xh v l r

balL :: String -> Int -> Maybe a -> Tree a -> Tree a -> Tree a
balL x xh v l r = case l of
  N R lx lxh lv ll lr -> case ll of
    N R llx llxh llv lll llr ->
      N R lx lxh lv
        (N B llx llxh llv lll llr)
        (N B x xh v lr r)
    _ -> case lr of
      N R lrx lrxh lrv lrl lrr ->
        N R lrx lrxh lrv
          (N B lx lxh lv ll lrl)
          (N B x xh v lrr r)
      _ -> balR x xh v l r
  _ -> balR x xh v l r

balR :: String -> Int -> Maybe a -> Tree a -> Tree a -> Tree a
balR x xh v l r = case r of
  N R rx rxh rv rl rr -> case rl of
    N R rlx rlxh rlv rll rlr ->
      N R rlx rlxh rlv
        (N B x xh v l rll)
        (N B rx rxh rv rlr rr)
    _ -> case rr of
      N R rrx rrxh rrv rrl rrr ->
        N R rx rxh rv
          (N B x xh v l rl)
          (N B rrx rrxh rrv rrl rrr)
      _ -> N B x xh v l r
  _ -> N B x xh v l r

hash :: String -> Int
hash s = go 5381 s where
  go h [] = h
  go h (c:cs) = go (((h * 33) + fromEnum c) `mod` 2147483647) cs

cmpHash :: String -> Int -> String -> Int -> Cmp
cmpHash l lh r rh =
  if lh < rh
  then Lt
  else if lh > rh
       then Gt
       else cmpString l r

data Cmp
  = Lt
  | Eq
  | Gt

cmpString :: String -> String -> Cmp
cmpString [] [] = Eq
cmpString [] _ = Lt
cmpString _ [] = Gt
cmpString (a:as) (b:bs) =
  if a < b
  then Lt
  else if a > b
  then Gt
  else cmpString as bs
