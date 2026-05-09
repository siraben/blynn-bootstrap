module IntTable where

import Base

data IntColor = IntRed | IntBlack

data IntTree a
  = IntEmpty
  | IntBranch IntColor Int a (IntTree a) (IntTree a)

data IntMap a = IntMap (IntTree a)

intMapEmpty :: IntMap a
intMapEmpty = IntMap IntEmpty

intMapLookup :: Int -> IntMap a -> Maybe a
intMapLookup key (IntMap tree) = intTreeLookup key tree

intMapInsert :: Int -> a -> IntMap a -> IntMap a
intMapInsert key value (IntMap tree) = IntMap (intTreeInsert key value tree)

intMapMember :: Int -> IntMap a -> Bool
intMapMember key table = case intMapLookup key table of
  Just _ -> True
  Nothing -> False

intTreeLookup :: Int -> IntTree a -> Maybe a
intTreeLookup key tree = case tree of
  IntEmpty -> Nothing
  IntBranch _ nodeKey value left right ->
    if key < nodeKey
    then intTreeLookup key left
    else if key > nodeKey
         then intTreeLookup key right
         else Just value

intTreeInsert :: Int -> a -> IntTree a -> IntTree a
intTreeInsert key value tree = intBlacken (insert tree) where
  insert current = case current of
    IntEmpty -> IntBranch IntRed key value IntEmpty IntEmpty
    IntBranch color nodeKey old left right ->
      if key < nodeKey
      then intBalance color nodeKey old (insert left) right
      else if key > nodeKey
           then intBalance color nodeKey old left (insert right)
           else IntBranch color key value left right

intBlacken :: IntTree a -> IntTree a
intBlacken tree = case tree of
  IntEmpty -> IntEmpty
  IntBranch _ key value left right -> IntBranch IntBlack key value left right

intBalance :: IntColor -> Int -> a -> IntTree a -> IntTree a -> IntTree a
intBalance color key value left right = case color of
  IntRed -> IntBranch IntRed key value left right
  IntBlack -> intBalanceBlack key value left right

intBalanceBlack :: Int -> a -> IntTree a -> IntTree a -> IntTree a
intBalanceBlack key value left right = case left of
  IntBranch IntRed lkey lvalue lleft lright -> case lleft of
    IntBranch IntRed llkey llvalue llleft llright ->
      IntBranch IntRed lkey lvalue
        (IntBranch IntBlack llkey llvalue llleft llright)
        (IntBranch IntBlack key value lright right)
    _ -> case lright of
      IntBranch IntRed lrkey lrvalue lrleft lrright ->
        IntBranch IntRed lrkey lrvalue
          (IntBranch IntBlack lkey lvalue lleft lrleft)
          (IntBranch IntBlack key value lrright right)
      _ -> intBalanceBlackRight key value left right
  _ -> intBalanceBlackRight key value left right

intBalanceBlackRight :: Int -> a -> IntTree a -> IntTree a -> IntTree a
intBalanceBlackRight key value left right = case right of
  IntBranch IntRed rkey rvalue rleft rright -> case rleft of
    IntBranch IntRed rlkey rlvalue rlleft rlright ->
      IntBranch IntRed rlkey rlvalue
        (IntBranch IntBlack key value left rlleft)
        (IntBranch IntBlack rkey rvalue rlright rright)
    _ -> case rright of
      IntBranch IntRed rrkey rrvalue rrleft rrright ->
        IntBranch IntRed rkey rvalue
          (IntBranch IntBlack key value left rleft)
          (IntBranch IntBlack rrkey rrvalue rrleft rrright)
      _ -> IntBranch IntBlack key value left right
  _ -> IntBranch IntBlack key value left right
