module LowerBootstrap
  ( registerBuiltinStructs
  ) where

import Base
import TypesAst
import CompileM

registerBuiltinStructs :: CompileM ()
registerBuiltinStructs = do
  bindStruct "tm" False tmFields
  bindStruct "timeval" False timevalFields
  bindStruct "__IO_FILE" False fileStructFields
  bindStruct "FILE" False fileStructFields

tmFields :: [Field]
tmFields =
  [ Field CInt "tm_sec" Nothing
  , Field CInt "tm_min" Nothing
  , Field CInt "tm_hour" Nothing
  , Field CInt "tm_mday" Nothing
  , Field CInt "tm_mon" Nothing
  , Field CInt "tm_year" Nothing
  , Field CInt "tm_wday" Nothing
  , Field CInt "tm_yday" Nothing
  , Field CInt "tm_isdst" Nothing
  ]

timevalFields :: [Field]
timevalFields =
  [ Field CLong "tv_sec" Nothing
  , Field CLong "tv_usec" Nothing
  ]

fileStructFields :: [Field]
fileStructFields =
  [ Field CInt "fd" Nothing
  , Field CInt "bufmode" Nothing
  , Field CInt "bufpos" Nothing
  , Field CInt "file_pos" Nothing
  , Field CInt "buflen" Nothing
  , Field (CPtr CChar) "buffer" Nothing
  , Field (CPtr (CStruct "__IO_FILE")) "next" Nothing
  , Field (CPtr (CStruct "__IO_FILE")) "prev" Nothing
  ]
