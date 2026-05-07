module RegAlloc where

import Base
import FingerTree
import Ir

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

data Allocation = Allocation Int (FingerTree AllocationEntry)
  deriving (Eq, Show)

data AllocationEntry = AllocationEntry Temp Location
  deriving (Eq, Show)

allocateFunction :: FunctionIr -> Either String Allocation
allocateFunction (FunctionIr _ _ blocks) =
  uncurry Allocation <$> allocateInstrs 0 fingerEmpty (concatMap blockInstrs blocks)

lookupLocation :: Temp -> Allocation -> Either String Location
lookupLocation temp (Allocation _ locations) = case lookupEntry temp locations of
  Just loc -> Right loc
  Nothing -> Left ("missing allocation for " ++ show temp)

stackSlotCount :: Allocation -> Int
stackSlotCount (Allocation slots _) = slots

allocateInstrs :: Int -> FingerTree AllocationEntry -> [Instr] -> Either String (Int, FingerTree AllocationEntry)
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

allocateStackObject :: Int -> FingerTree AllocationEntry -> Temp -> Int -> [Instr] -> Either String (Int, FingerTree AllocationEntry)
allocateStackObject nextSlot acc temp size rest =
  if allocationMember temp acc
  then allocateInstrs nextSlot acc rest
  else
    let slots = (max 1 size + 7) `div` 8
    in allocateInstrs (nextSlot + slots) (insertEntry temp (StackObject nextSlot slots) acc) rest

allocateDef :: Int -> FingerTree AllocationEntry -> Temp -> [Instr] -> Either String (Int, FingerTree AllocationEntry)
allocateDef nextSlot acc temp rest =
  if allocationMember temp acc
  then allocateInstrs nextSlot acc rest
  else allocateInstrs (nextSlot + 1) (insertEntry temp (OnStack nextSlot) acc) rest

allocationMember :: Temp -> FingerTree AllocationEntry -> Bool
allocationMember temp entries = case lookupEntry temp entries of
  Just _ -> True
  Nothing -> False

insertEntry :: Temp -> Location -> FingerTree AllocationEntry -> FingerTree AllocationEntry
insertEntry temp loc entries =
  fingerSnoc entryRange entries (AllocationEntry temp loc)

lookupEntry :: Temp -> FingerTree AllocationEntry -> Maybe Location
lookupEntry temp@(Temp key) entries =
  fingerLookupWith entryRange (matchEntry temp) key entries

matchEntry :: Temp -> AllocationEntry -> Maybe Location
matchEntry temp entry = case entry of
  AllocationEntry entryTemp loc ->
    if entryTemp == temp
    then Just loc
    else Nothing

entryRange :: AllocationEntry -> FingerRange
entryRange entry = case entry of
  AllocationEntry (Temp key) _ -> FingerRange key key

blockInstrs :: BasicBlock -> [Instr]
blockInstrs (BasicBlock _ instrs _) = instrs
