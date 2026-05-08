module ScopeMap where

import Base
import SymbolTable

data ScopeMap a = ScopeMap (SymbolMap a) [SymbolMap a]

scopeMapEmpty :: ScopeMap a
scopeMapEmpty = ScopeMap symbolMapEmpty []

scopeMapEnter :: ScopeMap a -> ScopeMap a
scopeMapEnter scoped = case scoped of
  ScopeMap current parents -> ScopeMap symbolMapEmpty (current:parents)

scopeMapLeave :: ScopeMap a -> ScopeMap a
scopeMapLeave scoped = case scoped of
  ScopeMap _ [] -> scopeMapEmpty
  ScopeMap _ (parent:parents) -> ScopeMap parent parents

scopeMapInsert :: String -> a -> ScopeMap a -> ScopeMap a
scopeMapInsert key value scoped = case scoped of
  ScopeMap current parents -> ScopeMap (symbolMapInsert key value current) parents

scopeMapLookup :: String -> ScopeMap a -> Maybe a
scopeMapLookup key scoped = case scoped of
  ScopeMap current parents -> case symbolMapLookup key current of
    Just value -> Just value
    Nothing -> lookupParents parents
  where
    lookupParents parents = case parents of
      [] -> Nothing
      parent:rest -> case symbolMapLookup key parent of
        Just value -> Just value
        Nothing -> lookupParents rest
