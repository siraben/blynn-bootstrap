module TextBuilder where

import Base

data TextBuilder = TextBuilder Int (String -> String)

textEmpty :: TextBuilder
textEmpty = TextBuilder 0 id

textChar :: Char -> TextBuilder
textChar c = TextBuilder 1 (c:)

textString :: String -> TextBuilder
textString text = TextBuilder (length text) (text++)

textShowInt :: Int -> TextBuilder
textShowInt value = textString (show value)

textAppend :: TextBuilder -> TextBuilder -> TextBuilder
textAppend left right = case left of
  TextBuilder leftLen leftBuild -> case right of
    TextBuilder rightLen rightBuild ->
      TextBuilder (leftLen + rightLen) (leftBuild . rightBuild)

textConcat :: [TextBuilder] -> TextBuilder
textConcat builders = case builders of
  [] -> textEmpty
  builder:rest -> textAppend builder (textConcat rest)

textIntercalate :: TextBuilder -> [TextBuilder] -> TextBuilder
textIntercalate sep builders = case builders of
  [] -> textEmpty
  [builder] -> builder
  builder:rest -> textAppend builder (textAppend sep (textIntercalate sep rest))

textRender :: TextBuilder -> String
textRender builder = case builder of
  TextBuilder _ build -> build ""

textLength :: TextBuilder -> Int
textLength builder = case builder of
  TextBuilder len _ -> len
