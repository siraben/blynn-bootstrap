module SymbolTable where

import Base

data Color = Red | Black

data Tree a
  = Empty
  | Branch Color String Int (Maybe a) (Tree a) (Tree a)

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
treeLookup key tree = treeLookupHashed key (stringHash key) tree

treeLookupHashed :: String -> Int -> Tree a -> Maybe a
treeLookupHashed key keyHash tree = case tree of
  Empty -> Nothing
  Branch _ name nameHash value left right -> case compareHashedString key keyHash name nameHash of
    IsLess -> treeLookupHashed key keyHash left
    IsEqual -> value
    IsGreater -> treeLookupHashed key keyHash right

treeInsert :: String -> a -> Tree a -> Tree a
treeInsert key value tree = treeInsertValue key (Just value) tree

treeDelete :: String -> Tree a -> Tree a
treeDelete key tree = treeInsertValue key Nothing tree

treeInsertValue :: String -> Maybe a -> Tree a -> Tree a
treeInsertValue key value tree = blacken (insert (stringHash key) tree) where
  insert keyHash current = case current of
    Empty -> Branch Red key keyHash value Empty Empty
    Branch color name nameHash old left right -> case compareHashedString key keyHash name nameHash of
      IsLess -> balance color name nameHash old (insert keyHash left) right
      IsEqual -> Branch color key keyHash value left right
      IsGreater -> balance color name nameHash old left (insert keyHash right)

blacken :: Tree a -> Tree a
blacken tree = case tree of
  Empty -> Empty
  Branch _ name nameHash value left right -> Branch Black name nameHash value left right

balance :: Color -> String -> Int -> Maybe a -> Tree a -> Tree a -> Tree a
balance color name nameHash value left right = case color of
  Red -> Branch Red name nameHash value left right
  Black -> balanceBlack name nameHash value left right

balanceBlack :: String -> Int -> Maybe a -> Tree a -> Tree a -> Tree a
balanceBlack name nameHash value left right = case left of
  Branch Red lname lnameHash lvalue lleft lright -> case lleft of
    Branch Red llname llnameHash llvalue llleft llright ->
      Branch Red lname lnameHash lvalue
        (Branch Black llname llnameHash llvalue llleft llright)
        (Branch Black name nameHash value lright right)
    _ -> case lright of
      Branch Red lrname lrnameHash lrvalue lrleft lrright ->
        Branch Red lrname lrnameHash lrvalue
          (Branch Black lname lnameHash lvalue lleft lrleft)
          (Branch Black name nameHash value lrright right)
      _ -> balanceBlackRight name nameHash value left right
  _ -> balanceBlackRight name nameHash value left right

balanceBlackRight :: String -> Int -> Maybe a -> Tree a -> Tree a -> Tree a
balanceBlackRight name nameHash value left right = case right of
  Branch Red rname rnameHash rvalue rleft rright -> case rleft of
    Branch Red rlname rlnameHash rlvalue rlleft rlright ->
      Branch Red rlname rlnameHash rlvalue
        (Branch Black name nameHash value left rlleft)
        (Branch Black rname rnameHash rvalue rlright rright)
    _ -> case rright of
      Branch Red rrname rrnameHash rrvalue rrleft rrright ->
        Branch Red rname rnameHash rvalue
          (Branch Black name nameHash value left rleft)
          (Branch Black rrname rrnameHash rrvalue rrleft rrright)
      _ -> Branch Black name nameHash value left right
  _ -> Branch Black name nameHash value left right

stringHash :: String -> Int
stringHash text = go 5381 text where
  go hash chars = case chars of
    [] -> hash
    c:rest -> go (((hash * 33) + fromEnum c) `mod` 2147483647) rest

compareHashedString :: String -> Int -> String -> Int -> Comparison
compareHashedString left leftHash right rightHash =
  if leftHash < rightHash
  then IsLess
  else if leftHash > rightHash
       then IsGreater
       else compareString left right

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
