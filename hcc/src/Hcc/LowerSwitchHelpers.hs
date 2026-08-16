module LowerSwitchHelpers
  ( collectSwitchLabels
  , freshBlocks
  , switchDefaultTarget
  , switchCases
  ) where

import Base
import TypesAst
import CompileM
import TypesIr

collectSwitchLabels :: [Stmt] -> [Maybe Expr]
collectSwitchLabels stmts = concatMap collectSwitchLabelsStmt stmts

collectSwitchLabelsStmt :: Stmt -> [Maybe Expr]
collectSwitchLabelsStmt stmt = case stmt of
  SCase expr -> [Just expr]
  SDefault -> [Nothing]
  SBlock body -> collectSwitchLabels body
  SIf _ yes no -> collectSwitchLabels yes ++ collectSwitchLabels no
  SWhile _ body -> collectSwitchLabels body
  SDoWhile body _ -> collectSwitchLabels body
  SFor _ _ _ body -> collectSwitchLabels body
  SSwitch _ _ -> []
  _ -> []

freshBlocks :: Int -> CompileM [BlockId]
freshBlocks count =
  if count <= 0
    then pure []
    else do
      first <- freshBlock
      rest <- freshBlocks (count - 1)
      pure (first:rest)

switchDefaultTarget :: BlockId -> [(Maybe Expr, BlockId)] -> BlockId
switchDefaultTarget restId targets = case find isDefaultTarget targets of
  Nothing -> restId
  Just (_, bid) -> bid
  where
    isDefaultTarget (label, _) = case label of
      Nothing -> True
      Just _ -> False

switchCases :: [(Maybe Expr, BlockId)] -> [(Expr, BlockId)]
switchCases = foldr addCase []
  where
    addCase (label, bid) rest = case label of
      Just value -> (value, bid) : rest
      Nothing -> rest
