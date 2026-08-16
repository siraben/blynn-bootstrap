module ScopeMap
  ( ScopeMap
  , scopeMapEmpty
  , scopeMapEnter
  , scopeMapLeave
  , scopeMapHide
  , scopeMapInsert
  , scopeMapLookup
  ) where

import Base
import SymbolTable

data ScopeMap a = ScopeMap (SymbolMap (Maybe a)) [SymbolMap (Maybe a)]

scopeMapEmpty :: ScopeMap a
scopeMapEmpty = ScopeMap symbolMapEmpty []

scopeMapEnter :: ScopeMap a -> ScopeMap a
scopeMapEnter (ScopeMap current parents) = ScopeMap symbolMapEmpty (current:parents)

scopeMapLeave :: ScopeMap a -> ScopeMap a
scopeMapLeave (ScopeMap _ []) = scopeMapEmpty
scopeMapLeave (ScopeMap _ (parent:parents)) = ScopeMap parent parents

scopeMapInsert :: String -> a -> ScopeMap a -> ScopeMap a
scopeMapInsert key value (ScopeMap current parents) =
  ScopeMap (symbolMapInsert key (Just value) current) parents

scopeMapHide :: String -> ScopeMap a -> ScopeMap a
scopeMapHide key (ScopeMap current parents) =
  ScopeMap (symbolMapInsert key Nothing current) parents

scopeMapLookup :: String -> ScopeMap a -> Maybe a
scopeMapLookup key (ScopeMap current parents) = lookupScopes (current:parents)
  where
    lookupScopes [] = Nothing
    lookupScopes (scope:rest) = case symbolMapLookup key scope of
      Just value -> value
      Nothing -> lookupScopes rest
