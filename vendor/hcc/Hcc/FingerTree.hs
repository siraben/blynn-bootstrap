module FingerTree where

data FingerRange = FingerRange Int Int
  deriving (Eq, Show)

data FingerTree a
  = Empty
  | Single a
  | Deep FingerRange (Digit a) (FingerTree (Node a)) (Digit a)
  deriving (Eq, Show)

data Digit a
  = One a
  | Two a a
  | Three a a a
  | Four a a a a
  deriving (Eq, Show)

data Node a = Node3 FingerRange a a a
  deriving (Eq, Show)

fingerEmpty :: FingerTree a
fingerEmpty = Empty

fingerSnoc :: (a -> FingerRange) -> FingerTree a -> a -> FingerTree a
fingerSnoc measure tree value = case tree of
  Empty -> Single value
  Single one -> deep measure (One one) Empty (One value)
  Deep _ prefix middle suffix -> case suffix of
    One a -> deep measure prefix middle (Two a value)
    Two a b -> deep measure prefix middle (Three a b value)
    Three a b c -> deep measure prefix middle (Four a b c value)
    Four a b c d ->
      deep measure prefix (fingerSnoc nodeRange middle (node3 measure a b c)) (Two d value)

fingerLookupWith :: (a -> FingerRange) -> (a -> Maybe b) -> Int -> FingerTree a -> Maybe b
fingerLookupWith measure accept key tree = case tree of
  Empty -> Nothing
  Single value ->
    if rangeContains key (measure value)
    then accept value
    else Nothing
  Deep range prefix middle suffix ->
    if rangeContains key range
    then firstJust
      [ lookupDigitWith measure accept key prefix
      , fingerLookupWith nodeRange (lookupNodeWith measure accept key) key middle
      , lookupDigitWith measure accept key suffix
      ]
    else Nothing

lookupDigitWith :: (a -> FingerRange) -> (a -> Maybe b) -> Int -> Digit a -> Maybe b
lookupDigitWith measure accept key digit = case digit of
  One a -> lookupValue measure accept key a
  Two a b -> firstJust [lookupValue measure accept key a, lookupValue measure accept key b]
  Three a b c -> firstJust [lookupValue measure accept key a, lookupValue measure accept key b, lookupValue measure accept key c]
  Four a b c d -> firstJust [lookupValue measure accept key a, lookupValue measure accept key b, lookupValue measure accept key c, lookupValue measure accept key d]

lookupNodeWith :: (a -> FingerRange) -> (a -> Maybe b) -> Int -> Node a -> Maybe b
lookupNodeWith measure accept key node = case node of
  Node3 _ a b c ->
    firstJust [lookupValue measure accept key a, lookupValue measure accept key b, lookupValue measure accept key c]

lookupValue :: (a -> FingerRange) -> (a -> Maybe b) -> Int -> a -> Maybe b
lookupValue measure accept key value =
  if rangeContains key (measure value)
  then accept value
  else Nothing

deep :: (a -> FingerRange) -> Digit a -> FingerTree (Node a) -> Digit a -> FingerTree a
deep measure prefix middle suffix =
  Deep (treeRange measure prefix middle suffix) prefix middle suffix

treeRange :: (a -> FingerRange) -> Digit a -> FingerTree (Node a) -> Digit a -> FingerRange
treeRange measure prefix middle suffix =
  rangeUnions (digitRange measure prefix) (middleRanges ++ [digitRange measure suffix])
  where
    middleRanges = case fingerRange nodeRange middle of
      Nothing -> []
      Just range -> [range]

fingerRange :: (a -> FingerRange) -> FingerTree a -> Maybe FingerRange
fingerRange measure tree = case tree of
  Empty -> Nothing
  Single value -> Just (measure value)
  Deep range _ _ _ -> Just range

digitRange :: (a -> FingerRange) -> Digit a -> FingerRange
digitRange measure digit = case digit of
  One a -> measure a
  Two a b -> rangeUnion (measure a) (measure b)
  Three a b c -> rangeUnions (measure a) [measure b, measure c]
  Four a b c d -> rangeUnions (measure a) [measure b, measure c, measure d]

node3 :: (a -> FingerRange) -> a -> a -> a -> Node a
node3 measure a b c =
  Node3 (rangeUnions (measure a) [measure b, measure c]) a b c

nodeRange :: Node a -> FingerRange
nodeRange node = case node of
  Node3 range _ _ _ -> range

rangeContains :: Int -> FingerRange -> Bool
rangeContains key (FingerRange lo hi) = key >= lo && key <= hi

rangeUnion :: FingerRange -> FingerRange -> FingerRange
rangeUnion (FingerRange alo ahi) (FingerRange blo bhi) =
  FingerRange (min alo blo) (max ahi bhi)

rangeUnions :: FingerRange -> [FingerRange] -> FingerRange
rangeUnions range ranges = case ranges of
  [] -> range
  r:rest -> rangeUnions (rangeUnion range r) rest

firstJust :: [Maybe a] -> Maybe a
firstJust choices = case choices of
  [] -> Nothing
  Nothing:rest -> firstJust rest
  Just value:_ -> Just value
