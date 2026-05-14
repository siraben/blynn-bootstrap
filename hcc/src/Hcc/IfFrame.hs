-- Shared #if / #ifdef / #ifndef / #elif / #else / #endif state machine.
-- Each conditional group is one IfFrame on a stack:
--   ifParent: was the enclosing group already active when we entered?
--   ifTaken : has any prior arm of this group been selected?
--   ifActive: is this arm currently expanding (parent active and condition holds)?
-- Both the textual include-expansion pass and the token preprocessor share
-- this layout so a divergence between the two cannot silently include the
-- wrong code on one path and not the other.
module IfFrame
  ( IfFrame(..)
  , ifStackActive
  , pushIfFrame
  , replaceElifFrame
  , replaceElseFrame
  , popIfFrame
  ) where

import Base

data IfFrame = IfFrame
  { ifParent :: Bool
  , ifTaken :: Bool
  , ifActive :: Bool
  }

ifStackActive :: [IfFrame] -> Bool
ifStackActive frames = case frames of
  [] -> True
  frame:_ -> ifActive frame

pushIfFrame :: [IfFrame] -> Bool -> [IfFrame]
pushIfFrame frames cond =
  let parent = ifStackActive frames
      active = parent && cond
  in IfFrame parent active active : frames

replaceElifFrame :: [IfFrame] -> Bool -> Maybe [IfFrame]
replaceElifFrame frames cond = case frames of
  [] -> Nothing
  frame:rest ->
    let active = ifParent frame && not (ifTaken frame) && cond
        taken = ifTaken frame || active
    in Just (frame { ifTaken = taken, ifActive = active } : rest)

replaceElseFrame :: [IfFrame] -> Maybe [IfFrame]
replaceElseFrame frames = case frames of
  [] -> Nothing
  frame:rest ->
    let active = ifParent frame && not (ifTaken frame)
    in Just (frame { ifTaken = True, ifActive = active } : rest)

popIfFrame :: [IfFrame] -> Maybe [IfFrame]
popIfFrame frames = case frames of
  [] -> Nothing
  _:rest -> Just rest
