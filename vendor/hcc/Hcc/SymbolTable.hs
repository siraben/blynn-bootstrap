module SymbolTable
  ( SymbolMap
  , SymbolSet
  , symbolMapDelete
  , symbolMapEmpty
  , symbolMapInsert
  , symbolMapLookup
  , symbolMapMember
  , symbolSetDelete
  , symbolSetEmpty
  , symbolSetFromList
  , symbolSetInsert
  , symbolSetMember
  ) where

data Tree a
  = Empty
  | Branch String a (Tree a) (Tree a)
  deriving (Eq, Show)

data SymbolMap a = SymbolMap (Tree a)
  deriving (Eq, Show)

data SymbolSet = SymbolSet (Tree ())
  deriving (Eq, Show)

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
  Branch name value left right -> case compareString key name of
    IsLess -> treeLookup key left
    IsEqual -> Just value
    IsGreater -> treeLookup key right

treeInsert :: String -> a -> Tree a -> Tree a
treeInsert key value tree = case tree of
  Empty -> Branch key value Empty Empty
  Branch name old left right -> case compareString key name of
    IsLess -> Branch name old (treeInsert key value left) right
    IsEqual -> Branch key value left right
    IsGreater -> Branch name old left (treeInsert key value right)

treeDelete :: String -> Tree a -> Tree a
treeDelete key tree = case tree of
  Empty -> Empty
  Branch name value left right -> case compareString key name of
    IsLess -> Branch name value (treeDelete key left) right
    IsEqual -> mergeTrees left right
    IsGreater -> Branch name value left (treeDelete key right)

mergeTrees :: Tree a -> Tree a -> Tree a
mergeTrees left right = case (left, right) of
  (Empty, _) -> right
  (_, Empty) -> left
  _ ->
    let (name, value, right') = removeMin right
    in Branch name value left right'

removeMin :: Tree a -> (String, a, Tree a)
removeMin tree = case tree of
  Empty -> error "removeMin on empty tree"
  Branch name value Empty right -> (name, value, right)
  Branch name value left right ->
    let (minName, minValue, left') = removeMin left
    in (minName, minValue, Branch name value left' right)

data Comparison
  = IsLess
  | IsEqual
  | IsGreater
  deriving (Eq, Show)

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
