module SymbolTable where

import Base

data Color = Red | Black

data Tree a
  = Empty
  | Branch Color String (Maybe a) (Tree a) (Tree a)

data SymbolMap a = SymbolMap (Tree a)

data SymbolSet = SymbolSet (Tree ())

symbolMapEmpty :: SymbolMap a
symbolMapEmpty = SymbolMap Empty

symbolSetEmpty :: SymbolSet
symbolSetEmpty = SymbolSet Empty

symbolMapLookup :: String -> SymbolMap a -> Maybe a
symbolMapLookup key (SymbolMap tree) = treeLookup key tree

symbolMapInsert :: String -> a -> SymbolMap a -> SymbolMap a
symbolMapInsert key value (SymbolMap tree) = SymbolMap (treeInsert key value tree)

symbolMapDelete :: String -> SymbolMap a -> SymbolMap a
symbolMapDelete key (SymbolMap tree) = SymbolMap (treeDelete key tree)

symbolMapMember :: String -> SymbolMap a -> Bool
symbolMapMember key table = case symbolMapLookup key table of
  Just _ -> True
  Nothing -> False

symbolSetFromList :: [String] -> SymbolSet
symbolSetFromList names = case names of
  [] -> symbolSetEmpty
  name:rest -> symbolSetInsert name (symbolSetFromList rest)

symbolSetMember :: String -> SymbolSet -> Bool
symbolSetMember key (SymbolSet tree) = case treeLookup key tree of
  Just _ -> True
  Nothing -> False

symbolSetInsert :: String -> SymbolSet -> SymbolSet
symbolSetInsert key (SymbolSet tree) = SymbolSet (treeInsert key () tree)

symbolSetDelete :: String -> SymbolSet -> SymbolSet
symbolSetDelete key (SymbolSet tree) = SymbolSet (treeDelete key tree)

treeLookup :: String -> Tree a -> Maybe a
treeLookup key tree = case tree of
  Empty -> Nothing
  Branch _ name value left right -> case compareString key name of
    IsLess -> treeLookup key left
    IsEqual -> value
    IsGreater -> treeLookup key right

treeInsert :: String -> a -> Tree a -> Tree a
treeInsert key value tree = treeInsertValue key (Just value) tree

treeDelete :: String -> Tree a -> Tree a
treeDelete key tree = treeInsertValue key Nothing tree

treeInsertValue :: String -> Maybe a -> Tree a -> Tree a
treeInsertValue key value tree = blacken (insert tree) where
  insert current = case current of
    Empty -> Branch Red key value Empty Empty
    Branch color name old left right -> case compareString key name of
      IsLess -> balance color name old (insert left) right
      IsEqual -> Branch color key value left right
      IsGreater -> balance color name old left (insert right)

blacken :: Tree a -> Tree a
blacken tree = case tree of
  Empty -> Empty
  Branch _ name value left right -> Branch Black name value left right

balance :: Color -> String -> Maybe a -> Tree a -> Tree a -> Tree a
balance color name value left right = case color of
  Red -> Branch Red name value left right
  Black -> balanceBlack name value left right

balanceBlack :: String -> Maybe a -> Tree a -> Tree a -> Tree a
balanceBlack name value left right = case left of
  Branch Red lname lvalue lleft lright -> case lleft of
    Branch Red llname llvalue llleft llright ->
      Branch Red lname lvalue
        (Branch Black llname llvalue llleft llright)
        (Branch Black name value lright right)
    _ -> case lright of
      Branch Red lrname lrvalue lrleft lrright ->
        Branch Red lrname lrvalue
          (Branch Black lname lvalue lleft lrleft)
          (Branch Black name value lrright right)
      _ -> balanceBlackRight name value left right
  _ -> balanceBlackRight name value left right

balanceBlackRight :: String -> Maybe a -> Tree a -> Tree a -> Tree a
balanceBlackRight name value left right = case right of
  Branch Red rname rvalue rleft rright -> case rleft of
    Branch Red rlname rlvalue rlleft rlright ->
      Branch Red rlname rlvalue
        (Branch Black name value left rlleft)
        (Branch Black rname rvalue rlright rright)
    _ -> case rright of
      Branch Red rrname rrvalue rrleft rrright ->
        Branch Red rname rvalue
          (Branch Black name value left rleft)
          (Branch Black rrname rrvalue rrleft rrright)
      _ -> Branch Black name value left right
  _ -> Branch Black name value left right

data Comparison
  = IsLess
  | IsEqual
  | IsGreater

compareString :: String -> String -> Comparison
compareString left right = case (left, right) of
  ([], []) -> IsEqual
  ([], _) -> IsLess
  (_, []) -> IsGreater
  (a:as, b:bs) ->
    if a < b
    then IsLess
    else if a > b
    then IsGreater
    else compareString as bs
