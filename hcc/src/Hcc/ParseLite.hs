module ParseLite where

import Base

data Consumed a = Consumed a | Unconsumed a

data Reply tok err a
  = Ok a [tok]
  | Error err

data P env tok err a = P { runP :: env -> [tok] -> Consumed (Reply tok err a) }

instance Functor (P env tok err) where
  fmap f p = P $ \env toks -> mapConsumed (runP p env toks)
    where
      mapConsumed consumed = case consumed of
        Unconsumed x -> Unconsumed (mapReply x)
        Consumed x -> Consumed (mapReply x)

      mapReply reply = case reply of
        Ok x rest -> Ok (f x) rest
        Error err -> Error err

instance Applicative (P env tok err) where
  pure x = P $ \_env toks -> Unconsumed (Ok x toks)
  pf <*> px = do
    f <- pf
    x <- px
    pure (f x)

instance Monad (P env tok err) where
  return = pure
  p >>= f = P $ \env toks -> case runP p env toks of
    Unconsumed reply -> case reply of
      Error err -> Unconsumed (Error err)
      Ok x rest -> runP (f x) env rest
    Consumed reply -> Consumed (case reply of
      Error err -> Error err
      Ok x rest -> forceConsumed (runP (f x) env rest))

forceConsumed :: Consumed a -> a
forceConsumed consumed = case consumed of
  Unconsumed x -> x
  Consumed x -> x

parseRest :: P env tok err a -> env -> [tok] -> Either err (a, [tok])
parseRest p env toks = case forceConsumed (runP p env toks) of
  Error err -> Left err
  Ok x rest -> Right (x, rest)

pEnv :: P env tok err env
pEnv = P $ \env toks -> Unconsumed (Ok env toks)

pRaw :: (env -> [tok] -> Consumed (Reply tok err a)) -> P env tok err a
pRaw action = P action

pFail :: err -> P env tok err a
pFail err = P $ \_env _toks -> Unconsumed (Error err)

pPeekMaybe :: P env tok err (Maybe tok)
pPeekMaybe = P $ \_env toks -> Unconsumed (Ok (case toks of { [] -> Nothing; tok:_ -> Just tok }) toks)

pTake :: err -> P env tok err tok
pTake eofErr = P $ \_env toks -> case toks of
  [] -> Unconsumed (Error eofErr)
  tok:rest -> Consumed (Ok tok rest)

pSatisfy :: (tok -> Bool) -> err -> P env tok err (Maybe tok)
pSatisfy predicate _err = P $ \_env toks -> case toks of
  tok:rest | predicate tok -> Consumed (Ok (Just tok) rest)
  _ -> Unconsumed (Ok Nothing toks)

pExpect :: (tok -> Maybe a) -> err -> P env tok err a
pExpect match err = do
  tok <- pTake err
  case match tok of
    Just x -> pure x
    Nothing -> pFail err

pTry :: P env tok err a -> P env tok err a
pTry p = P $ \env toks -> case runP p env toks of
  Consumed (Error err) -> Unconsumed (Error err)
  other -> other

pOptional :: P env tok err a -> P env tok err (Maybe a)
pOptional p = P $ \env toks -> case runP p env toks of
  Unconsumed (Error _) -> Unconsumed (Ok Nothing toks)
  Unconsumed (Ok x rest) -> Unconsumed (Ok (Just x) rest)
  Consumed (Ok x rest) -> Consumed (Ok (Just x) rest)
  Consumed (Error err) -> Consumed (Error err)

pMany :: P env tok err a -> P env tok err [a]
pMany p = go id where
  go acc = do
    mx <- pOptional p
    case mx of
      Nothing -> pure (acc [])
      Just x -> go (acc . (x:))

pManyUntil :: P env tok err Bool -> P env tok err a -> P env tok err [a]
pManyUntil done item = do
  stop <- done
  if stop
    then pure []
    else do
      x <- item
      xs <- pManyUntil done item
      pure (x:xs)
