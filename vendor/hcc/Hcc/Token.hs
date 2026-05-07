module Token
  ( SrcPos(..)
  , Span(..)
  , Token(..)
  , TokenKind(..)
  , tokenText
  , renderToken
  ) where

data SrcPos = SrcPos Int Int
  deriving (Eq, Show)

data Span = Span SrcPos SrcPos
  deriving (Eq, Show)

data Token = Token Span TokenKind
  deriving (Eq, Show)

data TokenKind
  = TokIdent String
  | TokInt String
  | TokChar String
  | TokString String
  | TokPunct String
  | TokDirective String
  deriving (Eq, Show)

tokenText :: TokenKind -> String
tokenText kind = case kind of
  TokIdent s -> s
  TokInt s -> s
  TokChar s -> s
  TokString s -> s
  TokPunct s -> s
  TokDirective s -> s

renderToken :: Token -> String
renderToken (Token (Span (SrcPos line col) _) kind) =
  show line ++ ":" ++ show col ++ " " ++ renderKind kind ++ " " ++ show (tokenText kind)

renderKind :: TokenKind -> String
renderKind kind = case kind of
  TokIdent _ -> "ident"
  TokInt _ -> "int"
  TokChar _ -> "char"
  TokString _ -> "string"
  TokPunct _ -> "punct"
  TokDirective _ -> "directive"
