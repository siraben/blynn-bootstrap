module IntTable where

import Base

data Color = R | B

data Tree a
  = E
  | N Color Int a (Tree a) (Tree a)

data IntMap a = IntMap (Tree a)

intMapEmpty :: IntMap a
intMapEmpty = IntMap E

intMapLookup :: Int -> IntMap a -> Maybe a
intMapLookup k (IntMap t) = lookupT k t

intMapInsert :: Int -> a -> IntMap a -> IntMap a
intMapInsert k v (IntMap t) = IntMap (insertT k v t)

lookupT :: Int -> Tree a -> Maybe a
lookupT k t = case t of
  E -> Nothing
  N _ x v l r ->
    if k < x
    then lookupT k l
    else if k > x
         then lookupT k r
         else Just v

insertT :: Int -> a -> Tree a -> Tree a
insertT k v t = blacken (go t) where
  go u = case u of
    E -> N R k v E E
    N c x old l r ->
      if k < x
      then bal c x old (go l) r
      else if k > x
           then bal c x old l (go r)
           else N c k v l r

blacken :: Tree a -> Tree a
blacken t = case t of
  E -> E
  N _ k v l r -> N B k v l r

bal :: Color -> Int -> a -> Tree a -> Tree a -> Tree a
bal c k v l r = case c of
  R -> N R k v l r
  B -> balL k v l r

balL :: Int -> a -> Tree a -> Tree a -> Tree a
balL k v l r = case l of
  N R lk lv ll lr -> case ll of
    N R llk llv lll llr ->
      N R lk lv
        (N B llk llv lll llr)
        (N B k v lr r)
    _ -> case lr of
      N R lrk lrv lrl lrr ->
        N R lrk lrv
          (N B lk lv ll lrl)
          (N B k v lrr r)
      _ -> balR k v l r
  _ -> balR k v l r

balR :: Int -> a -> Tree a -> Tree a -> Tree a
balR k v l r = case r of
  N R rk rv rl rr -> case rl of
    N R rlk rlv rll rlr ->
      N R rlk rlv
        (N B k v l rll)
        (N B rk rv rlr rr)
    _ -> case rr of
      N R rrk rrv rrl rrr ->
        N R rk rv
          (N B k v l rl)
          (N B rrk rrv rrl rrr)
      _ -> N B k v l r
  _ -> N B k v l r
