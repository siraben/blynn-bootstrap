module IfFrame
  ( IfFrame(..)
  , IfDirective(..)
  , ifStackActive
  , pushIfFrame
  , applyIfDirective
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

data IfDirective
  = IfCondition Bool
  | ElifCondition Bool
  | ElseCondition
  | EndifCondition

ifStackActive :: [IfFrame] -> Bool
ifStackActive [] = True
ifStackActive (frame:_) = ifActive frame

applyIfDirective :: [IfFrame] -> IfDirective -> Maybe [IfFrame]
applyIfDirective frames directive = case directive of
  IfCondition cond -> Just (pushIfFrame frames cond)
  ElifCondition cond -> replaceElifFrame frames cond
  ElseCondition -> replaceElseFrame frames
  EndifCondition -> popIfFrame frames

pushIfFrame :: [IfFrame] -> Bool -> [IfFrame]
pushIfFrame frames cond =
  let parent = ifStackActive frames
      active = parent && cond
  in IfFrame parent active active : frames

replaceElifFrame :: [IfFrame] -> Bool -> Maybe [IfFrame]
replaceElifFrame [] _ = Nothing
replaceElifFrame (frame:rest) cond =
  let active = ifParent frame && not (ifTaken frame) && cond
      taken = ifTaken frame || active
  in Just (frame { ifTaken = taken, ifActive = active } : rest)

replaceElseFrame :: [IfFrame] -> Maybe [IfFrame]
replaceElseFrame [] = Nothing
replaceElseFrame (frame:rest) =
  let active = ifParent frame && not (ifTaken frame)
  in Just (frame { ifTaken = True, ifActive = active } : rest)

popIfFrame :: [IfFrame] -> Maybe [IfFrame]
popIfFrame [] = Nothing
popIfFrame (_:rest) = Just rest
