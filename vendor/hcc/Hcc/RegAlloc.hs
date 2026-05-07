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
  | StackObject Int Int
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
stackSlotCount (Allocation pairs) = count 0 pairs where
  count maxSlot locs = case locs of
    [] -> maxSlot
    (_, OnStack slot):rest -> count (max maxSlot (slot + 1)) rest
    (_, StackObject slot slots):rest -> count (max maxSlot (slot + slots)) rest
    _:rest -> count maxSlot rest

allocateInstrs :: Int -> [(Temp, Location)] -> [Instr] -> Either String [(Temp, Location)]
allocateInstrs nextSlot acc instrs = case instrs of
  [] -> Right (reverse acc)
  instr:rest -> case instr of
    IParam temp _ ->
      allocateDef nextSlot acc temp rest
    IAlloca temp size ->
      allocateStackObject nextSlot acc temp size rest
    IConst temp _ ->
      allocateDef nextSlot acc temp rest
    ICopy temp _ ->
      allocateDef nextSlot acc temp rest
    IAddrOf temp _ ->
      allocateDef nextSlot acc temp rest
    ILoad64 temp _ ->
      allocateDef nextSlot acc temp rest
    ILoad32 temp _ ->
      allocateDef nextSlot acc temp rest
    ILoad16 temp _ ->
      allocateDef nextSlot acc temp rest
    ILoad8 temp _ ->
      allocateDef nextSlot acc temp rest
    IStore64 _ _ ->
      allocateInstrs nextSlot acc rest
    IStore32 _ _ ->
      allocateInstrs nextSlot acc rest
    IStore16 _ _ ->
      allocateInstrs nextSlot acc rest
    IStore8 _ _ ->
      allocateInstrs nextSlot acc rest
    IBin temp _ _ _ ->
      allocateDef nextSlot acc temp rest
    ICall Nothing _ _ ->
      allocateInstrs nextSlot acc rest
    ICall (Just temp) _ _ ->
      allocateDef nextSlot acc temp rest
    ICallIndirect Nothing _ _ ->
      allocateInstrs nextSlot acc rest
    ICallIndirect (Just temp) _ _ ->
      allocateDef nextSlot acc temp rest

allocateStackObject :: Int -> [(Temp, Location)] -> Temp -> Int -> [Instr] -> Either String [(Temp, Location)]
allocateStackObject nextSlot acc temp size rest =
  if temp `elem` map fst acc
  then allocateInstrs nextSlot acc rest
  else
    let slots = (max 1 size + 7) `div` 8
    in allocateInstrs (nextSlot + slots) ((temp, StackObject nextSlot slots):acc) rest

allocateDef :: Int -> [(Temp, Location)] -> Temp -> [Instr] -> Either String [(Temp, Location)]
allocateDef nextSlot acc temp rest =
  if temp `elem` map fst acc
  then allocateInstrs nextSlot acc rest
  else allocateInstrs (nextSlot + 1) ((temp, OnStack nextSlot):acc) rest

blockInstrs :: BasicBlock -> [Instr]
blockInstrs (BasicBlock _ instrs _) = instrs
