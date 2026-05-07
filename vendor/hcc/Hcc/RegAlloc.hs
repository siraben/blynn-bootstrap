module Hcc.RegAlloc
  ( Allocation
  , Location(..)
  , PhysReg(..)
  , allocateFunction
  , lookupLocation
  , stackSlotCount
  ) where

import qualified Data.Map.Strict as Map

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

data Allocation = Allocation Int (Map.Map Temp Location)
  deriving (Eq, Show)

allocateFunction :: FunctionIr -> Either String Allocation
allocateFunction (FunctionIr _ _ blocks) =
  uncurry Allocation <$> allocateInstrs 0 Map.empty (concatMap blockInstrs blocks)

lookupLocation :: Temp -> Allocation -> Either String Location
lookupLocation temp (Allocation _ locations) = case Map.lookup temp locations of
  Just loc -> Right loc
  Nothing -> Left ("missing allocation for " ++ show temp)

stackSlotCount :: Allocation -> Int
stackSlotCount (Allocation slots _) = slots

allocateInstrs :: Int -> Map.Map Temp Location -> [Instr] -> Either String (Int, Map.Map Temp Location)
allocateInstrs nextSlot acc instrs = case instrs of
  [] -> Right (nextSlot, acc)
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
    ILoadS32 temp _ ->
      allocateDef nextSlot acc temp rest
    ILoad16 temp _ ->
      allocateDef nextSlot acc temp rest
    ILoadS16 temp _ ->
      allocateDef nextSlot acc temp rest
    ILoad8 temp _ ->
      allocateDef nextSlot acc temp rest
    ILoadS8 temp _ ->
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
    ICond temp condInstrs _ trueInstrs _ falseInstrs _ ->
      allocateInstrs nextSlot acc (condInstrs ++ trueInstrs ++ falseInstrs ++ [IConst temp 0] ++ rest)
    ICall Nothing _ _ ->
      allocateInstrs nextSlot acc rest
    ICall (Just temp) _ _ ->
      allocateDef nextSlot acc temp rest
    ICallIndirect Nothing _ _ ->
      allocateInstrs nextSlot acc rest
    ICallIndirect (Just temp) _ _ ->
      allocateDef nextSlot acc temp rest

allocateStackObject :: Int -> Map.Map Temp Location -> Temp -> Int -> [Instr] -> Either String (Int, Map.Map Temp Location)
allocateStackObject nextSlot acc temp size rest =
  if Map.member temp acc
  then allocateInstrs nextSlot acc rest
  else
    let slots = (max 1 size + 7) `div` 8
    in allocateInstrs (nextSlot + slots) (Map.insert temp (StackObject nextSlot slots) acc) rest

allocateDef :: Int -> Map.Map Temp Location -> Temp -> [Instr] -> Either String (Int, Map.Map Temp Location)
allocateDef nextSlot acc temp rest =
  if Map.member temp acc
  then allocateInstrs nextSlot acc rest
  else allocateInstrs (nextSlot + 1) (Map.insert temp (OnStack nextSlot) acc) rest

blockInstrs :: BasicBlock -> [Instr]
blockInstrs (BasicBlock _ instrs _) = instrs
