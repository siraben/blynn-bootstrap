module System (getArgs, getContents, putStr, putStrLn) where

import Prelude (IO, String, getContents, putStr, putStrLn)
import qualified System.Environment as Env

getArgs :: IO [String]
getArgs = Env.getArgs
