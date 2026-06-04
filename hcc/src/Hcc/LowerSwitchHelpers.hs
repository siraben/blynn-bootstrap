module LowerSwitchHelpers
  ( collectSwitchClauses
  , freshBlocks
  , switchDefaultTarget
  , switchCases
  , switchNextDispatchTarget
  , switchFallthroughTarget
  ) where

import Base
import TypesAst
import CompileM
import TypesIr
import TypesLower

collectSwitchClauses :: [Stmt] -> [SwitchClause]
collectSwitchClauses stmts =
  reverse (collectSwitchClausesFinish Nothing [] [] stmts)

collectSwitchClausesFinish :: Maybe (Maybe Expr) -> [Stmt] -> [SwitchClause] -> [Stmt] -> [SwitchClause]
collectSwitchClausesFinish currentLabel currentBody clauses stmts = case stmts of
  [] -> collectSwitchClauseFinishOne currentLabel currentBody clauses
  stmt:rest -> case stmt of
    SCase expr ->
      collectSwitchClausesFinish (Just (Just expr)) [] (collectSwitchClauseFinishOne currentLabel currentBody clauses) rest
    SDefault ->
      collectSwitchClausesFinish (Just Nothing) [] (collectSwitchClauseFinishOne currentLabel currentBody clauses) rest
    _ -> case currentLabel of
      Nothing ->
        collectSwitchClausesFinish currentLabel currentBody clauses rest
      Just _ ->
        collectSwitchClausesFinish currentLabel (stmt:currentBody) clauses rest

collectSwitchClauseFinishOne :: Maybe (Maybe Expr) -> [Stmt] -> [SwitchClause] -> [SwitchClause]
collectSwitchClauseFinishOne currentLabel currentBody clauses = case currentLabel of
  Nothing -> clauses
  Just label -> SwitchClause label (reverse currentBody) : clauses

freshBlocks :: Int -> CompileM [BlockId]
freshBlocks count =
  if count <= 0
    then pure []
    else do
      first <- freshBlock
      rest <- freshBlocks (count - 1)
      pure (first:rest)

switchDefaultTarget :: BlockId -> [(SwitchClause, BlockId)] -> BlockId
switchDefaultTarget restId clauses = case find isDefaultClause clauses of
  Nothing -> restId
  Just (_, bid) -> bid
  where
    isDefaultClause (SwitchClause label _, _) = case label of
      Nothing -> True
      Just _ -> False

switchCases :: [(SwitchClause, BlockId)] -> [(Expr, BlockId)]
switchCases = foldr addCase []
  where
    addCase (SwitchClause label _, bid) rest = case label of
      Just value -> (value, bid) : rest
      Nothing -> rest

switchNextDispatchTarget :: BlockId -> [(Expr, BlockId)] -> CompileM BlockId
switchNextDispatchTarget defaultTarget tailCases = case tailCases of
  [] -> pure defaultTarget
  _ -> freshBlock

switchFallthroughTarget :: BlockId -> [(SwitchClause, BlockId)] -> BlockId
switchFallthroughTarget restId [] = restId
switchFallthroughTarget _ ((_, nextId):_) = nextId
