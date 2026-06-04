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
scopeMapLookup key (ScopeMap current parents) = lookupScopes (current:parents)
  where
    lookupScopes [] = Nothing
    lookupScopes (scope:rest) = case symbolMapLookup key scope of
      Just value -> Just value
      Nothing -> lookupScopes rest
