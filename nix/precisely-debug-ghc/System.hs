module System where

import Prelude hiding (getChar, putChar, getContents, putStr, putStrLn, interact, print)
import Base
import qualified Prelude as P
import qualified System.Environment as Env

putChar :: Char -> IO ()
putChar = P.putChar

getChar :: IO Char
getChar = P.getChar

isEOF :: IO Bool
isEOF = P.null <$> P.getContents >>= \case
  True -> pure True
  False -> error "System.isEOF is not available in the GHC debug shim"

putStr :: String -> IO ()
putStr = P.putStr

putStrLn :: String -> IO ()
putStrLn = P.putStrLn

print :: Show a => a -> IO ()
print = P.print

getContents :: IO String
getContents = P.getContents

interact :: (String -> String) -> IO ()
interact = P.interact

getArgs :: IO [String]
getArgs = Env.getArgs
