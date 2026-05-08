module Token where

import Base

data SrcPos = SrcPos Int Int

data Span = Span SrcPos SrcPos

data Token = Token Span TokenKind

data TokenKind
  = TokIdent String
  | TokInt String
  | TokChar String
  | TokString String
  | TokPunct String
  | TokDirective String

tokenText :: TokenKind -> String
tokenText kind = case kind of
  TokIdent s -> s
  TokInt s -> s
  TokChar s -> s
  TokString s -> s
  TokPunct s -> s
  TokDirective s -> s
