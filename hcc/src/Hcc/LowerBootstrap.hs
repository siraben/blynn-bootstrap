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
  [ Field CInt "tm_sec"
  , Field CInt "tm_min"
  , Field CInt "tm_hour"
  , Field CInt "tm_mday"
  , Field CInt "tm_mon"
  , Field CInt "tm_year"
  , Field CInt "tm_wday"
  , Field CInt "tm_yday"
  , Field CInt "tm_isdst"
  ]

timevalFields :: [Field]
timevalFields =
  [ Field CLong "tv_sec"
  , Field CLong "tv_usec"
  ]

fileStructFields :: [Field]
fileStructFields =
  [ Field CInt "fd"
  , Field CInt "bufmode"
  , Field CInt "bufpos"
  , Field CInt "file_pos"
  , Field CInt "buflen"
  , Field (CPtr CChar) "buffer"
  , Field (CPtr (CStruct "__IO_FILE")) "next"
  , Field (CPtr (CStruct "__IO_FILE")) "prev"
  ]
