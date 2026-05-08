module Token where

import Base

data SrcPos = SrcPos Int Int
  deriving (Eq)

data Span = Span SrcPos SrcPos
  deriving (Eq)

data Token = Token Span TokenKind
  deriving (Eq)

data TokenKind
  = TokIdent String
  | TokInt String
  | TokChar String
  | TokString String
  | TokPunct String
  | TokDirective String
  deriving (Eq)

tokenText :: TokenKind -> String
tokenText kind = case kind of
  TokIdent s -> s
  TokInt s -> s
  TokChar s -> s
  TokString s -> s
  TokPunct s -> s
  TokDirective s -> s
