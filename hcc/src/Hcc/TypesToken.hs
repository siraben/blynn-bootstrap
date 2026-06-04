module TypesToken
  ( SrcPos(..)
  , Span(..)
  , Token(..)
  , TokenKind(..)
  , tokenText
  ) where

import Base

data SrcPos = SrcPos Int Int

data Span = Span SrcPos SrcPos

data Token = Token Span TokenKind

data TokenKind
  = TokIdent String
  | TokInt String
  | TokFloat String
  | TokChar String
  | TokString String
  | TokPunct String
  | TokDirective String

tokenText :: TokenKind -> String
tokenText (TokIdent s) = s
tokenText (TokInt s) = s
tokenText (TokFloat s) = s
tokenText (TokChar s) = s
tokenText (TokString s) = s
tokenText (TokPunct s) = s
tokenText (TokDirective s) = s
