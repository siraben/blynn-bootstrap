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
  | N Color String (Maybe a) (Tree a) (Tree a)

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
symbolMapMember k m = maybe False (const True) (symbolMapLookup k m)

symbolSetFromList :: [String] -> SymbolSet
symbolSetFromList = foldr symbolSetInsert symbolSetEmpty

symbolSetMember :: String -> SymbolSet -> Bool
symbolSetMember k (SymbolSet t) = maybe False (const True) (lookupT k t)

symbolSetInsert :: String -> SymbolSet -> SymbolSet
symbolSetInsert k (SymbolSet t) = SymbolSet (insertT k () t)

symbolSetDelete :: String -> SymbolSet -> SymbolSet
symbolSetDelete k (SymbolSet t) = SymbolSet (deleteT k t)

lookupT :: String -> Tree a -> Maybe a
lookupT _ E = Nothing
lookupT k (N _ x v l r) = case cmpString k x of
  Lt -> lookupT k l
  Eq -> v
  Gt -> lookupT k r

insertT :: String -> a -> Tree a -> Tree a
insertT k v = alterT k (Just v)

deleteT :: String -> Tree a -> Tree a
deleteT k = alterT k Nothing

alterT :: String -> Maybe a -> Tree a -> Tree a
alterT k v t = blacken (go t) where
  go u = case u of
    E -> N R k v E E
    N c x old l r -> case cmpString k x of
      Lt -> bal c x old (go l) r
      Eq -> N c k v l r
      Gt -> bal c x old l (go r)

blacken :: Tree a -> Tree a
blacken E = E
blacken (N _ x v l r) = N B x v l r

bal :: Color -> String -> Maybe a -> Tree a -> Tree a -> Tree a
bal R x v l r = N R x v l r
bal B x v l r = balL x v l r

balL :: String -> Maybe a -> Tree a -> Tree a -> Tree a
balL x v l r = case l of
  N R lx lv ll lr -> case ll of
    N R llx llv lll llr ->
      N R lx lv
        (N B llx llv lll llr)
        (N B x v lr r)
    _ -> case lr of
      N R lrx lrv lrl lrr ->
        N R lrx lrv
          (N B lx lv ll lrl)
          (N B x v lrr r)
      _ -> balR x v l r
  _ -> balR x v l r

balR :: String -> Maybe a -> Tree a -> Tree a -> Tree a
balR x v l r = case r of
  N R rx rv rl rr -> case rl of
    N R rlx rlv rll rlr ->
      N R rlx rlv
        (N B x v l rll)
        (N B rx rv rlr rr)
    _ -> case rr of
      N R rrx rrv rrl rrr ->
        N R rx rv
          (N B x v l rl)
          (N B rrx rrv rrl rrr)
      _ -> N B x v l r
  _ -> N B x v l r

data Cmp
  = Lt
  | Eq
  | Gt

cmpString :: String -> String -> Cmp
cmpString [] [] = Eq
cmpString [] _ = Lt
cmpString _ [] = Gt
cmpString (a:as) (b:bs)
  | a < b = Lt
  | a > b = Gt
  | otherwise = cmpString as bs
