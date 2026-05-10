module ScopeMap
  ( ScopeMap
  , scopeMapEmpty
  , scopeMapEnter
  , scopeMapLeave
  , scopeMapInsert
  , scopeMapLookup
  ) where

import Base
import SymbolTable

data ScopeMap a = ScopeMap (SymbolMap a) [SymbolMap a]

scopeMapEmpty :: ScopeMap a
scopeMapEmpty = ScopeMap symbolMapEmpty []

scopeMapEnter :: ScopeMap a -> ScopeMap a
scopeMapEnter (ScopeMap current parents) = ScopeMap symbolMapEmpty (current:parents)

scopeMapLeave :: ScopeMap a -> ScopeMap a
scopeMapLeave (ScopeMap _ []) = scopeMapEmpty
scopeMapLeave (ScopeMap _ (parent:parents)) = ScopeMap parent parents

scopeMapInsert :: String -> a -> ScopeMap a -> ScopeMap a
scopeMapInsert key value (ScopeMap current parents) =
  ScopeMap (symbolMapInsert key value current) parents

scopeMapLookup :: String -> ScopeMap a -> Maybe a
scopeMapLookup key (ScopeMap current parents) = case symbolMapLookup key current of
  Just value -> Just value
  Nothing -> lookupParents parents
  where
    lookupParents [] = Nothing
    lookupParents (parent:rest) = case symbolMapLookup key parent of
      Just value -> Just value
      Nothing -> lookupParents rest
