module LowerSwitchHelpers where

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
        collectSwitchClausesFinish currentLabel (currentBody ++ [stmt]) clauses rest

collectSwitchClauseFinishOne :: Maybe (Maybe Expr) -> [Stmt] -> [SwitchClause] -> [SwitchClause]
collectSwitchClauseFinishOne currentLabel currentBody clauses = case currentLabel of
  Nothing -> clauses
  Just label -> SwitchClause label currentBody : clauses

freshBlocks :: Int -> CompileM [BlockId]
freshBlocks count =
  if count <= 0
    then pure []
    else do
      first <- freshBlock
      rest <- freshBlocks (count - 1)
      pure (first:rest)

switchDefaultTarget :: BlockId -> [(SwitchClause, BlockId)] -> BlockId
switchDefaultTarget restId clauses = case clauses of
  [] -> restId
  pair:rest -> case pair of
    (SwitchClause label _, bid) -> case label of
      Nothing -> bid
      Just _ -> switchDefaultTarget restId rest

switchCases :: [(SwitchClause, BlockId)] -> [(Expr, BlockId)]
switchCases clauses = case clauses of
  [] -> []
  pair:rest -> case pair of
    (SwitchClause label _, bid) -> case label of
      Just value -> (value, bid) : switchCases rest
      Nothing -> switchCases rest

switchNextDispatchTarget :: BlockId -> [(Expr, BlockId)] -> CompileM BlockId
switchNextDispatchTarget defaultTarget tailCases = case tailCases of
  [] -> pure defaultTarget
  _ -> freshBlock

switchFallthroughTarget :: BlockId -> [(SwitchClause, BlockId)] -> BlockId
switchFallthroughTarget restId clauses = case clauses of
  [] -> restId
  pair:_ -> case pair of
    (_, nextId) -> nextId
