module Base
  ( module Prelude
  , Alternative(..)
  , asum
  , find
  , foldM
  , intercalate
  , intersperse
  , intersect
  , nub
  , partition
  , union
  , when
  , unless
  , (\\)
  , (&)
  , bool
  ) where

import Control.Applicative (Alternative(..), asum)
import Control.Monad (foldM, unless, when)
import Data.Bool (bool)
import Data.Function ((&))
import Data.List (find, intercalate, intersperse, intersect, nub, partition, union, (\\))
import Prelude
