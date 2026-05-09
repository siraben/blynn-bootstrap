module RegAlloc where

import Base
import IntTable
import Ir

data PhysReg
  = Rax
  | Rbx
  | Rdi
  | Rsi
  | Rdx

data Location
  = InReg PhysReg
  | OnStack Int
  | StackObject Int Int

data LocationChunk = LocationChunk (Maybe Location) (Maybe Location)

data LocationTable = LocationTable (IntMap LocationChunk)

data Allocation = Allocation Int LocationTable

allocateFunction :: FunctionIr -> Either String Allocation
allocateFunction (FunctionIr _ _ blocks) =
  uncurry Allocation <$> allocateInstrs 0 locationTableEmpty (concatMap blockInstrs blocks)

lookupLocation :: Temp -> Allocation -> Either String Location
lookupLocation temp (Allocation _ locations) = case lookupEntry temp locations of
  Just loc -> Right loc
  Nothing -> Left ("missing allocation for " ++ renderTemp temp)

stackSlotCount :: Allocation -> Int
stackSlotCount (Allocation slots _) = slots

allocateInstrs :: Int -> LocationTable -> [Instr] -> Either String (Int, LocationTable)
allocateInstrs nextSlot acc instrs = case instrs of
  [] -> Right (nextSlot, acc)
  instr:rest -> case instr of
    IParam temp _ ->
      allocateDef nextSlot acc temp rest
    IAlloca temp size ->
      allocateStackObject nextSlot acc temp size rest
    IConst temp _ ->
      allocateDef nextSlot acc temp rest
    IConstBytes temp _ ->
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

allocateStackObject :: Int -> LocationTable -> Temp -> Int -> [Instr] -> Either String (Int, LocationTable)
allocateStackObject nextSlot acc temp size rest =
  if allocationMember temp acc
  then allocateInstrs nextSlot acc rest
  else
    let slots = (max 1 size + 7) `div` 8
    in allocateInstrs (nextSlot + slots) (insertEntry temp (StackObject nextSlot slots) acc) rest

allocateDef :: Int -> LocationTable -> Temp -> [Instr] -> Either String (Int, LocationTable)
allocateDef nextSlot acc temp rest =
  if allocationMember temp acc
  then allocateInstrs nextSlot acc rest
  else allocateInstrs (nextSlot + 1) (insertEntry temp (OnStack nextSlot) acc) rest

allocationMember :: Temp -> LocationTable -> Bool
allocationMember temp entries = case lookupEntry temp entries of
  Just _ -> True
  Nothing -> False

insertEntry :: Temp -> Location -> LocationTable -> LocationTable
insertEntry (Temp key) loc entries =
  locationTableInsert key loc entries

lookupEntry :: Temp -> LocationTable -> Maybe Location
lookupEntry (Temp key) entries =
  locationTableLookup key entries

locationTableEmpty :: LocationTable
locationTableEmpty = LocationTable intMapEmpty

locationTableLookup :: Int -> LocationTable -> Maybe Location
locationTableLookup key table = case table of
  LocationTable chunks -> case intMapLookup (locationChunkIndex key) chunks of
    Nothing -> Nothing
    Just chunk -> locationChunkLookup (locationChunkOffset key) chunk

locationTableInsert :: Int -> Location -> LocationTable -> LocationTable
locationTableInsert key value table = case table of
  LocationTable chunks ->
    let chunkIndex = locationChunkIndex key
        offset = locationChunkOffset key
        oldChunk = case intMapLookup chunkIndex chunks of
          Just chunk -> chunk
          Nothing -> emptyLocationChunk
        newChunk = locationChunkInsert offset value oldChunk
    in LocationTable (intMapInsert chunkIndex newChunk chunks)

locationChunkSize :: Int
locationChunkSize = 2

locationChunkIndex :: Int -> Int
locationChunkIndex key = key `div` locationChunkSize

locationChunkOffset :: Int -> Int
locationChunkOffset key = key `mod` locationChunkSize

emptyLocationChunk :: LocationChunk
emptyLocationChunk = LocationChunk Nothing Nothing

locationChunkLookup :: Int -> LocationChunk -> Maybe Location
locationChunkLookup offset chunk = case chunk of
  LocationChunk a b ->
    if offset == 0
    then a
    else b

locationChunkInsert :: Int -> Location -> LocationChunk -> LocationChunk
locationChunkInsert offset value chunk = case chunk of
  LocationChunk a b ->
    if offset == 0
    then LocationChunk (Just value) b
    else LocationChunk a (Just value)

blockInstrs :: BasicBlock -> [Instr]
blockInstrs (BasicBlock _ instrs _) = instrs
