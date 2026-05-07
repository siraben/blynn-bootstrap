module Hcc.FingerTree
  ( FingerTree
  , Range(..)
  , empty
  , lookupWith
  , snoc
  ) where

import Prelude hiding (lookup)

data Range = Range Int Int
  deriving (Eq, Show)

data FingerTree a
  = Empty
  | Single a
  | Deep Range (Digit a) (FingerTree (Node a)) (Digit a)
  deriving (Eq, Show)

data Digit a
  = One a
  | Two a a
  | Three a a a
  | Four a a a a
  deriving (Eq, Show)

data Node a = Node3 Range a a a
  deriving (Eq, Show)

empty :: FingerTree a
empty = Empty

snoc :: (a -> Range) -> FingerTree a -> a -> FingerTree a
snoc measure tree value = case tree of
  Empty -> Single value
  Single one -> deep measure (One one) Empty (One value)
  Deep _ prefix middle suffix -> case suffix of
    One a -> deep measure prefix middle (Two a value)
    Two a b -> deep measure prefix middle (Three a b value)
    Three a b c -> deep measure prefix middle (Four a b c value)
    Four a b c d ->
      deep measure prefix (snoc nodeRange middle (node3 measure a b c)) (Two d value)

lookupWith :: (a -> Range) -> (a -> Maybe b) -> Int -> FingerTree a -> Maybe b
lookupWith measure accept key tree = case tree of
  Empty -> Nothing
  Single value ->
    if rangeContains key (measure value)
    then accept value
    else Nothing
  Deep range prefix middle suffix ->
    if rangeContains key range
    then firstJust
      [ lookupDigitWith measure accept key prefix
      , lookupWith nodeRange (lookupNodeWith measure accept key) key middle
      , lookupDigitWith measure accept key suffix
      ]
    else Nothing

lookupDigitWith :: (a -> Range) -> (a -> Maybe b) -> Int -> Digit a -> Maybe b
lookupDigitWith measure accept key digit = case digit of
  One a -> lookupValue measure accept key a
  Two a b -> firstJust [lookupValue measure accept key a, lookupValue measure accept key b]
  Three a b c -> firstJust [lookupValue measure accept key a, lookupValue measure accept key b, lookupValue measure accept key c]
  Four a b c d -> firstJust [lookupValue measure accept key a, lookupValue measure accept key b, lookupValue measure accept key c, lookupValue measure accept key d]

lookupNodeWith :: (a -> Range) -> (a -> Maybe b) -> Int -> Node a -> Maybe b
lookupNodeWith measure accept key node = case node of
  Node3 _ a b c ->
    firstJust [lookupValue measure accept key a, lookupValue measure accept key b, lookupValue measure accept key c]

lookupValue :: (a -> Range) -> (a -> Maybe b) -> Int -> a -> Maybe b
lookupValue measure accept key value =
  if rangeContains key (measure value)
  then accept value
  else Nothing

deep :: (a -> Range) -> Digit a -> FingerTree (Node a) -> Digit a -> FingerTree a
deep measure prefix middle suffix =
  Deep (treeRange measure prefix middle suffix) prefix middle suffix

treeRange :: (a -> Range) -> Digit a -> FingerTree (Node a) -> Digit a -> Range
treeRange measure prefix middle suffix =
  rangeUnions (digitRange measure prefix) (middleRanges ++ [digitRange measure suffix])
  where
    middleRanges = case fingerRange nodeRange middle of
      Nothing -> []
      Just range -> [range]

fingerRange :: (a -> Range) -> FingerTree a -> Maybe Range
fingerRange measure tree = case tree of
  Empty -> Nothing
  Single value -> Just (measure value)
  Deep range _ _ _ -> Just range

digitRange :: (a -> Range) -> Digit a -> Range
digitRange measure digit = case digit of
  One a -> measure a
  Two a b -> rangeUnion (measure a) (measure b)
  Three a b c -> rangeUnions (measure a) [measure b, measure c]
  Four a b c d -> rangeUnions (measure a) [measure b, measure c, measure d]

node3 :: (a -> Range) -> a -> a -> a -> Node a
node3 measure a b c =
  Node3 (rangeUnions (measure a) [measure b, measure c]) a b c

nodeRange :: Node a -> Range
nodeRange node = case node of
  Node3 range _ _ _ -> range

rangeContains :: Int -> Range -> Bool
rangeContains key (Range lo hi) = key >= lo && key <= hi

rangeUnion :: Range -> Range -> Range
rangeUnion (Range alo ahi) (Range blo bhi) =
  Range (min alo blo) (max ahi bhi)

rangeUnions :: Range -> [Range] -> Range
rangeUnions range ranges = case ranges of
  [] -> range
  r:rest -> rangeUnions (rangeUnion range r) rest

firstJust :: [Maybe a] -> Maybe a
firstJust choices = case choices of
  [] -> Nothing
  Nothing:rest -> firstJust rest
  Just value:_ -> Just value
