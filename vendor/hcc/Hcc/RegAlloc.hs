module Hcc.RegAlloc
  ( Allocation
  , Location(..)
  , PhysReg(..)
  , allocateFunction
  , lookupLocation
  , stackSlotCount
  ) where

import Hcc.Ir

data PhysReg
  = Rax
  | Rbx
  | Rdi
  | Rsi
  | Rdx
  deriving (Eq, Show)

data Location
  = InReg PhysReg
  | OnStack Int
  deriving (Eq, Show)

newtype Allocation = Allocation [(Temp, Location)]
  deriving (Eq, Show)

allocateFunction :: FunctionIr -> Either String Allocation
allocateFunction (FunctionIr _ _ blocks) =
  Allocation <$> allocateInstrs 0 [] (concatMap blockInstrs blocks)

lookupLocation :: Temp -> Allocation -> Either String Location
lookupLocation temp (Allocation pairs) = case lookup temp pairs of
  Just loc -> Right loc
  Nothing -> Left ("missing allocation for " ++ show temp)

stackSlotCount :: Allocation -> Int
stackSlotCount (Allocation pairs) = count pairs where
  count xs = case xs of
    [] -> 0
    (_, OnStack _):rest -> 1 + count rest
    _:rest -> count rest

allocateInstrs :: Int -> [(Temp, Location)] -> [Instr] -> Either String [(Temp, Location)]
allocateInstrs nextSlot acc instrs = case instrs of
  [] -> Right (reverse acc)
  instr:rest -> case instr of
    IParam temp index -> do
      loc <- paramLocation index
      allocateInstrs nextSlot ((temp, loc):acc) rest
    IConst temp _ ->
      allocateDef nextSlot acc temp rest
    ICopy temp _ ->
      allocateDef nextSlot acc temp rest
    ILoad8 temp _ ->
      allocateDef nextSlot acc temp rest
    IBin temp _ _ _ ->
      allocateDef nextSlot acc temp rest
    ICall Nothing _ _ ->
      allocateInstrs nextSlot acc rest
    ICall (Just temp) _ _ ->
      allocateDef nextSlot acc temp rest

allocateDef :: Int -> [(Temp, Location)] -> Temp -> [Instr] -> Either String [(Temp, Location)]
allocateDef nextSlot acc temp rest =
  if temp `elem` map fst acc
  then allocateInstrs nextSlot acc rest
  else allocateInstrs (nextSlot + 1) ((temp, OnStack nextSlot):acc) rest

paramLocation :: Int -> Either String Location
paramLocation index = case index of
  0 -> Right (InReg Rdi)
  1 -> Right (InReg Rsi)
  2 -> Right (InReg Rdx)
  _ -> Left ("unsupported parameter index: " ++ show index)

blockInstrs :: BasicBlock -> [Instr]
blockInstrs (BasicBlock _ instrs _) = instrs
